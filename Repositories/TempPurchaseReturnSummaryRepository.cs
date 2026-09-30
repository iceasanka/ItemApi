using ItemApi.Data;
using ItemApi.Interface;
using ItemApi.Models;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using Serilog;

namespace ItemApi.Repositories
{
    // Purchase return header — same z_tb_TempPurchaseSummary table as GRN, scoped to Type = 2.
    public class TempPurchaseReturnSummaryRepository : ITempPurchaseReturnSummaryRepository
    {
        public const int ReturnType = 2;

        private readonly AppDbContext _context;
        // Hard-coded in appsettings.json (AppSettings:LocationId) until the user table is implemented
        private readonly int _locationId;

        public TempPurchaseReturnSummaryRepository(AppDbContext context, IOptions<AppSettings> appSettings)
        {
            _context = context;
            _locationId = appSettings.Value.LocationId;
        }

        public async Task<List<TempPurchaseReturnSummary>> GetAllAsync()
        {
            try
            {
                var list = await _context.TempPurchaseSummaries
                    .Where(x => x.LocationId == _locationId && x.Type == ReturnType)
                    .ToListAsync();

                return list.Select(ToDto).ToList();
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex.Message}");
                throw;
            }
        }

        public async Task<TempPurchaseReturnSummary?> GetByIdAsync(int idx)
        {
            try
            {
                var entity = await _context.TempPurchaseSummaries
                    .FirstOrDefaultAsync(x => x.Idx == idx && x.LocationId == _locationId && x.Type == ReturnType);

                return entity == null ? null : ToDto(entity);
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex.Message}");
                throw;
            }
        }

        public async Task<TempPurchaseReturnSummary> InsertAsync(TempPurchaseReturnSummary summary)
        {
            try
            {
                var entity = new TempPurchaseSummary();
                CopyToEntity(summary, entity);
                entity.UDate = DateTime.Now;

                await _context.TempPurchaseSummaries.AddAsync(entity);
                await _context.SaveChangesAsync();
                return ToDto(entity);
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex.Message}");
                throw;
            }
        }

        public async Task<TempPurchaseReturnSummary> UpdateAsync(TempPurchaseReturnSummary summary)
        {
            try
            {
                var existing = await _context.TempPurchaseSummaries
                    .FirstOrDefaultAsync(x => x.Idx == summary.Idx && x.Type == ReturnType);
                if (existing == null)
                    throw new Exception($"Return record with Idx {summary.Idx} not found.");

                CopyToEntity(summary, existing);
                existing.UDate = DateTime.Now;

                _context.TempPurchaseSummaries.Update(existing);
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
                var existing = await _context.TempPurchaseSummaries
                    .FirstOrDefaultAsync(x => x.Idx == idx && x.Type == ReturnType);
                if (existing == null) return false;

                _context.TempPurchaseSummaries.Remove(existing);
                await _context.SaveChangesAsync();
                return true;
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex.Message}");
                throw;
            }
        }

        public async Task<List<TempPurchaseReturnSummary>> SearchAsync(TempPurchaseReturnSummarySearchRequest request)
        {
            try
            {
                var headers = _context.TempPurchaseSummaries
                    .Where(t => t.LocationId == _locationId && t.Type == ReturnType);

                // Filters
                if (!string.IsNullOrWhiteSpace(request.PrnNo))
                    headers = headers.Where(t => EF.Functions.Like(t.GrnNo, $"%{request.PrnNo}%"));

                if (!string.IsNullOrWhiteSpace(request.RefNo))
                    headers = headers.Where(t => EF.Functions.Like(t.RefNo, $"%{request.RefNo}%"));

                if (!string.IsNullOrWhiteSpace(request.Remark))
                    headers = headers.Where(t => EF.Functions.Like(t.Remark, $"%{request.Remark}%"));

                if (request.SuppId != null && request.SuppId != 0)
                    headers = headers.Where(t => t.SuppId == request.SuppId);

                var query = from t in headers
                            join s in _context.SupplierEntities
                                on t.SuppId equals s.SuppId into sup
                            from s in sup.DefaultIfEmpty()
                            orderby t.PDate descending
                            select new TempPurchaseReturnSummary
                            {
                                Idx = t.Idx,
                                PrnNo = t.GrnNo,
                                LocationId = t.LocationId,
                                RefNo = t.RefNo,
                                PDate = t.PDate,
                                SuppId = t.SuppId,
                                SuppName = s != null ? s.SuppName : "",
                                RetType = t.PMode,
                                NetAmount = t.NetAmount,
                                Qty = t.Qty,
                                Type = t.Type,
                                Status = t.Status,
                                Remark = t.Remark
                            };

                return await query.ToListAsync();
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex.Message}");
                throw;
            }
        }

        private void CopyToEntity(TempPurchaseReturnSummary dto, TempPurchaseSummary entity)
        {
            entity.GrnNo      = dto.PrnNo;
            entity.LocationId = _locationId;
            entity.RefNo      = dto.RefNo;
            entity.PDate      = dto.PDate;
            entity.SuppId     = dto.SuppId;
            entity.PMode      = dto.RetType;
            entity.GAmount    = dto.GAmount;
            entity.POderNo    = dto.POderNo;
            entity.SubTotDisc = dto.SubTotDisc;
            entity.NetAmount  = dto.NetAmount;
            entity.Qty        = dto.Qty;
            entity.Type       = ReturnType;
            entity.Status     = dto.Status;
            entity.Remark     = dto.Remark;
            entity.UserId     = dto.UserId;
        }

        private static TempPurchaseReturnSummary ToDto(TempPurchaseSummary entity) => new()
        {
            Idx        = entity.Idx,
            PrnNo      = entity.GrnNo,
            LocationId = entity.LocationId,
            RefNo      = entity.RefNo,
            PDate      = entity.PDate,
            SuppId     = entity.SuppId,
            RetType    = entity.PMode,
            GAmount    = entity.GAmount,
            POderNo    = entity.POderNo,
            SubTotDisc = entity.SubTotDisc,
            NetAmount  = entity.NetAmount,
            Qty        = entity.Qty,
            Type       = entity.Type,
            Status     = entity.Status,
            Remark     = entity.Remark,
            UDate      = entity.UDate,
            UserId     = entity.UserId
        };
    }
}
