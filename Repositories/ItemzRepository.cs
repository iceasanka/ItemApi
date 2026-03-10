using ItemApi.Data;
using ItemApi.Interface;
using ItemApi.Models;

namespace ItemApi.Repositories
{
    public class ItemzRepository : IItemzRepository
    {
        private readonly ItemzContext _context;

        public ItemzRepository(ItemzContext context)
        {
            _context = context;
        }

        public async Task<ItemzWithDetails?> GetItemzWithDetailsByItemIdAsync(int itemId)
        {
            return await _context.GetItemzWithDetailsByItemIdAsync(itemId);
        }

        public async Task<ItemzWithDetails?> GetItemzWithDetailsByBarcodeAsync(string barcode)
        {
            return await _context.GetItemzWithDetailsByBarcodeAsync(barcode);
        }

        public async Task<ItemzWithDetails?> GetItemzWithDetailsByRefCodeAsync(string refCode)
        {
            return await _context.GetItemzWithDetailsByRefCodeAsync(refCode);
        }

        public async Task<List<ItemzWithDetails>> SearchItemzAsync(string query)
        {
            return await _context.SearchItemzAsync(query);
        }

        public async Task<Itemz> InsertItemzAsync(Itemz item)
        {
            return await _context.InsertItemzAsync(item);
        }

        public async Task<Itemz> UpdateItemzAsync(Itemz item)
        {
            return await _context.UpdateItemzAsync(item);
        }

        public async Task DeleteItemzAsync(int itemId)
        {
            await _context.DeleteItemzAsync(itemId);
        }

        public async Task<ItemzDet> InsertItemzDetAsync(ItemzDet det)
        {
            return await _context.InsertItemzDetAsync(det);
        }

        public async Task<ItemzDet> UpdateItemzDetAsync(ItemzDet det)
        {
            return await _context.UpdateItemzDetAsync(det);
        }
    }
}
