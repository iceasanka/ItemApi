using ItemApi.Common;
using ItemApi.Data;
using ItemApi.Interface;
using ItemApi.Models;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using Serilog;
using System.Security.Cryptography;
using System.Text;

namespace ItemApi.Controllers
{
    // Supplier ledger: bills (PURCHASE, the "pencil note" before the GRN), payments and returns.
    // Bills get a due date from the supplier's cheque period; the cheque writer pays them (Docs/StockSystem.md §6.19).
    [Route("api/[controller]")]
    [ApiController]
    public class SupplierLedgerController : ControllerBase
    {
        private readonly ISupplierLedgerRepository _repository;

        public SupplierLedgerController(ISupplierLedgerRepository repository)
        {
            _repository = repository;
        }

        // GET: api/SupplierLedger/{suppId}
        [HttpGet("{suppId:int}")]
        public Task<IActionResult> GetLedgerBySuppId(int suppId) =>
            Run(async () =>
            {
                if (suppId <= 0)
                    return BadRequest(new { message = "Invalid SuppId." });
                return Ok(await _repository.GetLedgerBySuppIdAsync(suppId));
            });

        // POST: api/SupplierLedger/search
        [HttpPost("search")]
        public Task<IActionResult> SearchByDateRange([FromBody] SupplierLedgerSearchRequest request) =>
            Run(async () =>
            {
                if (request.SuppId <= 0)
                    return BadRequest(new { message = "Invalid SuppId." });

                var result = request.FromDate.HasValue && request.ToDate.HasValue
                    ? await _repository.GetLedgerByDateRangeAsync(request.SuppId, request.FromDate.Value, request.ToDate.Value)
                    : await _repository.GetLedgerBySuppIdAsync(request.SuppId);
                return Ok(result);
            });

        // GET: api/SupplierLedger/summary/{suppId}
        [HttpGet("summary/{suppId:int}")]
        public Task<IActionResult> GetSupplierSummary(int suppId) =>
            Run(async () =>
            {
                if (suppId <= 0)
                    return BadRequest(new { message = "Invalid SuppId." });

                var result = await _repository.GetSupplierSummaryAsync(suppId);
                if (result == null)
                    return NotFound(new { message = $"No ledger records found for SuppId {suppId}." });
                return Ok(result);
            });

        // GET: api/SupplierLedger/invoices/{suppId}?includePaid=false — the supplier's bills for the cheque writer:
        // open ones first (oldest due first), with what is paid, what is open and the cheques that paid them
        [HttpGet("invoices/{suppId:int}")]
        public Task<IActionResult> GetInvoices(int suppId, [FromQuery] bool includePaid = false) =>
            Run(async () =>
            {
                if (suppId <= 0)
                    return BadRequest(new { message = "Invalid SuppId." });
                return Ok(await _repository.GetInvoicesAsync(suppId, includePaid));
            });

        // GET: api/SupplierLedger/due?toDate=2026-11-15&suppId= — open bills due on or before toDate
        // (default today + 30 days), overdue ones too: the "upcoming payments" on the cheque writer
        [HttpGet("due")]
        public Task<IActionResult> GetPaymentsDue([FromQuery] DateTime? toDate, [FromQuery] int? suppId) =>
            Run(async () => Ok(await _repository.GetPaymentsDueAsync(toDate, suppId)));

        // GET: api/SupplierLedger/overview — every supplier with ledger entries: totals, balance, aging of the open bills (U015)
        [HttpGet("overview")]
        public Task<IActionResult> GetOverview() =>
            Run(async () => Ok(await _repository.GetOverviewAsync()));

        // GET: api/SupplierLedger/monthly?suppId=&months=12 — purchases / payments / returns per month (U015)
        [HttpGet("monthly")]
        public Task<IActionResult> GetMonthly([FromQuery] int? suppId, [FromQuery] int months = 12) =>
            Run(async () => Ok(await _repository.GetMonthlyAsync(suppId, months)));

        // POST: api/SupplierLedger — referenceId empty → SUP001-00001; a bill's dueDate empty → txnDate + cheque period.
        // A payment / return may say which bills it pays: allocations [{ ledgerId, amount }]
        [HttpPost]
        public Task<IActionResult> AddLedger([FromBody] SupplierLedger ledger) =>
            Run(async () =>
            {
                var error = Validate(ledger);
                if (error != null)
                    return BadRequest(new { message = error });

                var result = await _repository.AddLedgerAsync(ledger);
                return CreatedAtAction(nameof(GetLedgerBySuppId), new { suppId = result.SuppId }, result);
            });

        // POST: api/SupplierLedger/MarkPaid { suppId, txnDate, remark, ledgerIds } — "Mark as paid" (U052): the ticked
        // returns are set against the ticked bills, what is still open = one PAYMENT; the bills end at 0.
        // → { paymentLedgerId (null = the returns covered the bills), referenceId, paid, returnsUsed }
        [HttpPost("MarkPaid")]
        public Task<IActionResult> MarkPaid([FromBody] SupplierMarkPaidRequest request) =>
            Run(async () =>
            {
                if (request == null || request.SuppId <= 0)
                    return BadRequest(new { message = "Invalid supplier." });
                if (request.LedgerIds == null || request.LedgerIds.Count == 0)
                    return BadRequest(new { message = "Tick at least one bill." });
                if (request.Remark?.Length > 500)
                    return BadRequest(new { message = "Remark: at most 500 letters." });
                var me = ItemApi.Service.AuthTokenService.UserId(User);
                return Ok(await _repository.MarkPaidAsync(request, me > 0 ? me : null));
            });

        // POST: api/SupplierLedger/AdjustBalance { suppId, txnDate, remark } — "Adjust balance to 0" (U053): unused
        // payments / returns are set against open bills, then one adjustment PAYMENT (bills still open) and / or one
        // adjustment PURCHASE (credits still unused) is added. Nothing old is changed; the balance ends at 0.
        [HttpPost("AdjustBalance")]
        public Task<IActionResult> AdjustBalance([FromBody] SupplierAdjustBalanceRequest request) =>
            Run(async () =>
            {
                if (request == null || request.SuppId <= 0)
                    return BadRequest(new { message = "Invalid supplier." });
                if (request.Remark?.Length > 500)
                    return BadRequest(new { message = "Remark: at most 500 letters." });
                var me = ItemApi.Service.AuthTokenService.UserId(User);
                return Ok(await _repository.AdjustBalanceAsync(request, me > 0 ? me : null));
            });

        // PUT: api/SupplierLedger/{ledgerId} — allocations null = the bills it pays stay as they are
        [HttpPut("{ledgerId:int}")]
        public Task<IActionResult> UpdateLedger(int ledgerId, [FromBody] SupplierLedger ledger) =>
            Run(async () =>
            {
                if (ledger == null || ledgerId != ledger.LedgerId)
                    return BadRequest(new { message = "LedgerId mismatch." });
                var error = Validate(ledger);
                if (error != null)
                    return BadRequest(new { message = error });

                var result = await _repository.UpdateLedgerAsync(ledger);
                return Ok(new { message = "Ledger entry updated successfully.", data = result });
            });

        // DELETE: api/SupplierLedger/{ledgerId}
        [HttpDelete("{ledgerId:int}")]
        public Task<IActionResult> DeleteLedger(int ledgerId) =>
            Run(async () =>
            {
                if (ledgerId <= 0)
                    return BadRequest(new { message = "Invalid LedgerId." });

                var deleted = await _repository.DeleteLedgerAsync(ledgerId);
                if (!deleted)
                    return NotFound(new { message = $"Ledger entry with Id {ledgerId} not found.", status = false });
                return Ok(new { message = "Ledger entry deleted successfully.", status = true });
            });

        // ─── ledger entry typed at a till (Menu > Add ledger entry) ───
        // TillService calls these live (tills have no user token) with the shared terminal key (X-Terminal-Key =
        // Sync:TerminalKey, the same check as api/Sync/Cashiers). Saved straight to the ledger, nothing is synced later.

        // GET: api/SupplierLedger/Till/Suppliers → [{ suppId, suppCode, suppName }] (active suppliers, by name)
        [AllowAnonymous]
        [HttpGet("Till/Suppliers")]
        public Task<IActionResult> TillSuppliers([FromServices] AppDbContext db, [FromServices] IConfiguration config) =>
            Run(async () =>
            {
                var refused = CheckTerminalKey(config);
                if (refused != null)
                    return refused;
                return Ok(await db.SupplierEntities.AsNoTracking()
                    .Where(s => s.Status == 1)
                    .OrderBy(s => s.SuppName)
                    .Select(s => new TillSupplierRow { SuppId = s.SuppId, SuppCode = s.SuppCode, SuppName = s.SuppName })
                    .ToListAsync());
            });

        // POST: api/SupplierLedger/Till { terminalId, cashierId, suppId, type (1 PURCHASE / 2 PAYMENT / 3 RETURN), qty, price,
        //   invoiceNo, remark } — amount = qty x price; today's date; a bill's due date from the supplier's cheque period.
        [AllowAnonymous]
        [HttpPost("Till")]
        public Task<IActionResult> AddFromTill([FromBody] TillLedgerRequest req, [FromServices] IConfiguration config) =>
            Run(async () =>
            {
                var refused = CheckTerminalKey(config);
                if (refused != null)
                    return refused;
                if (req == null || req.TerminalId <= 0)
                    return BadRequest(new { message = "TerminalId is required." });
                if (req.SuppId <= 0)
                    return BadRequest(new { message = "Pick the supplier." });
                if (req.Type is < 1 or > 3)
                    return BadRequest(new { message = "Type must be 1 (PURCHASE), 2 (PAYMENT) or 3 (RETURN)." });
                if (req.Qty <= 0 || req.Price <= 0)
                    return BadRequest(new { message = "Qty and price must be more than 0." });
                var amount = Math.Round(req.Qty * req.Price, 2, MidpointRounding.AwayFromZero);
                if (amount <= 0 || amount > 999_999_999m)
                    return BadRequest(new { message = "Check the qty and price (amount out of range)." });
                var invoiceNo = req.InvoiceNo?.Trim();
                if (invoiceNo?.Length > 50)
                    return BadRequest(new { message = "Bill no: max 50 characters." });

                // who typed it, kept with the remark (a till cashier is not a back office user)
                var by = $" [till {req.TerminalId}{(string.IsNullOrWhiteSpace(req.CashierId) ? "" : ", " + req.CashierId.Trim())}]";
                var remark = (req.Remark ?? "").Trim();
                if (remark.Length + by.Length > 500)
                    remark = remark[..Math.Max(0, 500 - by.Length)];

                var ledger = new SupplierLedger
                {
                    SuppId = req.SuppId,
                    TxnDate = DateTime.Today,
                    Type = req.Type,
                    InvoiceNo = string.IsNullOrEmpty(invoiceNo) ? null : invoiceNo,
                    Remark = remark + by,
                    DebitAmount = req.Type == 1 ? amount : 0,
                    CreditAmount = req.Type == 1 ? 0 : amount,
                    DueDate = null, // a bill: TxnDate + the supplier's cheque period
                    Allocations = null,
                };
                var result = await _repository.AddLedgerAsync(ledger);
                Log.Information("Ledger entry {LedgerId} from till {TerminalId} ({CashierId}): supp {SuppId} type {Type} {Amount}",
                    result.LedgerId, req.TerminalId, req.CashierId, req.SuppId, req.Type, amount);
                return Ok(result);
            });

        private IActionResult? CheckTerminalKey(IConfiguration config)
        {
            var key = config["Sync:TerminalKey"];
            if (string.IsNullOrEmpty(key))
                return StatusCode(403, new { message = "Set Sync:TerminalKey on the back office API (and the same key on each till)." });
            var sent = Request.Headers[SyncController.TerminalKeyHeader].ToString();
            if (!CryptographicOperations.FixedTimeEquals(Encoding.UTF8.GetBytes(sent), Encoding.UTF8.GetBytes(key)))
                return StatusCode(403, new { message = "Wrong terminal key (Sync:TerminalKey)." });
            return null;
        }

        // ─── pay from a till (U032, StockSystem.md 6.32) ───

        // GET: api/SupplierLedger/TillPay?suppId=79&status=0 — requests to pay bills in cash at a till (newest first)
        [HttpGet("TillPay")]
        public Task<IActionResult> GetTillPay([FromQuery] int? suppId, [FromQuery] int? status, [FromServices] AppDbContext db) =>
            Run(async () => Ok(await db.GetTillPayRequestsAsync(suppId, status)));

        // POST: api/SupplierLedger/TillPay { suppId, terminalId (null = any till), amount, remark, lines: [{ ledgerId, amount }] }
        //   — bills (and returns) to be paid in cash at a till; the till pays it as a Paid Out and the ledger is settled
        //   when that comes up → { message, requestId }
        [HttpPost("TillPay")]
        public Task<IActionResult> AddTillPay([FromBody] TillPayRequestCreate request, [FromServices] AppDbContext db) =>
            Run(async () =>
            {
                if (request == null || request.SuppId <= 0) return BadRequest(new { message = "Choose the supplier." });
                if (request.Lines.Count == 0) return BadRequest(new { message = "Pick the bills to pay." });
                var id = await db.AddTillPayRequestAsync(request, User.CurrentUserId(request.UserId));
                return Ok(new { message = request.TerminalId == null ? "Sent to the tills - any till can pay it." : "Sent to the till.", requestId = id });
            });

        // POST: api/SupplierLedger/TillPay/5/Cancel — a waiting request taken back (the tills drop it at their next download)
        [HttpPost("TillPay/{requestId:int}/Cancel")]
        public Task<IActionResult> CancelTillPay(int requestId, [FromQuery] int? userId, [FromServices] AppDbContext db) =>
            Run(async () =>
            {
                await db.CancelTillPayRequestAsync(requestId, User.CurrentUserId(userId));
                return Ok(new { message = "Request cancelled." });
            });

        private static string? Validate(SupplierLedger? ledger)
        {
            if (ledger == null || (ledger.SuppId ?? 0) <= 0)
                return "Invalid ledger data.";
            if (ledger.Type < 1 || ledger.Type > 3)
                return "Type must be 1 (PURCHASE), 2 (PAYMENT), or 3 (RETURN).";
            if (ledger.DebitAmount > 0 && ledger.CreditAmount > 0)
                return "Only DebitAmount or CreditAmount can be set, not both.";
            if (ledger.DebitAmount == 0 && ledger.CreditAmount == 0)
                return "Either DebitAmount or CreditAmount must be greater than 0.";
            if (ledger.Allocations != null && ledger.Allocations.GroupBy(a => a.LedgerId).Any(g => g.Count() > 1))
                return "A bill is picked twice.";
            return null;
        }

        // proc business errors (RAISERROR → 50000) → 400 { message }
        private async Task<IActionResult> Run(Func<Task<IActionResult>> action)
        {
            try
            {
                return await action();
            }
            catch (SqlException ex) when (ex.Number >= 50000)
            {
                return BadRequest(new { message = ex.Message });
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex.Message}");
                return StatusCode(500, new { message = "Internal Server Error", error = ex.Message });
            }
        }
    }
}
