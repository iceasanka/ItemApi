
using ItemApi.Models;

namespace ItemApi.Repositories
{
    public interface IReturnRepository
    {
        Task<List<ReturnItem>> GetAllItemsAsync();
        Task<ReturnItem> GetItemByCodeAsync(string itemCode);
        Task<List<ReturnItem>> GetItemsBySuppCodeAsync(string suppCode);
        Task<List<ReturnItem>> SearchItemsAsync(string description, string suppCode);
        Task AddItemAsync(ReturnItem item);
        Task UpdateItemAsync(int id, ReturnItem updatedItem);
        Task UpdateItemStatusAsync(int id, int status);
        Task DeleteItemAsync(int id);
        Task<List<IGrouping<string, ReturnItem>>> GroupBySuppCodeAsync();

        Task<int> GetPRNOByLocaCodeAsync(string locaCode);

        Task<List<ReturnMode>> GetReturnModesAsync();
        Task<List<PurchaseType>> GetPurchaseTypesAsync();

        Task<Supplier> GetSupplierByCodeAsync(string suppCode);

        Task UpdateReturnItemToTempPurchaseAsync(ReturnUpdateRequest request);

        Task CommitReturnToPurchaseAsync(CommitReturnItems request);

        Task DeleteTempPurchaseAsync(DeleteTempPurchaseRequest request);
    }
}
