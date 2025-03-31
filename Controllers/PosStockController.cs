using ItemApi.Data;
using ItemApi.Interface;
using ItemApi.Repositories;
using Microsoft.AspNetCore.Mvc;

namespace ItemApi.Controllers
{
    [Route("api/[controller]")]
    [ApiController]
    public class PosStockController : ControllerBase
    {
        private readonly PosStockContext _context;
        private readonly IPosStockRepository _repository;

        public PosStockController(PosStockContext context, IPosStockRepository repository)
        {
            _context = context;
            _repository = repository;
        }

        [HttpGet("GetPosStock")]
        public async Task<IActionResult> GetPosStocks(string itemCode)
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
    }
}
