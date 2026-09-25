using ItemApi.Data;
using ItemApi.Interface;
using ItemApi.Models;
using Microsoft.Extensions.Options;

namespace ItemApi.Repositories
{
    public class ItemzRepository : IItemzRepository
    {
        private readonly AppDbContext _context;
        // Hard-coded in appsettings.json (AppSettings:LocationId) until the user table is implemented
        private readonly int _locationId;

        public ItemzRepository(AppDbContext context, IOptions<AppSettings> appSettings)
        {
            _context = context;
            _locationId = appSettings.Value.LocationId;
        }

        public async Task<ItemzWithDetails?> GetItemzWithDetailsByItemIdAsync(int itemId)
        {
            return await _context.GetItemzWithDetailsByItemIdAsync(itemId, _locationId);
        }

        public async Task<ItemzWithDetails?> GetItemzWithDetailsByBarcodeAsync(string barcode)
        {
            return await _context.GetItemzWithDetailsByBarcodeAsync(barcode, _locationId);
        }

        public async Task<ItemzWithDetails?> GetItemzWithDetailsByRefCodeAsync(string refCode)
        {
            return await _context.GetItemzWithDetailsByRefCodeAsync(refCode, _locationId);
        }

        public async Task<List<ItemzWithDetails>> SearchItemzAsync(string query)
        {
            return await _context.SearchItemzAsync(query, _locationId);
        }
        
        public async Task<List<ItemzWithDetails>> SearchByCodeItemzAsync(string query)
        {
            return await _context.SearchByCodeItemzAsync(query, _locationId);
        }
        public async Task<List<ItemzWithDetails>> SearchByDesItemzAsync(string query)
        {
            return await _context.SearchByDesItemzAsync(query, _locationId);
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
            det.LocationId = _locationId;
            return await _context.InsertItemzDetAsync(det);
        }

        public async Task<ItemzDet> UpdateItemzDetAsync(ItemzDet det)
        {
            det.LocationId = _locationId;
            return await _context.UpdateItemzDetAsync(det);
        }
    }
}
