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

        public async Task<TempPurchaseReturn> InsertAsync(TempPurchaseReturn item)
        {
            try
            {
                var entity = new TempPurchase();
                CopyToEntity(item, entity);
                entity.UDate = DateTime.Now;

                await _context.TempPurchases.AddAsync(entity);
                await _context.SaveChangesAsync();
                return ToDto(entity);
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex.Message}");
                throw;
            }
        }

        public async Task<TempPurchaseReturn> UpdateAsync(TempPurchaseReturn item)
        {
            try
            {
                var existing = await _context.TempPurchases
                    .FirstOrDefaultAsync(x => x.Idx == item.Idx && x.GrnNo.StartsWith(PrnPrefix));
                if (existing == null)
                    throw new Exception($"Return record with Idx {item.Idx} not found.");

                CopyToEntity(item, existing);
                existing.UDate = DateTime.Now;

                _context.TempPurchases.Update(existing);
                await _context.SaveChangesAsync();
                return ToDto(existing);
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

        public async Task<List<TempPurchaseReturn>> GetByPrnNoAsync(string prnNo)
        {
            try
            {
                var list = await _context.TempPurchases
                    .Where(x => x.LocationId == _locationId)
                    .Where(x => x.GrnNo.StartsWith(PrnPrefix))
                    .Where(x => EF.Functions.Like(x.GrnNo, $"%{prnNo}%"))
                    .OrderByDescending(x => x.PDate)
                    .ToListAsync();

                return list.Select(ToDto).ToList();
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex.Message}");
                throw;
            }
        }

        private void CopyToEntity(TempPurchaseReturn dto, TempPurchase entity)
        {
            entity.GrnNo      = dto.PrnNo;
            entity.LocationId = _locationId;
            entity.ItemId     = dto.ItemId;
            entity.PDate      = dto.PDate;
            entity.CostPrice  = dto.CostPrice;
            entity.SellPrice  = dto.SellPrice;
            entity.Qty        = dto.Qty;
            entity.Discount   = dto.Discount;
            entity.GAmount    = dto.GAmount;
            entity.ExpDate    = dto.ExpDate;
            entity.Status     = dto.Status;
            entity.UserId     = dto.UserId;
        }

        private static TempPurchaseReturn ToDto(TempPurchase entity) => new()
        {
            Idx        = entity.Idx,
            PrnNo      = entity.GrnNo,
            LocationId = entity.LocationId,
            ItemId     = entity.ItemId,
            PDate      = entity.PDate,
            CostPrice  = entity.CostPrice,
            SellPrice  = entity.SellPrice,
            Qty        = entity.Qty,
            Discount   = entity.Discount,
            GAmount    = entity.GAmount,
            ExpDate    = entity.ExpDate,
            Status     = entity.Status,
            UDate      = entity.UDate,
            UserId     = entity.UserId
        };
    }
}
