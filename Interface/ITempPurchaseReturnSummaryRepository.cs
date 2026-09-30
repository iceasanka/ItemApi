using ItemApi.Models;

namespace ItemApi.Interface
{
    public interface ITempPurchaseReturnSummaryRepository
    {
        Task<List<TempPurchaseReturnSummary>> GetAllAsync();
        Task<TempPurchaseReturnSummary?> GetByIdAsync(int idx);
        Task<TempPurchaseReturnSummary> InsertAsync(TempPurchaseReturnSummary summary);
        Task<TempPurchaseReturnSummary> UpdateAsync(TempPurchaseReturnSummary summary);
        Task<bool> DeleteAsync(int idx);
        Task<List<TempPurchaseReturnSummary>> SearchAsync(TempPurchaseReturnSummarySearchRequest request);
    }
}
