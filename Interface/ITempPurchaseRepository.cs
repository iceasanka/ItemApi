using ItemApi.Models;

namespace ItemApi.Interface
{
    public interface ITempPurchaseRepository
    {
        Task<TempPurchase> InsertAsync(TempPurchase tempPurchase);
        Task<TempPurchase> UpdateAsync(TempPurchase tempPurchase);
        Task<bool> DeleteAsync(int idx);
        Task<List<TempPurchase>> GetByGrnNoAsync(string grnNo);
    }
}
