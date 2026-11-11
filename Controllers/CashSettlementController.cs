using System.Text.Json;
using ItemApi.Common;
using ItemApi.Data;
using ItemApi.Models;
using ItemApi.Service;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace ItemApi.Controllers
{
    // Cash Management saved (DBScript U055): the till's cash counted in the back office, what goes back to the till and
    // the cash to bank. The slip (bill printer) has the barcode CS-<till>-<id>: scanned on that till at day end it fills
    // the counted cash (and links the Z - its Avg_Cash on the cheque sheet = this cash to bank), scanned at the next
    // opening cash it fills the opening cash.
    [Route("api/[controller]")]
    [ApiController]
    public class CashSettlementController : ControllerBase
    {
        private readonly AppDbContext _db;
        private readonly PrinterConfig _printers;

        public CashSettlementController(AppDbContext db, PrinterConfig printers)
        {
            _db = db;
            _printers = printers;
        }

        // GET api/CashSettlement?from=2026-11-01&to=2026-11-11&search=CS-T01&top=500 - slips counted in the dates
        // (both optional) matching the search, newest first
        [HttpGet]
        public async Task<IActionResult> List([FromQuery] DateTime? from, [FromQuery] DateTime? to,
                                              [FromQuery] string? search, [FromQuery] int top = 500) =>
            await Run(async () => Ok(await _db.GetCashSettlementsAsync(from, to, search, top)));

        // GET api/CashSettlement/Cashiers - users who work on the till (the page's cashier list)
        [HttpGet("Cashiers")]
        public async Task<IActionResult> Cashiers() => await Run(async () => Ok(await _db.GetTillCashiersAsync()));

        // POST api/CashSettlement { terminalId, cashierId, cashTable, creditTable, debitTable, cashierCash, print }
        // The totals are worked out here from the rows (the page shows the same). Saved first; a print problem does not
        // undo the save (printed false + printError - Reprint on the page).
        [HttpPost]
        public async Task<IActionResult> Save([FromBody] CashSettlementSaveRequest req) => await Run(async () =>
        {
            if (req == null || req.TerminalId <= 0)
                return BadRequest(new { message = "Choose the till." });
            if (req.CashierCash < 0)
                return BadRequest(new { message = "Cashier cash can not be below 0." });

            var t = Totals(req.CashTable, req.CreditTable, req.DebitTable);
            var detail = JsonSerializer.Serialize(new { cashTable = req.CashTable, creditTable = req.CreditTable, debitTable = req.DebitTable });
            var s = await _db.SaveCashSettlementAsync(req.TerminalId, req.CashierId, t.Counted, t.CashIn, t.CashOut,
                                                      req.CashierCash, t.Coins, detail, Who());
            var answer = new CashSettlementSaveResponse { Settlement = s };
            if (req.Print)
                (answer.Printed, answer.PrintError) = await PrintAsync(s, req.CashTable, req.CreditTable, req.DebitTable);
            return Ok(answer);
        });

        // POST api/CashSettlement/12/print - the same slip again
        [HttpPost("{id:int}/print")]
        public async Task<IActionResult> Reprint(int id) => await Run(async () =>
        {
            var s = await _db.GetCashSettlementAsync(id);
            if (s == null)
                return NotFound(new { message = $"Cash slip {id} not found." });
            var d = string.IsNullOrEmpty(s.Detail) ? null : JsonSerializer.Deserialize<SavedTables>(s.Detail, Json);
            var (printed, error) = await PrintAsync(s, d?.CashTable ?? new(), d?.CreditTable ?? new(), d?.DebitTable ?? new());
            return printed ? Ok(new { printed, message = "Cash slip printed." }) : BadRequest(new { printed, message = error });
        });

        // DELETE api/CashSettlement/12 - a wrong count (counted again), before the till used the slip
        [HttpDelete("{id:int}")]
        public async Task<IActionResult> Delete(int id) => await Run(async () =>
        {
            var s = await _db.GetCashSettlementAsync(id);
            if (s == null)
                return NotFound(new { message = $"Cash slip {id} not found." });
            await _db.DeleteCashSettlementAsync(id);
            Serilog.Log.Information("Cash slip {Id} deleted by {Who} (till {Till}, counted {Counted}, cash to bank {Bank})",
                id, Who(), s.TerminalCode, s.CountedCash, s.BankCash);
            return Ok(new { message = $"Cash slip {id} deleted." });
        });

        // ─────────────────────────────────────────────────────────────────────────

        private static readonly JsonSerializerOptions Json = new() { PropertyNameCaseInsensitive = true };

        private class SavedTables
        {
            public TableData CashTable { get; set; } = new();
            public TableData CreditTable { get; set; } = new();
            public TableData DebitTable { get; set; } = new();
        }

        // counted = every note / coin x qty; coins = the notes / coins of 100 and below (all go back to the till)
        private static (decimal Counted, decimal Coins, decimal CashIn, decimal CashOut) Totals(TableData cash, TableData credit, TableData debit)
        {
            decimal counted = 0, coins = 0;
            foreach (var row in cash.Rows)
            {
                var note = ReceiptSlip.Num(row, "cash");
                var value = note * ReceiptSlip.Num(row, "qty");
                counted += value;
                if (note <= 100)
                    coins += value;
            }
            return (counted, coins, credit.Rows.Sum(r => ReceiptSlip.Num(r, "amount")), debit.Rows.Sum(r => ReceiptSlip.Num(r, "amount")));
        }

        private async Task<(bool, string?)> PrintAsync(CashSettlementRow s, TableData cash, TableData credit, TableData debit)
        {
            try
            {
                var p = await _printers.GetAsync();
                cash.Total = s.CountedCash;
                credit.Total = s.CashIn;
                debit.Total = s.CashOut;
                var r = new PrintRequest
                {
                    CashTable = cash, CreditTable = credit, DebitTable = debit,
                    TotalCashBalance = s.CountedCash + s.CashIn - s.CashOut,
                    CashierCash = s.CashierCash, ReturnedCoinsValue = s.ReturnedCoins,
                    TotalReturnedToCashier = s.ReturnedCash, FinalCashBalance = s.BankCash,
                };
                var slip = ReceiptSlip.CashManagement(r, p.BillChars, DateTime.Now, s);
                await slip.PrintAsync(p.NeedBill(), "Cash slip " + s.SettlementId, p.BillEscPos);
                return (true, null);
            }
            catch (Exception ex)
            {
                Serilog.Log.Error(ex, "Cash slip {Id} not printed", s.SettlementId);
                return (false, $"Saved, but not printed: {ex.Message}");
            }
        }

        private async Task<IActionResult> Run(Func<Task<IActionResult>> work)
        {
            try
            {
                return await work();
            }
            catch (SqlException ex) when (ex.Number >= 50000)
            {
                return BadRequest(new { message = ex.Message });
            }
            catch (SqlException ex) when (ex.Number == 2812)
            {
                return BadRequest(new { message = "Run the back office update U055 first (cash slips)." });
            }
            catch (Exception ex)
            {
                Serilog.Log.Error(ex, "Cash settlement failed");
                return StatusCode(500, new { message = "Internal Server Error", error = ex.Message });
            }
        }

        private string? Who() => User.Identity?.Name ?? (User.CurrentUserId() is int id ? $"user {id}" : null);
    }
}
