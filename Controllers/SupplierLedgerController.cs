using ItemApi.Interface;
using ItemApi.Models;
using Microsoft.AspNetCore.Mvc;
using Serilog;

namespace ItemApi.Controllers
{
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
        [HttpGet("{suppId}")]
        public async Task<ActionResult<List<SupplierLedger>>> GetLedgerBySuppId(int suppId)
        {
            try
            {
                if (suppId <= 0)
                    return BadRequest(new { message = "Invalid SuppId." });

                var result = await _repository.GetLedgerBySuppIdAsync(suppId);
                return Ok(result);
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex.Message}");
                return StatusCode(500, new { message = "Internal Server Error", error = ex.Message });
            }
        }

        // POST: api/SupplierLedger/search
        [HttpPost("search")]
        public async Task<ActionResult<List<SupplierLedger>>> SearchByDateRange(
            [FromBody] SupplierLedgerSearchRequest request)
        {
            try
            {
                if (request.SuppId <= 0)
                    return BadRequest(new { message = "Invalid SuppId." });

                List<SupplierLedger> result;

                if (request.FromDate.HasValue && request.ToDate.HasValue)
                {
                    result = await _repository.GetLedgerByDateRangeAsync(
                        request.SuppId,
                        request.FromDate.Value,
                        request.ToDate.Value);
                }
                else
                {
                    result = await _repository.GetLedgerBySuppIdAsync(request.SuppId);
                }

                return Ok(result);
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex.Message}");
                return StatusCode(500, new { message = "Internal Server Error", error = ex.Message });
            }
        }

        // GET: api/SupplierLedger/summary/{suppId}
        [HttpGet("summary/{suppId}")]
        public async Task<ActionResult<SupplierLedgerSummary>> GetSupplierSummary(int suppId)
        {
            try
            {
                if (suppId <= 0)
                    return BadRequest(new { message = "Invalid SuppId." });

                var result = await _repository.GetSupplierSummaryAsync(suppId);

                if (result == null)
                    return NotFound(new { message = $"No ledger records found for SuppId {suppId}." });

                return Ok(result);
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex.Message}");
                return StatusCode(500, new { message = "Internal Server Error", error = ex.Message });
            }
        }

        // POST: api/SupplierLedger
        [HttpPost]
        public async Task<ActionResult<SupplierLedger>> AddLedger([FromBody] SupplierLedger ledger)
        {
            try
            {
                if (ledger == null || ledger.SuppId <= 0)
                    return BadRequest(new { message = "Invalid ledger data." });

                if (ledger.Type < 1 || ledger.Type > 3)
                    return BadRequest(new { message = "Type must be 1 (PURCHASE), 2 (PAYMENT), or 3 (RETURN)." });

                if (ledger.DebitAmount > 0 && ledger.CreditAmount > 0)
                    return BadRequest(new { message = "Only DebitAmount or CreditAmount can be set, not both." });

                if (ledger.DebitAmount == 0 && ledger.CreditAmount == 0)
                    return BadRequest(new { message = "Either DebitAmount or CreditAmount must be greater than 0." });

                var result = await _repository.AddLedgerAsync(ledger);
                return CreatedAtAction(nameof(GetLedgerBySuppId), new { suppId = result.SuppId }, result);
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex.Message}");
                return StatusCode(500, new { message = "Internal Server Error", error = ex.Message });
            }
        }

        // PUT: api/SupplierLedger/{ledgerId}
        [HttpPut("{ledgerId}")]
        public async Task<ActionResult<SupplierLedger>> UpdateLedger(int ledgerId, [FromBody] SupplierLedger ledger)
        {
            try
            {
                if (ledgerId != ledger.LedgerId)
                    return BadRequest(new { message = "LedgerId mismatch." });

                if (ledger.Type < 1 || ledger.Type > 3)
                    return BadRequest(new { message = "Type must be 1 (PURCHASE), 2 (PAYMENT), or 3 (RETURN)." });

                if (ledger.DebitAmount > 0 && ledger.CreditAmount > 0)
                    return BadRequest(new { message = "Only DebitAmount or CreditAmount can be set, not both." });

                var result = await _repository.UpdateLedgerAsync(ledger);
                return Ok(new { message = "Ledger entry updated successfully.", data = result });
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex.Message}");
                return StatusCode(500, new { message = "Internal Server Error", error = ex.Message });
            }
        }

        // DELETE: api/SupplierLedger/{ledgerId}
        [HttpDelete("{ledgerId}")]
        public async Task<ActionResult> DeleteLedger(int ledgerId)
        {
            try
            {
                if (ledgerId <= 0)
                    return BadRequest(new { message = "Invalid LedgerId." });

                var deleted = await _repository.DeleteLedgerAsync(ledgerId);

                if (!deleted)
                    return NotFound(new { message = $"Ledger entry with Id {ledgerId} not found.", status = false });

                return Ok(new { message = "Ledger entry deleted successfully.", status = true });
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex.Message}");
                return StatusCode(500, new { message = "Internal Server Error", error = ex.Message });
            }
        }
    }
}
