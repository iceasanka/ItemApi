using ItemApi.Models;

namespace ItemApi.Interface
{
    public interface IPurchaseRepository
    {
        
        Task<int> GetPNOByLocaCodeAsync(string locaCode);
        Task UpdatePurchaseItemToTempPurchaseAsync(PurchaseUpdateRequest request);
        Task CommitPurchaseAsync(CommitPurchaseItems request);
        //Task DeleteTempPurchaseAsync(DeleteTempPurchaseRequest request);

    }
}
