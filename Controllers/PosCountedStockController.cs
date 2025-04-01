using ItemApi.Data;
using ItemApi.Interface;
using ItemApi.Models;
using Microsoft.AspNetCore.Mvc;

namespace ItemApi.Controllers
{
    [Route("api/[controller]")]
    [ApiController]
    public class PosCountedStockController : ControllerBase
    {

        private readonly PosCountedStockContext _context;
        private readonly IPosCountedStockRepository _repository;

        public PosCountedStockController(PosCountedStockContext context, IPosCountedStockRepository repository)
        {
            _context = context;
            _repository = repository;
        }

        [HttpGet("GetCountedPosStocks")]
        public async Task<IActionResult> GetCountedPosStocks(string itemCode)
        {
            try
            {
                var posStocks = await _repository.GetSumQtyAsync(itemCode);
                return Ok(posStocks);
            }
            catch (Exception ex)
            {
                return NotFound(ex.Message);
            }
        }

        
        [HttpPost]
        public async Task<IActionResult> PostPosCountedStock(PosCountedStock posCountedStock)
        {
            try
            {
                   
                await _repository.AddPosCountedStock(posCountedStock);
                return Ok(posCountedStock);
            }
            catch (Exception ex)
            {
                return NotFound(ex.Message);
            }
        }

        //implement delete method
        [HttpPost("DeleteByItemCode")]
        public async Task<IActionResult> DeletePosCountedStock(string itemCode)
        {
            try
            {
                await _repository.DeletePosCountedStock(itemCode);
                return Ok();
            }
            catch (Exception ex)
            {
                return NotFound(ex.Message);
            }
        }

        //implement delete all the table data in the database table
        [HttpPost("DeleteAll")]
        public async Task<IActionResult> DeleteAllPosCountedStock()
        {
            try
            {
                await _repository.DeleteAllPosCountedStock();
                return Ok();
            }
            catch (Exception ex)
            {
                return NotFound(ex.Message);
            }
        }

    }
}
