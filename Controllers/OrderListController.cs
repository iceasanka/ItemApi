using ItemApi.Data;
using ItemApi.Models;
using ItemApi.Service;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;
using Serilog;

namespace ItemApi.Controllers
{
    // Tools > Order Lists (Docs/StockSystem.md §6.39, U063): lists of the items we order from another shop (Nandana,
    // Serina, Naginda at first). Printed with a blank qty column - the qty is written on the paper by hand. Only the
    // lists are kept (changed any time); nothing is ordered, no history.
    [Route("api/[controller]")]
    [ApiController]
    public class OrderListController : ControllerBase
    {
        private const string Blank = "______";

        private readonly AppDbContext _db;
        private readonly PrinterConfig _printers;

        public OrderListController(AppDbContext db, PrinterConfig printers)
        {
            _db = db;
            _printers = printers;
        }

        // GET: api/OrderList → [{ listId, name, lines: [{ lineId, itemId, descrip, refCode, barcode, active, note }] }]
        [HttpGet]
        public Task<IActionResult> Get() => Run(async () => Ok(await _db.OrderListGetAsync()));

        // POST: api/OrderList { name, kind: 1 order list / 2 code list } → { listId }
        [HttpPost]
        public Task<IActionResult> Add([FromBody] OrderListNameRequest r) =>
            Run(async () => Ok(new { listId = await _db.OrderListSaveAsync(null, r?.Name, r?.Kind ?? 1) }));

        // PUT: api/OrderList/5 { name } - rename
        [HttpPut("{listId:int}")]
        public Task<IActionResult> Rename(int listId, [FromBody] OrderListNameRequest r) =>
            Run(async () => Ok(new { listId = await _db.OrderListSaveAsync(listId, r?.Name) }));

        // PUT: api/OrderList/5/Sinhala { sinhala } - print the items' Sinhala names (an item with none: its English name)
        [HttpPut("{listId:int}/Sinhala")]
        public Task<IActionResult> SetSinhala(int listId, [FromBody] OrderListSinhalaRequest r) =>
            Run(async () => { await _db.OrderListSetSinhalaAsync(listId, r?.Sinhala == true); return Ok(new { message = "Saved." }); });

        // DELETE: api/OrderList/5 - the list and its lines
        [HttpDelete("{listId:int}")]
        public Task<IActionResult> Delete(int listId) =>
            Run(async () => { await _db.OrderListDeleteAsync(listId); return Ok(new { message = "List deleted." }); });

        // POST: api/OrderList/5/Lines { itemId } or { text } (+ note) → { lineId }
        [HttpPost("{listId:int}/Lines")]
        public Task<IActionResult> AddLine(int listId, [FromBody] OrderListLineRequest r) =>
            Run(async () => Ok(new { lineId = await _db.OrderListAddLineAsync(listId, r ?? new OrderListLineRequest()) }));

        // PUT: api/OrderList/Lines/7 { note, text } - text only for a text line
        [HttpPut("Lines/{lineId:int}")]
        public Task<IActionResult> UpdateLine(int lineId, [FromBody] OrderListLineRequest r) =>
            Run(async () => { await _db.OrderListUpdateLineAsync(lineId, r ?? new OrderListLineRequest()); return Ok(new { message = "Saved." }); });

        // DELETE: api/OrderList/Lines/7
        [HttpDelete("Lines/{lineId:int}")]
        public Task<IActionResult> RemoveLine(int lineId) =>
            Run(async () => { await _db.OrderListRemoveLineAsync(lineId); return Ok(new { message = "Removed." }); });

        // POST: api/OrderList/Lines/7/Move?up=true
        [HttpPost("Lines/{lineId:int}/Move")]
        public Task<IActionResult> MoveLine(int lineId, [FromQuery] bool up) =>
            Run(async () => { await _db.OrderListMoveLineAsync(lineId, up); return Ok(new { message = "Moved." }); });

        // POST: api/OrderList/5/SortByName?byCode= - the whole list A-Z, or by ref code
        [HttpPost("{listId:int}/SortByName")]
        public Task<IActionResult> SortByName(int listId, [FromQuery] bool byCode = false) =>
            Run(async () => { await _db.OrderListSortByNameAsync(listId, byCode); return Ok(new { message = byCode ? "Sorted by code." : "Sorted A-Z." }); });

        // POST: api/OrderList/5/Print { spaced } - on the bill printer (thermal) of Settings > Printers:
        //   NAME (big), Date ______, then a line a item "1 NAME (note) ______" (a long name wraps; the blank is on its last
        //   line), spaced = an empty line under each to write on. A4 is printed by the page (browser).
        [HttpPost("{listId:int}/Print")]
        public Task<IActionResult> Print(int listId, [FromBody] OrderListPrintRequest? r) =>
            Run(async () =>
            {
                var list = (await _db.OrderListGetAsync()).FirstOrDefault(l => l.ListId == listId);
                if (list == null) return NotFound(new { message = "The list is not there any more." });
                if (list.Lines.Count == 0) return BadRequest(new { message = "The list is empty - add items first." });
                var spaced = r?.Spaced ?? true;
                try
                {
                    var p = await _printers.GetAsync();
                    var slip = new ReceiptSlip(p.BillChars);
                    slip.Line(list.Name.ToUpperInvariant(), SlipAlign.Center, bold: true, tall: true);
                    slip.Line("ORDER LIST", SlipAlign.Center);
                    slip.Line();
                    slip.LeftRight("Date ____________", $"{list.Lines.Count} items");
                    slip.Line();
                    slip.LeftRight("Item", "Qty", bold: true);
                    slip.Divider();
                    var n = 0;
                    var numW = list.Lines.Count.ToString().Length + 1;
                    foreach (var l in list.Lines)
                    {
                        n++;
                        var name = string.IsNullOrWhiteSpace(l.Note) ? l.Descrip : $"{l.Descrip} ({l.Note})";
                        var room = slip.Width - numW - 1 - Blank.Length - 1;
                        var parts = Wrap(name, room).ToList();
                        for (var i = 0; i < parts.Count; i++)
                        {
                            var lead = i == 0 ? n.ToString().PadLeft(numW - 1) + " " : new string(' ', numW);
                            if (i < parts.Count - 1) slip.Line(lead + parts[i]);
                            else slip.LeftRight(lead + parts[i], Blank);
                        }
                        if (spaced) slip.Line();
                    }
                    slip.Divider();
                    slip.Line($"Printed {DateTime.Now:yyyy-MM-dd HH:mm}", SlipAlign.Center);
                    await slip.PrintAsync(p.NeedBill(), "Order list " + list.Name, p.BillEscPos);
                    return Ok(new { message = "Sent to the bill printer." });
                }
                catch (InvalidOperationException ex)
                {
                    // no bill printer chosen, or not installed on the server
                    return BadRequest(new { message = ex.Message });
                }
            });

        private static IEnumerable<string> Wrap(string text, int width)
        {
            text = (text ?? "").Trim();
            width = Math.Max(8, width);
            while (text.Length > width)
            {
                var cut = text.LastIndexOf(' ', width);
                if (cut <= 0) cut = width;
                yield return text[..cut].TrimEnd();
                text = text[cut..].TrimStart();
            }
            yield return text;
        }

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
            catch (SqlException ex) when (ex.Number == 208 || ex.Number == 2812)
            {
                // table / proc missing
                return new ObjectResult(new { message = "Order lists are not set up on the database - run U063." }) { StatusCode = 503 };
            }
            catch (Exception ex)
            {
                Log.Error(ex, "Order list");
                return new ObjectResult(new { message = "Internal Server Error", error = ex.Message }) { StatusCode = 500 };
            }
        }
    }
}
