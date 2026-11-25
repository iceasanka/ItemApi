using ItemApi.Models;
using ItemApi.Interface;
using ItemApi.Service;
using Microsoft.AspNetCore.Mvc;

namespace ItemApi.Controllers
{
    // Back office Day Reports — one day, any time after it: per till sales / payments / drawer cash, the Zs (day ends),
    // opening cash / paid in / paid out, items sold, bills and a bill copy. Docs/StockSystem.md §6.25.
    [Route("api/[controller]")]
    [ApiController]
    public class DayReportController : ControllerBase
    {
        private readonly IDayReportRepository _repository;
        private readonly PrinterConfig _printers;

        public DayReportController(IDayReportRepository repository, PrinterConfig printers)
        {
            _repository = repository;
            _printers = printers;
        }

        // GET: api/DayReport?date=2026-10-22&terminalId=   (no date = today, no terminalId = all tills)
        // → { date, terminalId, tills: [...], zReports: [...], cashMovements: [...] }
        [HttpGet]
        public async Task<IActionResult> Day([FromQuery] DateTime? date, [FromQuery] int? terminalId)
        {
            try
            {
                return Ok(await _repository.GetDayAsync((date ?? DateTime.Today).Date, terminalId));
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = "Internal Server Error", error = ex.Message });
            }
        }

        // GET: api/DayReport/Items?date=2026-10-22&terminalId=
        [HttpGet("Items")]
        public async Task<IActionResult> Items([FromQuery] DateTime? date, [FromQuery] int? terminalId)
        {
            try
            {
                return Ok(await _repository.GetItemsAsync((date ?? DateTime.Today).Date, terminalId));
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = "Internal Server Error", error = ex.Message });
            }
        }

        // GET: api/DayReport/Bills?date=2026-10-22&terminalId=   (voided bills too, Status 9)
        [HttpGet("Bills")]
        public async Task<IActionResult> Bills([FromQuery] DateTime? date, [FromQuery] int? terminalId)
        {
            try
            {
                return Ok(await _repository.GetBillsAsync((date ?? DateTime.Today).Date, terminalId));
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = "Internal Server Error", error = ex.Message });
            }
        }

        // GET: api/DayReport/Loss?date=2026-10-22&terminalId=   voids & No Sale, for stopping cash loss
        // → { date, terminalId, cashiers: [...], voids: [...], noSales: [...] }
        [HttpGet("Loss")]
        public async Task<IActionResult> Loss([FromQuery] DateTime? date, [FromQuery] int? terminalId)
        {
            try
            {
                return Ok(await _repository.GetLossAsync((date ?? DateTime.Today).Date, terminalId));
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = "Internal Server Error", error = ex.Message });
            }
        }

        // GET: api/DayReport/Abandoned?date=2026-10-22&terminalId=   bills found still open after a till restart
        // (power cut, crash) → { date, terminalId, bills: [...], lines: [...] }
        [HttpGet("Abandoned")]
        public async Task<IActionResult> Abandoned([FromQuery] DateTime? date, [FromQuery] int? terminalId)
        {
            try
            {
                return Ok(await _repository.GetAbandonedAsync((date ?? DateTime.Today).Date, terminalId));
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = "Internal Server Error", error = ex.Message });
            }
        }

        // GET: api/DayReport/BankCheque?from=2026-11-01&to=2026-11-03&terminalId=&payType=&status=
        // Every bank transfer (payType 5) / cheque (payType 6) payment of the bills dated from..to (both included, at most
        // 366 days), voided bills left out, refund bills negative. No payType = both. No dates = today.
        // status (U060): none = all, 0 = pending only, 1 = received only.
        [HttpGet("BankCheque")]
        public async Task<IActionResult> BankCheque([FromQuery] DateTime? from, [FromQuery] DateTime? to,
                                                    [FromQuery] int? terminalId, [FromQuery] int? payType, [FromQuery] int? status)
        {
            if (status is not (null or 0 or 1))
                return BadRequest(new { message = "Status must be 0 (pending) or 1 (received)." });
            var f = (from ?? to ?? DateTime.Today).Date;
            var t = (to ?? from ?? DateTime.Today).Date;
            if (t < f)
                return BadRequest(new { message = "The To date is before the From date." });
            if ((t - f).TotalDays > 366)
                return BadRequest(new { message = "Pick at most one year." });
            if (payType is not (null or 5 or 6))
                return BadRequest(new { message = "Pay type must be 5 (bank transfer) or 6 (cheque)." });

            try
            {
                return Ok(await _repository.GetBankChequeAsync(f, t, terminalId, payType, status));
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = "Internal Server Error", error = ex.Message });
            }
        }

        // POST: api/DayReport/BankCheque/Status { received, receivedDate, note, lines: [{ invoiceId, lineNum }] } (U060)
        // received true = the cheque was handed over / the transfer reached the bank on receivedDate (marking again
        // changes the date / note); false = back to pending. → { changed }
        [HttpPost("BankCheque/Status")]
        public async Task<IActionResult> BankChequeStatus([FromBody] BankChequeStatusRequest request)
        {
            if (request == null || request.Lines.Count == 0)
                return BadRequest(new { message = "Tick at least one bank transfer or cheque." });
            if (request.Received && request.ReceivedDate == null)
                return BadRequest(new { message = "Pick the date it was received." });
            if (request.Note?.Trim().Length > 200)
                return BadRequest(new { message = "Note: at most 200 letters." });

            try
            {
                var me = AuthTokenService.UserId(User);
                return Ok(new { changed = await _repository.SetBankChequeStatusAsync(request, me > 0 ? me : null) });
            }
            catch (Microsoft.Data.SqlClient.SqlException ex) when (ex.Number == 50000)
            {
                // the proc's own checks (date before the bill, not a bank / cheque line ...)
                return BadRequest(new { message = ex.Message });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = "Internal Server Error", error = ex.Message });
            }
        }

        // POST: api/DayReport/BankCheque/Ref { invoiceId, lineNum, refNo } (U074)
        // Correct the transfer reference / cheque no of one line (empty = none); the change is logged. → { changed }
        [HttpPost("BankCheque/Ref")]
        public async Task<IActionResult> BankChequeRef([FromBody] BankChequeRefRequest request)
        {
            if (request == null || request.InvoiceId <= 0 || request.LineNum <= 0)
                return BadRequest(new { message = "Pick a bank transfer or cheque." });
            if (request.RefNo?.Trim().Length > 30)
                return BadRequest(new { message = "Reference / cheque no: at most 30 letters." });

            try
            {
                var me = AuthTokenService.UserId(User);
                return Ok(new { changed = await _repository.SetBankChequeRefAsync(request, me > 0 ? me : null) });
            }
            catch (Microsoft.Data.SqlClient.SqlException ex) when (ex.Number == 50000)
            {
                return BadRequest(new { message = ex.Message });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = "Internal Server Error", error = ex.Message });
            }
        }

        // GET: api/DayReport/Bill/T01-00000038 → the bill with its lines and payments (bill copy)
        [HttpGet("Bill/{invoiceNo}")]
        public async Task<IActionResult> Bill(string invoiceNo)
        {
            if (string.IsNullOrWhiteSpace(invoiceNo))
                return BadRequest(new { message = "Bill number is required." });

            try
            {
                var bill = await _repository.GetBillAsync(invoiceNo);
                if (bill == null)
                    return NotFound(new { message = $"Bill {invoiceNo} is not on the back office (not uploaded yet, or a wrong number)." });
                return Ok(bill);
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = "Internal Server Error", error = ex.Message });
            }
        }

        // POST: api/DayReport/Bill/T01-00000038/Print?shop=... → the bill copy straight on the bill printer (thermal) of
        // Settings > Printers, no print preview. shop = the name on top (the page's shop name).
        [HttpPost("Bill/{invoiceNo}/Print")]
        public async Task<IActionResult> PrintBill(string invoiceNo, [FromQuery] string? shop)
        {
            if (string.IsNullOrWhiteSpace(invoiceNo))
                return BadRequest(new { message = "Bill number is required." });

            try
            {
                var bill = await _repository.GetBillAsync(invoiceNo.Trim());
                if (bill == null)
                    return NotFound(new { message = $"Bill {invoiceNo} is not on the back office (not uploaded yet, or a wrong number)." });
                var p = await _printers.GetAsync();
                var slip = ReceiptSlip.BillCopy(bill, p.BillChars, shop, DateTime.Now);
                await slip.PrintAsync(p.NeedBill(), "Bill copy " + bill.InvoiceNo, p.BillEscPos);
                return Ok(new { message = $"Bill {bill.InvoiceNo} sent to the bill printer." });
            }
            catch (InvalidOperationException ex)
            {
                // no bill printer chosen, or it is not installed on the server
                return BadRequest(new { message = ex.Message });
            }
            catch (Exception ex)
            {
                Serilog.Log.Error(ex, "Bill copy {Bill} not printed", invoiceNo);
                return StatusCode(500, new { message = $"Not printed: {ex.Message}" });
            }
        }
    }
}
