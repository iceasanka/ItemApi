
using ItemApi.Data;
using ItemApi.Models;
using ItemApi.Service;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;
using ItemApi.Interface;
using Microsoft.Data.SqlClient;


namespace ItemApi.Controllers
{
    [Route("api/[controller]")]
    [ApiController]
    public class UtilController : ControllerBase
    {
        private readonly IChequeCreateRepository _repository;
        private readonly AppDbContext _context;
        private readonly PrinterConfig _printers;
        public UtilController(IChequeCreateRepository repository, AppDbContext context, PrinterConfig printers)
        {
            _printers = printers;
            _repository = repository;
            _context = context;
        }


        // GET: api/Util/BackupRunning — any signed-in user: the daily / "Back up now" backup is running now
        // (the back office shows "Backup in progress - please wait" on every page while it runs). { running, db, since }
        [HttpGet("BackupRunning")]
        public IActionResult BackupRunning([FromServices] DbBackupService backup) =>
            Ok(new { running = backup.Running, db = backup.RunningDb, since = backup.RunningSince });

        [HttpPost("print")]
        public async Task<ActionResult> Print([FromBody] PrintRequest data)
        {
            // Cash Management > Print (all the data): the bill printer of Settings > Printers
            try
            {
                var p = await _printers.GetAsync();
                var slip = ReceiptSlip.CashManagement(data, p.BillChars, DateTime.Now);
                await slip.PrintAsync(p.NeedBill(), "Cash management", p.BillEscPos);
                return Ok(new { message = "Cash management printed." });
            }
            catch (Exception ex)
            {
                Serilog.Log.Error(ex, "Cash management print failed");
                return BadRequest(new { message = $"Could not print: {ex.Message}" });
            }
        }



        // Cheque Writer > Print Cheque: check -> save -> print -> Google sheet. No BarTender / LocalPrintAgent:
        // Service/ChequePrinter.cs draws it on the general printer (Settings > Printers) with the layout of Cheque Writer > Cheque layout.
        // Everything that can be checked is checked BEFORE the cheque is saved (it fits, the printer is there, its
        // queue is empty). A print problem after the save does not undo the save: the answer says printed = false and
        // the page offers "Print again" (api/ChequePrint/reprint).
        [HttpPost("printCheque")]
        public async Task<ActionResult> PrintCheque([FromBody] Cheque cheque)
        {
            try
            {
                var printer = (await _printers.GetAsync()).General;   // empty = refused below (CheckPrinter)
                if (await _repository.ChequeNumberExistsAsync(cheque.chequeNumber))
                    return Conflict(new { code = "DUPLICATE_CHEQUE_NUMBER", message = $"Cheque number {cheque.chequeNumber} already exists." });
                var billsError = cheque.BillsError();
                if (billsError != null)
                    return BadRequest(new { message = billsError });

                var layout = (await _context.GetChequeLayoutAsync()).Layout;
                var data = new ChequePrintData
                {
                    Payee = cheque.payee ?? "",
                    Amount = cheque.amount,
                    AmountInWords = cheque.amountInWords ?? "",
                    ChequeDate = cheque.chequeDate,
                    AcPayee = cheque.acPayee,
                };
                var laid = ChequePrinter.Lay(layout, data);
                if (laid.Problems.Count > 0)
                    return BadRequest(new { message = "Not printed, not saved: " + string.Join(" ", laid.Problems) });
                try
                {
                    ChequePrinter.CheckPrinter(printer);
                }
                catch (ChequePrintException ex)
                {
                    return BadRequest(new { message = ex.Message });
                }

                // with a supplier it is also a PAYMENT in the supplier ledger (§6.19); a cheque the ledger refuses
                // (bill already paid, ...) is not printed
                ChequeCreate chequeCreate;
                try
                {
                    chequeCreate = await _repository.WriteChequeAsync(cheque);
                }
                catch (SqlException ex) when (ex.Number >= 50000)
                {
                    // the first error is the proc's message; inside our transaction SQL adds "Transaction count ..." ones after it
                    return BadRequest(new { message = ex.Errors.Count > 0 ? ex.Errors[0].Message : ex.Message });
                }

                string? printError = null;
                try
                {
                    await Task.Run(() => ChequePrinter.Print(printer, layout, laid, $"Cheque {cheque.chequeNumber}", test: false));
                    Serilog.Log.Information("Cheque {No} printed (Rs {Amount}, {Date:yyyy-MM-dd})", cheque.chequeNumber, cheque.amount, cheque.chequeDate);
                }
                catch (Exception ex)
                {
                    printError = ex.Message;
                    Serilog.Log.Error(ex, "Cheque {No} saved but not printed", cheque.chequeNumber);
                }

                // Google sheet (AsankaTemp) - a sheet problem does not make the cheque look unsaved / unprinted
                string? syncError = null;
                try
                {
                    await _repository.SyncPrintedChequeAsync(chequeCreate);
                    chequeCreate.IsSync = 1;
                    await _repository.UpdateChequeAsync(chequeCreate);
                }
                catch (Exception syncEx)
                {
                    syncError = syncEx.Message;
                    Serilog.Log.Error(syncEx, "Cheque {No}: Google sheet update failed", cheque.chequeNumber);
                }

                return Ok(new
                {
                    message = printError == null ? $"Cheque {cheque.chequeNumber} printed." : $"Cheque {cheque.chequeNumber} was SAVED but did NOT print: {printError}",
                    chequeNumber = cheque.chequeNumber,
                    printed = printError == null,
                    printError,
                    syncError,
                });
            }
            catch (Exception ex)
            {
                Serilog.Log.Error(ex, "printCheque failed");
                return BadRequest(new { message = $"Could not write the cheque: {ex.Message}" });
            }
        }


        [HttpPost("printCashierSettlement")]
        public async Task<ActionResult> PrintCashierSettlement([FromBody] CashierSettlement settlement)
        {
            try
            {
                // the bill printer of Settings > Printers (no BarTender, no LocalPrintAgent)
                var p = await _printers.GetAsync();
                var slip = ReceiptSlip.Settlement(settlement, p.BillChars, DateTime.Now);
                await slip.PrintAsync(p.NeedBill(), "Cashier settlement", p.BillEscPos);
                return Ok(new { message = "Settlement printed." });
            }
            catch (Exception ex)
            {
                Serilog.Log.Error(ex, "Settlement print failed");
                return BadRequest(new { message = $"Could not print the settlement: {ex.Message}" });
            }
        }




    }
}
