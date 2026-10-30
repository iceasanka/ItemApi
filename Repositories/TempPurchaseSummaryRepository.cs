using ItemApi.Data;
using ItemApi.Interface;
using ItemApi.Models;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using Serilog;

namespace ItemApi.Repositories
{
    public class TempPurchaseSummaryRepository : ITempPurchaseSummaryRepository
    {
        private readonly AppDbContext _context;
        // Hard-coded in appsettings.json (AppSettings:LocationId) until the user table is implemented
        private readonly int _locationId;

        public TempPurchaseSummaryRepository(AppDbContext context, IOptions<AppSettings> appSettings)
        {
            _context = context;
            _locationId = appSettings.Value.LocationId;
        }

        public async Task<List<TempPurchaseSummary>> GetAllAsync()
        {
            try
            {
                return await _context.TempPurchaseSummaries
                    .Where(x => x.LocationId == _locationId)
                    .ToListAsync();
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex.Message}");
                throw;
            }
        }

        public async Task<TempPurchaseSummary?> GetByIdAsync(int idx)
        {
            try
            {
                return await _context.TempPurchaseSummaries
                    .FirstOrDefaultAsync(x => x.Idx == idx && x.LocationId == _locationId);
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex.Message}");
                throw;
            }
        }

        public async Task<TempPurchaseSummary> InsertAsync(TempPurchaseSummary summary)
        {
            try
            {
                summary.LocationId = _locationId;
                summary.UDate = DateTime.Now;
                await _context.TempPurchaseSummaries.AddAsync(summary);
                await _context.SaveChangesAsync();
                return summary;
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex.Message}");
                throw;
            }
        }

        public async Task<TempPurchaseSummary> UpdateAsync(TempPurchaseSummary summary)
        {
            try
            {
                var existing = await _context.TempPurchaseSummaries.FindAsync(summary.Idx);
                if (existing == null)
                    throw new Exception($"Record with Idx {summary.Idx} not found.");

                existing.GrnNo        = summary.GrnNo;
                existing.LocationId = _locationId;
                existing.RefNo        = summary.RefNo;
                existing.PDate        = summary.PDate;
                existing.SuppId     = summary.SuppId;
                existing.PMode        = summary.PMode;
                existing.GAmount      = summary.GAmount;
                existing.POderNo      = summary.POderNo;
                existing.SubTotDisc   = summary.SubTotDisc;
                existing.NetAmount    = summary.NetAmount;
                existing.Advance      = summary.Advance;
                existing.Returns      = summary.Returns;
                //existing.Balance      = summary.Balance;
                existing.Qty          = summary.Qty;
                existing.Type         = summary.Type;
                existing.Status       = summary.Status;
                existing.Remark       = summary.Remark;
                existing.UserId       = summary.UserId;
                existing.UDate        = DateTime.Now;

                _context.TempPurchaseSummaries.Update(existing);
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
                var existing = await _context.TempPurchaseSummaries.FindAsync(idx);
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

        // GRN Entry > Search GRN > delete a draft: the summary and its lines in one go, refused once committed (Status 2).
        // A GRN scan made into it (z_tb_GrnScan, U031) is open again, so it can be corrected and made into a draft again.
        public async Task<int> DeleteDraftAsync(string grnNo)
        {
            try
            {
                var result = await _context.Database.SqlQueryRaw<int>(@"
                    SET XACT_ABORT ON;
                    BEGIN TRAN;
                    DECLARE @St INT, @Found INT = 0;
                    SELECT @St = ISNULL(Status, 0), @Found = 1 FROM dbo.z_tb_TempPurchaseSummary WITH (UPDLOCK, HOLDLOCK) WHERE GrnNo = {0};
                    IF @Found = 0 AND EXISTS (SELECT 1 FROM dbo.z_tb_TempPurchase WHERE GrnNo = {0} AND ISNULL(Status, 0) = 2) SET @St = 2;
                    IF @Found = 0 AND @St IS NULL AND NOT EXISTS (SELECT 1 FROM dbo.z_tb_TempPurchase WHERE GrnNo = {0})
                    BEGIN COMMIT; SELECT 1 AS Value; RETURN; END
                    IF @St = 2 BEGIN COMMIT; SELECT 2 AS Value; RETURN; END
                    DELETE FROM dbo.z_tb_TempPurchase WHERE GrnNo = {0};
                    DELETE FROM dbo.z_tb_TempPurchaseSummary WHERE GrnNo = {0};
                    IF OBJECT_ID(N'dbo.z_tb_GrnScan', 'U') IS NOT NULL
                        EXEC sp_executesql N'UPDATE dbo.z_tb_GrnScan SET Status = 0, GrnNo = NULL, UpdatedAt = GETDATE() WHERE GrnNo = @g',
                                           N'@g VARCHAR(20)', @g = {0};
                    COMMIT;
                    SELECT 0 AS Value;", grnNo).ToListAsync();
                return result.First();
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex.Message}");
                throw;
            }
        }

        public async Task<List<TempPurchaseSummary>> SearchAsync(TempPurchaseSummarySearchRequest request)
        {
            try
            {
                var query = from t in _context.TempPurchaseSummaries
                            join s in _context.SupplierEntities
                                on t.SuppId equals s.SuppId into sup
                            from s in sup.DefaultIfEmpty()
                            where t.LocationId == _locationId
                            select new TempPurchaseSummary
                            {
                                Idx = t.Idx,
                                GrnNo = t.GrnNo,
                                LocationId = t.LocationId,
                                RefNo = t.RefNo,
                                PDate = t.PDate,
                                SuppId = t.SuppId,
                                SuppName = s != null ? s.SuppName : "",
                                NetAmount = t.NetAmount,
                                Qty = t.Qty,
                                Status = t.Status,
                                Remark = t.Remark
                            };

                // Filters
                if (!string.IsNullOrWhiteSpace(request.GrnNo))
                    query = query.Where(x => EF.Functions.Like(x.GrnNo, $"%{request.GrnNo}%"));

                if (!string.IsNullOrWhiteSpace(request.RefNo))
                    query = query.Where(x => EF.Functions.Like(x.RefNo, $"%{request.RefNo}%"));

                if (!string.IsNullOrWhiteSpace(request.Remark))
                    query = query.Where(x => EF.Functions.Like(x.Remark, $"%{request.Remark}%"));

                if (request.SuppId != null && request.SuppId != 0)
                    query = query.Where(x => x.SuppId == request.SuppId);

                return await query
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
