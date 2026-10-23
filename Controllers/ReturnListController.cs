using ItemApi.Interface;
using ItemApi.Models;
using ItemApi.Repositories;
using ItemApi.Service;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;
using Serilog;

namespace ItemApi.Controllers
{
    // Return Items list on the new system (Docs/StockSystem.md §6.22, U016). The mobile app scans items into it, the
    // back office Return Items page checks them (Ready) and Process makes a PRN of one supplier's Ready rows — posted
    // to stock at once unless post = false (then commit it on the Goods Return page). Replaces api/Return (old tables).
    [Route("api/[controller]")]
    [ApiController]
    public class ReturnListController : ControllerBase
    {
        private readonly IReturnListRepository _repository;
        private readonly IItemzRepository _itemz;
        private readonly IStockLedgerRepository _stock;

        public ReturnListController(IReturnListRepository repository, IItemzRepository itemz, IStockLedgerRepository stock)
        {
            _repository = repository;
            _itemz = itemz;
            _stock = stock;
        }

        // GET: api/ReturnList?suppId=&status=&days=90 — status empty = open rows (Added + Ready), 3 = PRN made
        [HttpGet]
        public Task<IActionResult> GetList([FromQuery] int? suppId, [FromQuery] int? status, [FromQuery] int days = 90) =>
            Run(async () => Ok(await _repository.GetListAsync(suppId, status, days)));

        // GET: api/ReturnList/Lookup?code= — scanned / typed barcode or code (exact barcode, then ref code, then
        // codes containing it) -> items with cost, retail price, stock now and their own supplier
        [HttpGet("Lookup")]
        public Task<IActionResult> Lookup([FromQuery] string? code) =>
            Run(async () =>
            {
                if (string.IsNullOrWhiteSpace(code))
                    return BadRequest(new { message = "Scan or type a code." });
                var items = (await _itemz.SearchByCodeItemzAsync(code.Trim())).Take(20).ToList();
                var rows = new List<ReturnListLookupRow>();
                foreach (var i in items)
                {
                    var bal = items.Count <= 5 ? await _stock.GetBalanceAsync(i.ItemId) : null;
                    rows.Add(new ReturnListLookupRow
                    {
                        ItemId = i.ItemId, Barcode = i.Barcode, RefCode = i.RefCode, Descrip = i.Descrip,
                        CostPrice = i.CostPrice, RetailPrice = i.RetailPrice, StockQty = bal?.Qty ?? 0,
                        SuppId = i.SupId is > 0 ? i.SupId : null,
                    });
                }
                return Ok(rows);
            });

        // POST: api/ReturnList — { itemId, suppId, qty, reason?, remark?, source (1 mobile / 2 back office), userId? }
        [HttpPost]
        public Task<IActionResult> Add([FromBody] ReturnListAddRequest request) =>
            Run(async () =>
            {
                if (request == null || request.ItemId <= 0) return BadRequest(new { message = "Scan an item first." });
                if (request.SuppId <= 0) return BadRequest(new { message = "Select the supplier." });
                if (request.Qty <= 0) return BadRequest(new { message = "Enter a return qty more than 0." });
                return Ok(await _repository.AddAsync(request));
            });

        // PUT: api/ReturnList/{id} — qty / supplier / reason / remark of a row with no PRN yet
        [HttpPut("{id:int}")]
        public Task<IActionResult> Update(int id, [FromBody] ReturnListUpdateRequest request) =>
            Run(async () =>
            {
                await _repository.UpdateAsync(id, request);
                return Ok(new { message = "Saved." });
            });

        // POST: api/ReturnList/status — { ids, status: 2 Ready / 1 Added, userId }
        [HttpPost("status")]
        public Task<IActionResult> SetStatus([FromBody] ReturnListIdsRequest request) =>
            Run(async () =>
            {
                if (request?.Ids == null || request.Ids.Count == 0) return BadRequest(new { message = "Select the items first." });
                var changed = await _repository.SetStatusAsync(request.Ids, request.Status, request.UserId);
                return Ok(new { changed });
            });

        // POST: api/ReturnList/delete — { ids } (rows with a PRN are kept)
        [HttpPost("delete")]
        public Task<IActionResult> Delete([FromBody] ReturnListIdsRequest request) =>
            Run(async () =>
            {
                if (request?.Ids == null || request.Ids.Count == 0) return BadRequest(new { message = "Select the items first." });
                var deleted = await _repository.DeleteAsync(request.Ids);
                return Ok(new { deleted });
            });

        // POST: api/ReturnList/process — { ids, post = true, refNo?, remark?, userId?, print? } -> the PRN made
        [HttpPost("process")]
        public Task<IActionResult> Process([FromBody] ReturnListProcessRequest request) =>
            Run(async () =>
            {
                if (request?.Ids == null || request.Ids.Count == 0) return BadRequest(new { message = "Select the Ready items to process." });
                var prn = await _repository.ToPrnAsync(request);
                string? printError = null;
                if (request.Print)
                    printError = PrintSlip(await _repository.GetByIdsAsync(request.Ids, 3), prn.PrnNo);
                return Ok(new { prn.PrnNo, prn.Lines, prn.Qty, prn.Amount, prn.Posted, printed = request.Print && printError == null, printError });
            });

        // POST: api/ReturnList/print — { ids } -> the return slip on the receipt printer (open rows or PRN made)
        [HttpPost("print")]
        public Task<IActionResult> Print([FromBody] ReturnListIdsRequest request) =>
            Run(async () =>
            {
                if (request?.Ids == null || request.Ids.Count == 0) return BadRequest(new { message = "Select the items to print." });
                var rows = await _repository.GetByIdsAsync(request.Ids, null);
                if (rows.Count == 0) rows = await _repository.GetByIdsAsync(request.Ids, 3);
                var error = PrintSlip(rows, rows.Select(r => r.PrnNo).FirstOrDefault(p => p != null));
                return error == null ? Ok(new { message = "Printed." }) : BadRequest(new { message = error });
            });

        // the old return slip layout (PrinterService) with the new rows; null = printed
        private static string? PrintSlip(List<ReturnListRow> rows, string? prnNo)
        {
            if (rows.Count == 0) return "Nothing to print.";
            try
            {
                new PrinterService().PrintProcessedData(rows.Select(r => new ReturnItem
                {
                    Item_Code = string.IsNullOrEmpty(r.Barcode) ? (r.RefCode ?? r.ItemId.ToString()) : r.Barcode,
                    Descrip = (prnNo != null && r == rows[0] ? $"{prnNo} {r.SuppName}\n" : "") + r.Descrip,
                    Supp_Code = r.SuppCode ?? "",
                    Cost_Price = r.CostPrice ?? 0,
                    ERet_Price = r.SellPrice ?? 0,
                    Qty = (double)r.Qty,
                }).ToList());
                return null;
            }
            catch (Exception ex)
            {
                Log.Error($"Return slip not printed: {ex.Message}");
                return $"Not printed: {ex.Message}";
            }
        }

        // proc business errors (RAISERROR -> 50000) -> 400 { message }
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
                Log.Error($"ReturnList error: {ex.Message}");
                return new ObjectResult(new { message = "Internal Server Error", error = ex.Message }) { StatusCode = 500 };
            }
        }
    }
}
