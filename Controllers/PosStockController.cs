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
        private readonly IPosStockRepository _repository;

        private readonly IPosCountedStockRepository _posCountedRepository;

        public PosStockController(IPosStockRepository repository, IPosCountedStockRepository posCountedRepository)
        {
            _repository = repository;
            _posCountedRepository = posCountedRepository;
        }

        [HttpGet("GetPosStock")]
        public async Task<IActionResult> GetPosStocks(string itemCode)
        {
            try
            {
                double toBeUpdateStock = 0;

                double countedStocks = await _posCountedRepository.GetSumQtyAsync(itemCode);

                decimal posStocks = await _repository.GetSumQtyAsync(itemCode);

                toBeUpdateStock = (double)posStocks - countedStocks;

                return Ok(toBeUpdateStock);
            }
            catch (Exception ex)
            {
                return NotFound(ex.Message);
            }
        }
    }
}
