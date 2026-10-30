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

        // a GRN draft (not committed) with its lines; a GRN scan made into it is open again → 0 deleted, 1 not found,
        // 2 committed (refused)
        Task<int> DeleteDraftAsync(string grnNo);
        Task<List<TempPurchaseSummary>> SearchAsync(TempPurchaseSummarySearchRequest request);
    }
}
