using System.Threading.Tasks;
using ItemApi.Repositories;

namespace ItemApi.Service
{

    public class StockService
    {
        private readonly IStockRepository _stockRepository;

        public StockService(IStockRepository stockRepository)
        {
            _stockRepository = stockRepository;
        }

        public async Task<bool> UpdateStockIfExistsAsync(string locaCode, string itemCode, string serialCode, decimal qty, int type, string fromLoca, string toLoca, string id, string serialNo)
        {
            var results = await _stockRepository.CheckStockAsync(locaCode, itemCode, serialCode, qty, type, fromLoca, toLoca, id, serialNo);

            return results.Count > 0;
        }

        public async Task<int> GetOpbByLocaCode(string locaCode)
        {
            var opb = await _stockRepository.GetOpbByLocaCodeAsync(locaCode);

            return opb;
        }

    }

}
