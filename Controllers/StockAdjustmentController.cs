using ItemApi.Interface;
using ItemApi.Models;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace ItemApi.Controllers
{
    // Stock adjustments can be saved any time; each save is posted to stock at once (ADJ00000001).
    // Count mode lines (CountedQty) should be done while all tills are synced — the UI checks
    // GET api/Sync/Terminals and warns about IsStale tills first. See Docs/StockSystem.md.
    [Route("api/[controller]")]
    [ApiController]
    public class StockAdjustmentController : ControllerBase
    {
        private readonly IStockAdjustmentRepository _repository;

        public StockAdjustmentController(IStockAdjustmentRepository repository)
        {
            _repository = repository;
        }

        // GET: api/StockAdjustment/Reasons
        [HttpGet("Reasons")]
        public async Task<IActionResult> Reasons()
        {
            try
            {
                return Ok(await _repository.GetReasonsAsync());
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = "Internal Server Error", error = ex.Message });
            }
        }

        // POST: api/StockAdjustment/Save
        [HttpPost("Save")]
        public async Task<IActionResult> Save([FromBody] StockAdjustmentRequest request)
        {
            if (request == null || request.Lines == null || request.Lines.Count == 0)
                return BadRequest(new { message = "Add at least one line." });

            try
            {
                var result = await _repository.SaveAsync(request);
                return Ok(new { message = $"Adjustment {result.AdjNo} saved and posted to stock.", data = result });
            }
            catch (SqlException ex) when (ex.Number >= 50000)
            {
                // validation raised by z_sp_SaveStockAdjustment
                return BadRequest(new { message = ex.Message });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = "Internal Server Error", error = ex.Message });
            }
        }

        // GET: api/StockAdjustment/GetByAdjNo/ADJ00000001
        [HttpGet("GetByAdjNo/{adjNo}")]
        public async Task<IActionResult> GetByAdjNo(string adjNo)
        {
            try
            {
                var result = await _repository.GetByAdjNoAsync(adjNo);
                if (result == null)
                    return NotFound(new { message = $"Adjustment {adjNo} not found.", status = false });

                return Ok(result);
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = "Internal Server Error", error = ex.Message });
            }
        }

        // POST: api/StockAdjustment/Search
        [HttpPost("Search")]
        public async Task<IActionResult> Search([FromBody] StockAdjustmentSearchRequest request)
        {
            try
            {
                return Ok(await _repository.SearchAsync(request));
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = "Internal Server Error", error = ex.Message });
            }
        }
    }
}
