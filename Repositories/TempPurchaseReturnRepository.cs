using ItemApi.Data;
using ItemApi.Interface;
using ItemApi.Models;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using Serilog;

namespace ItemApi.Repositories
{
    // Purchase return lines — same z_tb_TempPurchase table as GRN, scoped to GrnNo starting with "PRN".
    public class TempPurchaseReturnRepository : ITempPurchaseReturnRepository
    {
        public const string PrnPrefix = "PRN";

        private readonly AppDbContext _context;
        // Hard-coded in appsettings.json (AppSettings:LocationId) until the user table is implemented
        private readonly int _locationId;

        public TempPurchaseReturnRepository(AppDbContext context, IOptions<AppSettings> appSettings)
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
                var existing = await _context.TempPurchases
                    .FirstOrDefaultAsync(x => x.Idx == tempPurchase.Idx && x.GrnNo.StartsWith(PrnPrefix));
                if (existing == null)
                    throw new Exception($"Return record with Idx {tempPurchase.Idx} not found.");

                existing.GrnNo      = tempPurchase.GrnNo;
                existing.LocationId = _locationId;
                existing.ItemId     = tempPurchase.ItemId;
                existing.PDate      = tempPurchase.PDate;
                existing.CostPrice  = tempPurchase.CostPrice;
                existing.SellPrice  = tempPurchase.SellPrice;
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
                var existing = await _context.TempPurchases
                    .FirstOrDefaultAsync(x => x.Idx == idx && x.GrnNo.StartsWith(PrnPrefix));
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

        public async Task<List<TempPurchase>> GetByPrnNoAsync(string prnNo)
        {
            try
            {
                return await _context.TempPurchases
                    .Where(x => x.LocationId == _locationId)
                    .Where(x => x.GrnNo.StartsWith(PrnPrefix))
                    .Where(x => EF.Functions.Like(x.GrnNo, $"%{prnNo}%"))
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
