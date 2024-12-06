
using ItemApi.Models;

namespace ItemApi.Repositories
{
    public interface IItemRepository
    {
        Task<ItemWithDetails> GetItemWithDetailsByItemCodeAsync(string itemcode);

        Task<ItemWithDetails> GetItemWithDetailsByBarcodeAsync(string barcode);

        Task<List<PriceLink>> GetPriceLink(string itemCode);
    }
}
