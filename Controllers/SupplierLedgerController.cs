using ItemApi.Interface;
using ItemApi.Models;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;
using Serilog;

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
