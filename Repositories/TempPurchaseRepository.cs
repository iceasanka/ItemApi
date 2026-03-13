using ItemApi.Data;
using ItemApi.Interface;
using ItemApi.Models;
using Microsoft.EntityFrameworkCore;
using Serilog;

namespace ItemApi.Repositories
{
    public class TempPurchaseRepository : ITempPurchaseRepository
    {
        private readonly TempPurchaseContext _context;

        public TempPurchaseRepository(TempPurchaseContext context)
        {
            _context = context;
        }

        public async Task<TempPurchase> InsertAsync(TempPurchase tempPurchase)
        {
            try
            {
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
                existing.LocationId = tempPurchase.LocationId;
                existing.ItemId     = tempPurchase.ItemId;
                existing.PDate      = tempPurchase.PDate;
                existing.Cost       = tempPurchase.Cost;
                existing.Rate       = tempPurchase.Rate;
                existing.Qty        = tempPurchase.Qty;
                existing.Discount   = tempPurchase.Discount;
                existing.GAmount    = tempPurchase.GAmount;
                existing.ExpDate    = tempPurchase.ExpDate;
                existing.Status     = tempPurchase.Status;
                existing.Type       = tempPurchase.Type;
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
