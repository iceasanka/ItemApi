using ItemApi.Interface;
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

        public DayReportController(IDayReportRepository repository)
        {
            _repository = repository;
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
    }
}
