using ItemApi.Data;
using ItemApi.Interface;
using ItemApi.Models;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using Serilog;

namespace ItemApi.Repositories
{
    public class TempPurchaseRepository : ITempPurchaseRepository
    {
        private readonly AppDbContext _context;
        // Hard-coded in appsettings.json (AppSettings:LocationId) until the user table is implemented
        private readonly int _locationId;

        public TempPurchaseRepository(AppDbContext context, IOptions<AppSettings> appSettings)
        {
            _context = context;
            _locationId = appSettings.Value.LocationId;
        }

        public async Task<TempPurchase> InsertAsync(TempPurchase tempPurchase)
        {
            try
            {
                tempPurchase.LocationId = _locationId;
                tempPurchase.UDate = DateTime.Now;
                await _context.TempPurchases.AddAsync(tempPurchase);
                await _context.SaveChangesAsync();
                return tempPurchase;
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex.Message}");
                throw;
            }
        }

        public async Task<TempPurchase> UpdateAsync(TempPurchase tempPurchase)
        {
            try
            {
                var existing = await _context.TempPurchases.FindAsync(tempPurchase.Idx);
                if (existing == null)
                    throw new Exception($"Record with Idx {tempPurchase.Idx} not found.");

                existing.GrnNo      = tempPurchase.GrnNo;
                existing.LocationId = _locationId;
                existing.ItemId     = tempPurchase.ItemId;
                existing.PDate      = tempPurchase.PDate;
                existing.Cost       = tempPurchase.Cost;
                existing.Rate       = tempPurchase.Rate;
                existing.Qty        = tempPurchase.Qty;
                existing.Discount   = tempPurchase.Discount;
                existing.GAmount    = tempPurchase.GAmount;
                existing.ExpDate    = tempPurchase.ExpDate;
                existing.Status     = tempPurchase.Status;
                existing.UserId     = tempPurchase.UserId;
                existing.UDate      = DateTime.Now;

                _context.TempPurchases.Update(existing);
                await _context.SaveChangesAsync();
                return existing;
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex.Message}");
                throw;
            }
        }

        public async Task<bool> DeleteAsync(int idx)
        {
            try
            {
                var existing = await _context.TempPurchases.FindAsync(idx);
                if (existing == null) return false;

                _context.TempPurchases.Remove(existing);
                await _context.SaveChangesAsync();
                return true;
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex.Message}");
                throw;
            }
        }

        public async Task<List<TempPurchase>> GetByGrnNoAsync(string grnNo)
        {
            try
            {
                return await _context.TempPurchases
                    .Where(x => x.LocationId == _locationId)
                    .Where(x => EF.Functions.Like(x.GrnNo, $"%{grnNo}%"))
                    .OrderByDescending(x => x.PDate)
                    .ToListAsync();
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex.Message}");
                throw;
            }
        }
    }
}
