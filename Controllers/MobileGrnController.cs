using ItemApi.Interface;
using ItemApi.Models;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;
using Serilog;

namespace ItemApi.Controllers
{
    // Mobile GRN on the new system (Docs/StockSystem.md §6.23, U017). The phone scans a delivery into a suspended GRN of
    // the supplier (one open draft per supplier); the back office opens it on the GRN Entry page, checks it and commits it
    // to stock. Replaces api/GrnTemp (old tables) for the mobile app.
    [Route("api/[controller]")]
    [ApiController]
    public class MobileGrnController : ControllerBase
    {
        private readonly IMobileGrnRepository _repository;

        public MobileGrnController(IMobileGrnRepository repository)
        {
            _repository = repository;
        }

        // GET: api/MobileGrn?suppId=5 — the supplier's open draft lines, newest first (empty = no draft yet)
        [HttpGet]
        public Task<IActionResult> Get([FromQuery] int suppId) =>
            Run(async () =>
            {
                if (suppId <= 0) return BadRequest(new { message = "Select the supplier." });
                return Ok(await _repository.GetAsync(suppId));
            });

        // POST: api/MobileGrn/line — { suppId, itemId, qty, costPrice, sellPrice } -> { grnNo, idx }
        [HttpPost("line")]
        public Task<IActionResult> AddLine([FromBody] MobileGrnAddRequest request) =>
            Run(async () =>
            {
                if (request == null || request.ItemId <= 0) return BadRequest(new { message = "Scan an item first." });
                if (request.SuppId <= 0) return BadRequest(new { message = "Select the supplier." });
                return Ok(await _repository.AddLineAsync(request));
            });

        // PUT: api/MobileGrn/line/12 — { qty, costPrice, sellPrice }
        [HttpPut("line/{idx:int}")]
        public Task<IActionResult> UpdateLine(int idx, [FromBody] MobileGrnUpdateRequest request) =>
            Run(async () =>
            {
                if (request == null) return BadRequest(new { message = "Nothing to save." });
                return Ok(await _repository.UpdateLineAsync(idx, request));
            });

        // DELETE: api/MobileGrn/line/12 -> { grnNo, linesLeft } (0 = the empty draft was deleted too)
        [HttpDelete("line/{idx:int}")]
        public Task<IActionResult> DeleteLine(int idx) =>
            Run(async () => Ok(await _repository.DeleteLineAsync(idx)));

        // proc business errors (RAISERROR 50000) -> 400 { message }
        private static async Task<IActionResult> Run(Func<Task<IActionResult>> action)
        {
            try
            {
                return await action();
            }
            catch (SqlException ex) when (ex.Number >= 50000)
            {
                return new BadRequestObjectResult(new { message = ex.Message });
            }
            catch (Exception ex)
            {
                Log.Error($"MobileGrn error: {ex.Message}");
                return new ObjectResult(new { message = "Internal Server Error", error = ex.Message }) { StatusCode = 500 };
            }
        }
    }
}
