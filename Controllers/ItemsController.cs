using ItemApi.Data;
using ItemApi.Models;
using ItemApi.Repositories;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace ItemApi.Controllers
{
    [Route("api/[controller]")]
    [ApiController]
    public class ItemsController : ControllerBase
    {
        private readonly AppDbContext _context;
        private readonly IItemRepository _itemRepository;

        public ItemsController(AppDbContext context, IItemRepository itemRepository)
        {
            _context = context;
            _itemRepository = itemRepository;
        }


        [HttpGet("GetItemWithDetailsByBarcode")]
        public async Task<ActionResult<ItemWithDetails>> GetItemWithDetailsByBarcodeAsync(string barcode)
        {
            try
            {
                var item = await _itemRepository.GetItemWithDetailsByBarcodeAsync(barcode);

                if (item == null)
                    return NotFound("Item not found for the given barcode.");

                return Ok(item);
            }
            catch (Exception ex)
            {
                return NotFound(ex.Message);
            }

        }

        [HttpGet("GetItemWithDetailsByRefCode")]
        public async Task<ActionResult<ItemWithDetails>> GetItemWithDetailsByRefCodeAsync(string barcode)
        {
            try
            {
                var item = await _itemRepository.GetItemWithDetailsByRefCodeAsync(barcode);
                return Ok(item);
            }
            catch (Exception ex)
            {
                return NotFound(ex.Message);
            }

        }

        [HttpGet("search")]
        public async Task<IActionResult> SearchItems([FromQuery] string query)
        {
            if (string.IsNullOrEmpty(query))
            {
                return BadRequest("Query parameter is required");
            }

            try
            {

                var items = await _context.Items
                .Where(i => i.Descrip.Contains(query) || i.Ref_Code.Contains(query))
                .Select(i => new { i.Item_Code, i.Descrip })
                .Take(50) // limit to 10 results
                .ToListAsync();

                return Ok(items);
            }
            catch (Exception ex)
            {
                return NotFound(ex.Message);
            }
        }

        [HttpGet("GetPriceLink")]
        public async Task<ActionResult<List<PriceLink>>> GetPriceLink(string itemCode)
        {
            try
            {
                var item = await _itemRepository.GetPriceLink(itemCode);

                return Ok(item);
            }
            catch (Exception ex)
            {
                return NotFound(ex.Message);
            }

        }


        [HttpPost("AddPriceLink")]
        public async Task<IActionResult> AddPriceLink([FromBody] PriceLinkUpdateDTO dto)
        {
            if (dto == null || string.IsNullOrEmpty(dto.ItemCode))
            {
                return BadRequest("Invalid request data.");
            }

            try
            {
                int rowsAffected = await _itemRepository.UpdatePriceLink(dto);

                if (rowsAffected > 0)
                    return Ok(new { message = "Price Link updated successfully." });

                return NotFound(new { message = "No record updated." });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = "Internal Server Error", error = ex.Message });
            }
        }

        [HttpDelete("{itemCode}")]
        public IActionResult DeletePriceLink(string itemCode)
        {
            return Ok(new { message = "OK" });
        }

        [HttpPost("UpdateItemRetPrice")]
        public async Task<IActionResult> UpdateItemRetPrice([FromBody] ItemPrice itemPrice)
        {
            if (itemPrice == null || string.IsNullOrEmpty(itemPrice.ItemCode))
                return BadRequest("Invalid request data.");

            // Example repository call
            int rowsAffected = await _itemRepository.UpdateItemRetPrice(itemPrice.ItemCode, itemPrice.ERetPrice);

            if (rowsAffected > 0)
                return Ok(new { message = "Price updated successfully." });

            return NotFound(new { message = "No record updated." });
        }

        


    }
}
