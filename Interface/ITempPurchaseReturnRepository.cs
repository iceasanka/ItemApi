using ItemApi.Models;

namespace ItemApi.Interface
{
    public interface ITempPurchaseReturnRepository
    {
        Task<TempPurchase> InsertAsync(TempPurchase tempPurchase);
        Task<TempPurchase> UpdateAsync(TempPurchase tempPurchase);
        Task<bool> DeleteAsync(int idx);
        Task<List<TempPurchase>> GetByPrnNoAsync(string prnNo);
    }
}
