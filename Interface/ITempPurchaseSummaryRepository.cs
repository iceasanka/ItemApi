using ItemApi.Models;

namespace ItemApi.Interface
{
    public interface ITempPurchaseSummaryRepository
    {
        Task<List<TempPurchaseSummary>> GetAllAsync();
        Task<TempPurchaseSummary?> GetByIdAsync(int idx);
        Task<TempPurchaseSummary> InsertAsync(TempPurchaseSummary summary);
        Task<TempPurchaseSummary> UpdateAsync(TempPurchaseSummary summary);
        Task<bool> DeleteAsync(int idx);
        Task<List<TempPurchaseSummary>> SearchAsync(TempPurchaseSummarySearchRequest request);
    }
}
