using Microsoft.AspNetCore.Mvc;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using ItemApi.Data;
using ItemApi.Models;
using ItemApi.Repositories;

namespace ItemApi.Controllers
{
    [Route("api/[controller]")]
    [ApiController]
    public class ItemsController : ControllerBase
    {
        private readonly ItemContext _context;
        private readonly IItemRepository _itemRepository;

        public ItemsController(ItemContext context, IItemRepository itemRepository)
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
                return Ok(item);
            }
            catch (Exception ex)
            {
                return NotFound(ex.Message);
            }

        }

        [HttpGet("GetItemWithDetailsByRefCode")]
        public async Task<ActionResult<ItemWithDetails>> GetItemWithDetailsByBarcodeAsync(string barcode)
        {
            try
            {
                var item = await _itemRepository.GetItemWithDetailsByBarcodeAsync(barcode);
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
                .Where(i => i.Descrip.Contains(query))
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

    }
}
