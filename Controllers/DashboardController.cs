using ItemApi.Interface;
using Microsoft.AspNetCore.Mvc;

namespace ItemApi.Controllers
{
    // Home page sales (today, live) and sales analysis (date range). Live updates: SignalR /hubs/sales sends
    // "salesChanged" when a till uploads new bills (Dashboard:LivePush). Docs/StockSystem.md §6.9.
    [Route("api/[controller]")]
    [ApiController]
    public class DashboardController : ControllerBase
    {
        private const int MaxDays = 366;

        private readonly IDashboardRepository _repository;

        public DashboardController(IDashboardRepository repository)
        {
            _repository = repository;
        }

        // GET: api/Dashboard/Today?terminalId=   (no terminalId = all tills)
        [HttpGet("Today")]
        public async Task<IActionResult> Today([FromQuery] int? terminalId)
        {
            try
            {
                return Ok(await _repository.GetTodayAsync(terminalId));
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = "Internal Server Error", error = ex.Message });
            }
        }

        // GET: api/Dashboard/Sales?fromDate=2026-10-01&toDate=2026-10-31&terminalId=&top=20
        [HttpGet("Sales")]
        public async Task<IActionResult> Sales([FromQuery] DateTime? fromDate, [FromQuery] DateTime? toDate,
                                               [FromQuery] int? terminalId, [FromQuery] int top = 20)
        {
            var to = (toDate ?? DateTime.Today).Date;
            var from = (fromDate ?? to.AddDays(-29)).Date;
            if (from > to)
                return BadRequest(new { message = "From date must be on or before To date." });
            if ((to - from).TotalDays >= MaxDays)
                return BadRequest(new { message = $"Choose at most {MaxDays} days." });
            if (top is < 1 or > 100)
                return BadRequest(new { message = "Top must be between 1 and 100." });

            try
            {
                return Ok(await _repository.GetSalesAsync(from, to, terminalId, top));
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = "Internal Server Error", error = ex.Message });
            }
        }
    }
}
