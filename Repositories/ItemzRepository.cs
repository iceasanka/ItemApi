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

      

        // UDate is set here (not by the UI): cashier tills download items "changed since" UDate
        // (z_sp_GetItemsForSync), so every insert/update must move it.
        public async Task<Itemz> InsertItemzAsync(Itemz item)
        {
            item.UDate = DateTime.Now;
            if (item.CDate == default) item.CDate = item.UDate;
            return await _context.InsertItemzAsync(item);
        }

        public async Task<Itemz> UpdateItemzAsync(Itemz item)
        {
            item.UDate = DateTime.Now;
            if (item.CDate == default) item.CDate = item.UDate;
            return await _context.UpdateItemzAsync(item);
        }

        public async Task DeleteItemzAsync(int itemId)
        {
            await _context.DeleteItemzAsync(itemId);
        }

        public async Task<ItemzDet> InsertItemzDetAsync(ItemzDet det)
        {
            det.LocationId = _locationId;
            det.UDate = DateTime.Now;   // price change → tills pick it up on the next item sync
            if (det.CDate == default) det.CDate = det.UDate;
            return await _context.InsertItemzDetAsync(det);
        }

        public async Task<ItemzDet> UpdateItemzDetAsync(ItemzDet det)
        {
            det.LocationId = _locationId;
            det.UDate = DateTime.Now;   // price change → tills pick it up on the next item sync
            if (det.CDate == default) det.CDate = det.UDate;
            return await _context.UpdateItemzDetAsync(det);
        }

        public async Task<List<ItemzPriceLink>> GetPriceLinksAsync(int itemId)
        {
            return await _context.GetPriceLinksAsync(itemId, _locationId);
        }

        public async Task<ItemzPriceLink> AddPriceLinkAsync(AddPriceLinkRequest request)
        {
            return await _context.AddPriceLinkAsync(request, _locationId);
        }

        public async Task DeletePriceLinkAsync(int priceLinkId, int? userId)
        {
            await _context.DeletePriceLinkAsync(priceLinkId, userId);
        }

        // Quantity prices (QtyLevel2..4 / PriceLevel2..4): "buy at least MinQty → pay Price each".
        // The till picks the level with the highest MinQty the line reaches (zf_sp_SaveInvoice), so the
        // levels must be complete pairs, go up in quantity and down in price, and stay below RetailPrice.
        // Returns an error message, or null when the levels are fine.
        public static string? ValidatePriceLevels(ItemzDet det)
        {
            var levels = new[]
            {
                (Level: 2, MinQty: det.QtyLevel2, Price: det.PriceLevel2),
                (Level: 3, MinQty: det.QtyLevel3, Price: det.PriceLevel3),
                (Level: 4, MinQty: det.QtyLevel4, Price: det.PriceLevel4)
            };

            decimal lastQty = 1;
            decimal? lastPrice = det.RetailPrice;
            var lastPriceName = "the retail price";
            foreach (var l in levels)
            {
                if (l.MinQty == null && l.Price == null)
                    continue;
                if (l.MinQty == null || l.Price == null)
                    return $"Price level {l.Level}: enter both Min Qty and Price, or leave both empty.";
                if (l.MinQty <= lastQty)
                    return $"Price level {l.Level}: Min Qty must be more than {lastQty:0.###}.";
                if (l.Price <= 0)
                    return $"Price level {l.Level}: Price must be more than 0.";
                if (lastPrice != null && l.Price >= lastPrice)
                    return $"Price level {l.Level}: Price must be less than {lastPriceName} ({lastPrice:0.00}).";

                lastQty = l.MinQty.Value;
                lastPrice = l.Price;
                lastPriceName = $"level {l.Level}'s price";
            }
            return null;
        }
    }
}
