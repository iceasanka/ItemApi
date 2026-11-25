using ItemApi.Common;
using ItemApi.Data;
using ItemApi.Models;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace ItemApi.Controllers
{
    // Back office > Reports (DBScript U057 / 36_BackOffice_Reports.sql):
    //   Period report  - sales, profit, payments taken, paid in / out, supplier bills and payments, stock in, per day / month
    //   Payments       - every cheque, supplier transfer, till paid in / out and bank / cheque bill in a date range
    //   Stock health   - minus / zero stock, items not sold or not moved for a long time; deactivate unused items
    //   Discount items - items sold with an item / bill discount, their bills, and the discounts set on items (U075)
    [Route("api/[controller]")]
    [ApiController]
    public class ReportController : ControllerBase
    {
        private readonly AppDbContext _db;

        public ReportController(AppDbContext db) => _db = db;

        // GET api/Report/Period?from=2026-01-01&to=2026-11-30&month=true
        [HttpGet("Period")]
        public Task<IActionResult> Period([FromQuery] DateTime from, [FromQuery] DateTime to, [FromQuery] bool month = false) =>
            Run(async () =>
            {
                if (to < from)
                    return BadRequest(new { message = "The To date is before the From date." });
                if (!month && (to - from).TotalDays > 400)
                    return BadRequest(new { message = "Up to 400 days per day - pick By month for a longer period." });
                if ((to - from).TotalDays > 3700)
                    return BadRequest(new { message = "Up to 10 years." });
                var rows = await _db.GetRptPeriodAsync(from, to, month);
                var stock = await _db.GetRptStockNowAsync();
                return Ok(new RptPeriodResponse { Rows = rows, Stock = stock });
            });

        // GET api/Report/Money?from=2026-11-01&to=2026-11-30&chequeByDate=false
        [HttpGet("Money")]
        public Task<IActionResult> Money([FromQuery] DateTime from, [FromQuery] DateTime to, [FromQuery] bool chequeByDate = false) =>
            Run(async () =>
            {
                if (to < from)
                    return BadRequest(new { message = "The To date is before the From date." });
                if ((to - from).TotalDays > 3700)
                    return BadRequest(new { message = "Up to 10 years." });
                return Ok(await _db.GetRptMoneyAsync(from, to, chequeByDate));
            });

        // GET api/Report/StockHealth?inactive=false
        [HttpGet("StockHealth")]
        public Task<IActionResult> StockHealth([FromQuery] bool inactive = false) =>
            Run(async () => Ok(await _db.GetRptStockHealthAsync(inactive)));

        // GET api/Report/DiscountItems?from=2026-11-01&to=2026-11-30 - items sold with an item / bill discount (U075)
        [HttpGet("DiscountItems")]
        public Task<IActionResult> DiscountItems([FromQuery] DateTime from, [FromQuery] DateTime to) =>
            Run(async () =>
            {
                if (to < from)
                    return BadRequest(new { message = "The To date is before the From date." });
                if ((to - from).TotalDays > 3700)
                    return BadRequest(new { message = "Up to 10 years." });
                return Ok(await _db.GetRptDiscountItemsAsync(from, to));
            }, "U075");

        // GET api/Report/DiscountLines?from=..&to=..&itemId=123 - the discounted bill lines of one item (0 = other items)
        [HttpGet("DiscountLines")]
        public Task<IActionResult> DiscountLines([FromQuery] DateTime from, [FromQuery] DateTime to, [FromQuery] int itemId) =>
            Run(async () =>
            {
                if (to < from)
                    return BadRequest(new { message = "The To date is before the From date." });
                if (itemId < 0)
                    return BadRequest(new { message = "Pick an item." });
                return Ok(await _db.GetRptDiscountLinesAsync(from, to, itemId));
            }, "U075");

        // GET api/Report/DiscountSetup - active items with a discount set now (or marked no discount)
        [HttpGet("DiscountSetup")]
        public Task<IActionResult> DiscountSetup() =>
            Run(async () => Ok(await _db.GetRptDiscountSetupAsync()), "U075");

        // POST api/Report/DiscountClear { ids: [1, 2] } - clears the discount % / Rs set on the items (as clearing them in
        // Item Entry); the tills take it at their next item sync. The old values go to the log.
        [HttpPost("DiscountClear")]
        public Task<IActionResult> DiscountClear([FromBody] RptIdsRequest req) =>
            Run(async () =>
            {
                var ids = req?.Ids?.Where(i => i > 0).Distinct().ToList() ?? new();
                if (ids.Count == 0)
                    return BadRequest(new { message = "Tick the items first." });
                if (ids.Count > 5000)
                    return BadRequest(new { message = "Up to 5000 items at a time." });
                var done = await _db.ClearItemDiscountsAsync(ids);
                Serilog.Log.Information("{Who} cleared the discount of {N} items (ItemId:old%/oldRs): {Old}", Who(), done.Count,
                    string.Join(",", done.Select(d => $"{d.ItemId}:{d.OldPercent}/{d.OldAmount}")));
                return Ok(new { changed = done.Count, message = $"Discount cleared on {done.Count} item(s)." });
            }, "U075");

        // POST api/Report/ItemStatus { ids: [1, 2], active: false } - Admin only. Deactivated items stop selling on the
        // tills at their next item sync; nothing is deleted (bills / GRNs keep them). Refused for an item with stock.
        [Authorize(Roles = UserRoles.AdminName)]
        [HttpPost("ItemStatus")]
        public Task<IActionResult> ItemStatus([FromBody] RptItemStatusRequest req) =>
            Run(async () =>
            {
                var ids = req?.Ids?.Where(i => i > 0).Distinct().ToList() ?? new();
                if (ids.Count == 0)
                    return BadRequest(new { message = "Tick the items first." });
                if (ids.Count > 5000)
                    return BadRequest(new { message = "Up to 5000 items at a time." });
                var n = await _db.SetItemsActiveAsync(ids, req!.Active);
                Serilog.Log.Information("{Who} {What} {N} items: {Ids}", Who(), req.Active ? "activated" : "deactivated", n,
                    string.Join(",", ids.Take(200)));
                return Ok(new { changed = n, message = $"{n} item(s) {(req.Active ? "activated" : "deactivated")}." });
            });

        private async Task<IActionResult> Run(Func<Task<IActionResult>> work, string update = "U057")
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
                return BadRequest(new { message = $"Run the back office update {update} first (reports)." });
            }
            catch (Exception ex)
            {
                Serilog.Log.Error(ex, "Report failed");
                return StatusCode(500, new { message = "Internal Server Error", error = ex.Message });
            }
        }

        private string? Who() => User.Identity?.Name ?? (User.CurrentUserId() is int id ? $"user {id}" : null);
    }
}
