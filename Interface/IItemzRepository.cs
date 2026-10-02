using ItemApi.Models;

namespace ItemApi.Interface
{
    public interface IItemzRepository
    {
        // Queries
        Task<ItemzWithDetails?> GetItemzWithDetailsByItemIdAsync(int itemId);
        Task<ItemzWithDetails?> GetItemzWithDetailsByBarcodeAsync(string barcode);
        Task<ItemzWithDetails?> GetItemzWithDetailsByRefCodeAsync(string refCode);
        Task<List<ItemzWithDetails>> SearchItemzAsync(string query);
        Task<List<ItemzWithDetails>> SearchByCodeItemzAsync(string query);
        Task<List<ItemzWithDetails>> SearchByDesItemzAsync(string query);




        // Itemz CRUD
        Task<Itemz> InsertItemzAsync(Itemz item);
        Task<Itemz> UpdateItemzAsync(Itemz item);
        Task DeleteItemzAsync(int itemId);

        // ItemzDet CRUD
        Task<ItemzDet> InsertItemzDetAsync(ItemzDet det);
        Task<ItemzDet> UpdateItemzDetAsync(ItemzDet det);

        // Price links (extra retail prices the cashier picks from)
        Task<List<ItemzPriceLink>> GetPriceLinksAsync(int itemId);
        Task<ItemzPriceLink> AddPriceLinkAsync(AddPriceLinkRequest request);
        Task DeletePriceLinkAsync(int priceLinkId, int? userId);
    }
}
