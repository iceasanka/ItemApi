using ItemApi.Interface;
using ItemApi.Models;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace ItemApi.Controllers
{
    // Stock take (ST00000001): Create makes the count sheets "as at" now → people enter counts per sheet →
    // Variance shows counted vs system → Post makes ONE stock adjustment (ADJ…) for the differences.
    // Like count-mode adjustments, post after the tills have uploaded their sales (the UI checks
    // GET api/Sync/Terminals). See Docs/StockSystem.md §6.18.
    [Route("api/[controller]")]
    [ApiController]
    public class StockTakeController : ControllerBase
    {
        private readonly IStockTakeRepository _repository;

        public StockTakeController(IStockTakeRepository repository)
        {
            _repository = repository;
        }

        // POST: api/StockTake/Create
        [HttpPost("Create")]
        public Task<IActionResult> Create([FromBody] StockTakeCreateRequest request) =>
            Run(async () =>
            {
                var result = await _repository.CreateAsync(request ?? new StockTakeCreateRequest());
                return Ok(new { message = $"Stock take {result.StockTakeNo} started: {result.ItemCount} items on {result.SheetCount} sheets.", data = result });
            });

        // POST: api/StockTake/Search
        [HttpPost("Search")]
        public Task<IActionResult> Search([FromBody] StockTakeSearchRequest request) =>
            Run(async () => Ok(await _repository.SearchAsync(request ?? new StockTakeSearchRequest())));

        // GET: api/StockTake/5 — header + sheets with progress
        [HttpGet("{id:int}")]
        public Task<IActionResult> Get(int id) =>
            Run(async () =>
            {
                var result = await _repository.GetAsync(id);
                return result == null ? NotFound(new { message = $"Stock take {id} not found." }) : Ok(result);
            });

        // GET: api/StockTake/5/Sheet/12?showSystemQty=false — a count sheet (blind count unless showSystemQty)
        [HttpGet("{id:int}/Sheet/{sheetId:int}")]
        public Task<IActionResult> GetSheet(int id, int sheetId, [FromQuery] bool showSystemQty = false) =>
            Run(async () =>
            {
                var result = await _repository.GetSheetAsync(id, sheetId, showSystemQty);
                return result == null ? NotFound(new { message = "Sheet not found." }) : Ok(result);
            });

        // POST: api/StockTake/5/Sheet — an extra empty sheet ("Store room")
        [HttpPost("{id:int}/Sheet")]
        public Task<IActionResult> AddSheet(int id, [FromBody] StockTakeAddSheetRequest request) =>
            Run(async () =>
            {
                if (string.IsNullOrWhiteSpace(request?.SheetName))
                    return BadRequest(new { message = "Give the sheet a name." });
                return Ok(await _repository.AddSheetAsync(id, request));
            });

        // POST: api/StockTake/5/Sheet/12/AddItem — { itemId } or { code } (barcode / item code)
        [HttpPost("{id:int}/Sheet/{sheetId:int}/AddItem")]
        public Task<IActionResult> AddItem(int id, int sheetId, [FromBody] StockTakeAddItemRequest request) =>
            Run(async () =>
            {
                if (request == null || ((request.ItemId ?? 0) == 0 && string.IsNullOrWhiteSpace(request.Code)))
                    return BadRequest(new { message = "Scan or pick an item." });
                return Ok(await _repository.AddItemAsync(id, sheetId, request));
            });

        // POST: api/StockTake/5/Sheet/12/Counts — only the items sent change; countedQty null clears a count
        [HttpPost("{id:int}/Sheet/{sheetId:int}/Counts")]
        public Task<IActionResult> SaveCounts(int id, int sheetId, [FromBody] StockTakeCountsRequest request) =>
            Run(async () =>
            {
                if (request == null)
                    return BadRequest(new { message = "Nothing to save." });
                if (request.Counts.GroupBy(c => c.ItemId).Any(g => g.Count() > 1))
                    return BadRequest(new { message = "An item is sent twice." });
                await _repository.SaveCountsAsync(id, sheetId, request);
                return Ok(new { message = "Counts saved." });
            });

        // GET: api/StockTake/5/Variance?onlyDiff=true
        [HttpGet("{id:int}/Variance")]
        public Task<IActionResult> Variance(int id, [FromQuery] bool onlyDiff = false) =>
            Run(async () =>
            {
                var result = await _repository.GetVarianceAsync(id, onlyDiff);
                return result == null ? NotFound(new { message = $"Stock take {id} not found." }) : Ok(result);
            });

        // POST: api/StockTake/5/Post — { uncountedAsZero, reasonId, userId }
        [HttpPost("{id:int}/Post")]
        public Task<IActionResult> Post(int id, [FromBody] StockTakePostRequest request) =>
            Run(async () =>
            {
                var result = await _repository.PostAsync(id, request ?? new StockTakePostRequest());
                var message = result.AdjNo == null
                    ? "Stock take posted. Every count matched the system — no adjustment needed."
                    : $"Stock take posted: adjustment {result.AdjNo} for {result.AdjustedItems} items.";
                return Ok(new { message, data = result });
            });

        // POST: api/StockTake/5/Cancel — only while counting; nothing is posted
        [HttpPost("{id:int}/Cancel")]
        public Task<IActionResult> Cancel(int id, [FromBody] StockTakeCancelRequest? request) =>
            Run(async () =>
            {
                await _repository.CancelAsync(id, request?.UserId);
                return Ok(new { message = "Stock take cancelled." });
            });

        // proc business errors (RAISERROR → 50000) and "not found" → 400 / 404 { message }
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
            catch (KeyNotFoundException ex)
            {
                return NotFound(new { message = ex.Message });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = "Internal Server Error", error = ex.Message });
            }
        }
    }
}
