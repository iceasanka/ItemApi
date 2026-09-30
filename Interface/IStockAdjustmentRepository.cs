using ItemApi.Models;

namespace ItemApi.Interface
{
    public interface IStockAdjustmentRepository
    {
        Task<StockAdjustment> SaveAsync(StockAdjustmentRequest request);
        Task<StockAdjustment?> GetByAdjNoAsync(string adjNo);
        Task<List<StockAdjustment>> SearchAsync(StockAdjustmentSearchRequest request);
        Task<List<StockAdjReason>> GetReasonsAsync();
    }
}
