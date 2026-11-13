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

        // Costs to check before a GRN goes to stock. Cost = the line's cost a piece (what the stock batch takes).
        //   - above the sell price (the line's, else the item's retail price): a loss on every one sold
        //   - 2x or more / a third or less of our cost now: a case / line total taken as the cost a piece, or the reverse
        // Free-only lines (no cost) are not checked.
        private const decimal CostCheckHighTimes = 2m, CostCheckLowTimes = 3m;

        public async Task<List<GrnCostCheckLine>> GetCostChecksAsync(string grnNo)
        {
            try
            {
                var rows = await _context.Database.SqlQueryRaw<GrnCostCheckLine>(@"
                    SELECT x.LineNum, x.ItemId, x.Descrip, x.Qty, x.Cost, x.SellPrice, x.OurCost, CAST('' AS NVARCHAR(200)) AS Reason
                    FROM (SELECT ROW_NUMBER() OVER (ORDER BY p.Idx) AS LineNum, p.ItemId, i.Descrip,
                                 CAST(ISNULL(p.Qty, 0) AS DECIMAL(18,2)) AS Qty, CAST(ISNULL(p.CostPrice, 0) AS DECIMAL(18,2)) AS Cost,
                                 CAST(ISNULL(NULLIF(p.SellPrice, 0), NULLIF(d.RetailPrice, 0)) AS DECIMAL(18,2)) AS SellPrice,
                                 CAST(NULLIF(d.CostPrice, 0) AS DECIMAL(18,2)) AS OurCost
                          FROM dbo.z_tb_TempPurchase p
                          LEFT JOIN dbo.z_tb_Item i    ON i.ItemId = p.ItemId
                          LEFT JOIN dbo.z_tb_ItemDet d ON d.ItemId = p.ItemId AND d.LocationId = p.LocationId
                          WHERE p.GrnNo = {0} AND p.LocationId = {1} AND ISNULL(p.Status, 0) <> 2) x
                    WHERE x.Cost > 0
                      AND (x.Cost > x.SellPrice OR x.Cost >= x.OurCost * {2} OR x.Cost * {3} <= x.OurCost)
                    ORDER BY x.LineNum;", grnNo, _locationId, CostCheckHighTimes, CostCheckLowTimes).ToListAsync();

                foreach (var r in rows)
                {
                    var why = new List<string>();
                    if (r.SellPrice > 0 && r.Cost > r.SellPrice)
                        why.Add($"cost {r.Cost:0.00} is above the sell price {r.SellPrice:0.00}");
                    if (r.OurCost > 0 && (r.Cost >= r.OurCost * CostCheckHighTimes || r.Cost * CostCheckLowTimes <= r.OurCost))
                        why.Add($"cost {r.Cost:0.00} is {r.Cost / r.OurCost:0.#}x our cost now {r.OurCost:0.00}");
                    r.Reason = string.Join("; ", why) + " - a case / line total entered as the cost of one?";
                }
                return rows;
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
