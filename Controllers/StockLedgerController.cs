using ItemApi.Interface;
using ItemApi.Models;
using Microsoft.AspNetCore.Mvc;

namespace ItemApi.Controllers
{
    // Stock balance and item card (movement history). Read-only — stock only changes through
    // GRN/PRN Commit, StockAdjustment and till sales (api/Sync).
    [Route("api/[controller]")]
    [ApiController]
    public class StockLedgerController : ControllerBase
    {
        private readonly IStockLedgerRepository _repository;

        public StockLedgerController(IStockLedgerRepository repository)
        {
            _repository = repository;
        }

        // GET: api/StockLedger/Balance/5
        [HttpGet("Balance/{itemId}")]
        public async Task<IActionResult> GetBalance(int itemId)
        {
            try
            {
                var result = await _repository.GetBalanceAsync(itemId);
                if (result == null)
                    return NotFound(new { message = $"Item {itemId} not found.", status = false });

                return Ok(result);
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = "Internal Server Error", error = ex.Message });
            }
        }

        // POST: api/StockLedger/SearchBalances
        [HttpPost("SearchBalances")]
        public async Task<IActionResult> SearchBalances([FromBody] StockBalanceSearchRequest request)
        {
            try
            {
                var result = await _repository.SearchBalancesAsync(request);
                return Ok(result);
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = "Internal Server Error", error = ex.Message });
            }
        }

        // GET: api/StockLedger/ItemCard?itemId=5&fromDate=2026-09-01&toDate=2026-09-30
        [HttpGet("ItemCard")]
        public async Task<IActionResult> ItemCard([FromQuery] int itemId, [FromQuery] DateTime? fromDate, [FromQuery] DateTime? toDate)
        {
            if (itemId <= 0)
                return BadRequest(new { message = "ItemId is required." });

            try
            {
                var to = toDate ?? DateTime.Today;
                var from = fromDate ?? to.AddDays(-30);

                var result = await _repository.GetItemCardAsync(itemId, from, to);
                if (result == null)
                    return NotFound(new { message = $"Item {itemId} not found.", status = false });

                return Ok(result);
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = "Internal Server Error", error = ex.Message });
            }
        }
    }
}
