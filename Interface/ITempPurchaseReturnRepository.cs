using ItemApi.Models;

namespace ItemApi.Interface
{
    public interface ITempPurchaseReturnRepository
    {
        Task<TempPurchaseReturn> InsertAsync(TempPurchaseReturn item);
        Task<TempPurchaseReturn> UpdateAsync(TempPurchaseReturn item);
        Task<bool> DeleteAsync(int idx);
        Task<List<TempPurchaseReturn>> GetByPrnNoAsync(string prnNo);
    }
}
