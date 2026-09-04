using ItemApi.Data;
using ItemApi.Models;
using Microsoft.EntityFrameworkCore;
using System.Threading.Tasks;
namespace ItemApi.Repositories
{

    public class StockRepository : IStockRepository
    {
        private readonly AppDbContext _context;

        public StockRepository(AppDbContext context)
        {
            _context = context;
        }


        public async Task<StockCountResult> GetStockByItemcodeAsync(string itemcode)
        {
            return await _context.GetStockByItemcodeAsync(itemcode);
        }

         public async Task<int> GetOpbByLocaCodeAsync(string locaCode)
        {
            return await _context.GetOpbByLocaCodeAsync(locaCode);
        }

        public async Task<List<SpHasExistsSrlNewResult>> CheckStockAsync(string locaCode, string itemCode, string serialCode, decimal qty, int type, string fromLoca, string toLoca, string id, string serialNo)
        {
            return await _context.ExecuteSpHasExistsSrlNewAsync(locaCode, itemCode, serialCode, qty, type, fromLoca, toLoca, id, serialNo);
        }

        public async Task UpdateStockAsync(UpdateStockParams updateStockParams)
        {
            await _context.UpdateStockAsync( updateStockParams);
        }

         public async Task CommitStockAdjustmentAsync(CommitStockAdjustmentParams commitStockAdjustmentParams)

        {
            await _context.CommitStockAdjustmentAsync( commitStockAdjustmentParams);
        }
    }
}
