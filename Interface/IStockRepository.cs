
using ItemApi.Models;

namespace ItemApi.Repositories
{
    public interface IStockRepository
    {
        Task<StockCountResult> GetStockByItemcodeAsync(string itemcode);

          Task<int> GetOpbByLocaCodeAsync(string locaCode);

          Task<List<SpHasExistsSrlNewResult>> CheckStockAsync(string locaCode, string itemCode, string serialCode, decimal qty, int type, string fromLoca, string toLoca, string id, string serialNo);

         Task UpdateStockAsync(UpdateStockParams updateStockParams);

          Task CommitStockAdjustmentAsync(CommitStockAdjustmentParams commitStockAdjustmentParams);
    }
}
