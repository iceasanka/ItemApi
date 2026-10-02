using ItemApi.Interface;
using ItemApi.Models;
using ItemApi.Repositories;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;
using Serilog;

namespace ItemApi.Controllers
{
    [Route("api/[controller]")]
    [ApiController]
    public class ItemzController : ControllerBase
    {
        private readonly IItemzRepository _repository;

        public ItemzController(IItemzRepository repository)
        {
            _repository = repository;
        }

        // ─── GET ──────────────────────────────────────────────────────────────────

        [HttpGet("GetByItemId/{itemId}")]
        public async Task<ActionResult<ItemzWithDetails>> GetByItemId(int itemId)
        {
            try
            {
                var item = await _repository.GetItemzWithDetailsByItemIdAsync(itemId);
                if (item == null)
                    return NotFound($"Item not found for ItemId: {itemId}");

                return Ok(item);
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex}");
                return NotFound(ex.Message);
            }
        }

        [HttpGet("GetByBarcode")]
        public async Task<ActionResult<ItemzWithDetails>> GetByBarcode([FromQuery] string barcode)
        {
            try
            {
                var item = await _repository.GetItemzWithDetailsByBarcodeAsync(barcode);
                if (item == null)
                    return NotFound($"Item not found for Barcode: {barcode}");

                return Ok(item);
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex}");
                return NotFound(ex.Message);
            }
        }

        [HttpGet("GetByRefCode")]
        public async Task<ActionResult<ItemzWithDetails>> GetByRefCode([FromQuery] string refCode)
        {
            try
            {
                var item = await _repository.GetItemzWithDetailsByRefCodeAsync(refCode);
                if (item == null)
                    return NotFound($"Item not found for RefCode: {refCode}");

                return Ok(item);
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex}");
                return NotFound(ex.Message);
            }
        }

        [HttpGet("Search")]
        public async Task<ActionResult<List<ItemzWithDetails>>> Search([FromQuery] string query)
        {
            if (string.IsNullOrWhiteSpace(query))
                return BadRequest("Query parameter is required.");

            try
            {
                var items = await _repository.SearchItemzAsync(query);
                return Ok(items);
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex}");
                return NotFound(ex.Message);
            }
        }

        [HttpGet("SearchByCode")]
        public async Task<ActionResult<List<ItemzWithDetails>>> SearchByCode([FromQuery] string query)
        {
            if (string.IsNullOrWhiteSpace(query))
                return BadRequest("Query parameter is required.");

            try
            {
                var items = await _repository.SearchByCodeItemzAsync(query);
                return Ok(items);
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex}");
                return NotFound(ex.Message);
            }
        }

        [HttpGet("SearchByDes")]
        public async Task<ActionResult<List<ItemzWithDetails>>> SearchByDes([FromQuery] string query)
        {
            if (string.IsNullOrWhiteSpace(query))
                return BadRequest("Query parameter is required.");

            try
            {
                var items = await _repository.SearchByDesItemzAsync(query);
                return Ok(items);
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex}");
                return NotFound(ex.Message);
            }
        }

        // ─── POST ─────────────────────────────────────────────────────────────────

        [HttpPost("AddItem")]
        public async Task<ActionResult<Itemz>> AddItem([FromBody] Itemz item)
        {
            try
            {
                var result = await _repository.InsertItemzAsync(item);
                return CreatedAtAction(nameof(GetByItemId), new { itemId = result.ItemId }, result);
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex}");
                return StatusCode(500, ex.Message);
            }
        }

        [HttpPost("AddItemDet")]
        public async Task<ActionResult<ItemzDet>> AddItemDet([FromBody] ItemzDet det)
        {
            var levelError = ItemzRepository.ValidatePriceLevels(det);
            if (levelError != null)
                return BadRequest(new { message = levelError });

            try
            {
                var result = await _repository.InsertItemzDetAsync(det);
                return Ok(result);
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex}");
                return StatusCode(500, ex.Message);
            }
        }

        // ─── PUT ──────────────────────────────────────────────────────────────────

        [HttpPut("UpdateItem")]
        public async Task<ActionResult<Itemz>> UpdateItem([FromBody] Itemz item)
        {
            try
            {
                var result = await _repository.UpdateItemzAsync(item);
                return Ok(result);
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex}");
                return StatusCode(500, ex.Message);
            }
        }

        [HttpPut("UpdateItemDet")]
        public async Task<ActionResult<ItemzDet>> UpdateItemDet([FromBody] ItemzDet det)
        {
            var levelError = ItemzRepository.ValidatePriceLevels(det);
            if (levelError != null)
                return BadRequest(new { message = levelError });

            try
            {
                var result = await _repository.UpdateItemzDetAsync(det);
                return Ok(result);
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex}");
                return StatusCode(500, ex.Message);
            }
        }

        // ─── DELETE ───────────────────────────────────────────────────────────────

        [HttpDelete("DeleteItem/{itemId}")]
        public async Task<ActionResult> DeleteItem(int itemId)
        {
            try
            {
                await _repository.DeleteItemzAsync(itemId);
                return NoContent();
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex}");
                return StatusCode(500, ex.Message);
            }
        }

        // ─── Price links ──────────────────────────────────────────────────────────
        // Extra retail prices for the same item (e.g. old stock at the old MRP). Tills download them
        // (api/Sync/PriceLinks) and the cashier picks the right price when the item is scanned.

        // GET: api/Itemz/PriceLinks/5 — active links, lowest price first
        [HttpGet("PriceLinks/{itemId}")]
        public async Task<ActionResult<List<ItemzPriceLink>>> GetPriceLinks(int itemId)
        {
            try
            {
                return Ok(await _repository.GetPriceLinksAsync(itemId));
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex}");
                return StatusCode(500, new { message = "Internal Server Error", error = ex.Message });
            }
        }

        // POST: api/Itemz/AddPriceLink { itemId, retailPrice, wholesalePrice?, costPrice?, remark?, userId? }
        [HttpPost("AddPriceLink")]
        public async Task<IActionResult> AddPriceLink([FromBody] AddPriceLinkRequest request)
        {
            if (request == null || request.ItemId <= 0)
                return BadRequest(new { message = "ItemId is required." });

            try
            {
                var result = await _repository.AddPriceLinkAsync(request);
                return Ok(new { message = "Price link added.", data = result });
            }
            catch (SqlException ex) when (ex.Number >= 50000)
            {
                return BadRequest(new { message = ex.Message });
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex}");
                return StatusCode(500, new { message = "Internal Server Error", error = ex.Message });
            }
        }

        // DELETE: api/Itemz/PriceLink/12?userId=3 — marks it deleted (Status 0); tills drop it on their next download
        [HttpDelete("PriceLink/{priceLinkId}")]
        public async Task<IActionResult> DeletePriceLink(int priceLinkId, [FromQuery] int? userId)
        {
            try
            {
                await _repository.DeletePriceLinkAsync(priceLinkId, userId);
                return Ok(new { message = "Price link deleted." });
            }
            catch (SqlException ex) when (ex.Number >= 50000)
            {
                return BadRequest(new { message = ex.Message });
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex}");
                return StatusCode(500, new { message = "Internal Server Error", error = ex.Message });
            }
        }
    }
}
