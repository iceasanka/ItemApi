using ItemApi.Data;
using ItemApi.Interface;
using ItemApi.Models;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using Serilog;

namespace ItemApi.Repositories
{
    // Stock adjustments — saved and posted in one step by z_sp_SaveStockAdjustment (no draft state).
    public class StockAdjustmentRepository : IStockAdjustmentRepository
    {
        private readonly AppDbContext _context;
        // Hard-coded in appsettings.json (AppSettings:LocationId) until the user table is implemented
        private readonly int _locationId;

        public StockAdjustmentRepository(AppDbContext context, IOptions<AppSettings> appSettings)
        {
            _context = context;
            _locationId = appSettings.Value.LocationId;
        }

        public async Task<StockAdjustment> SaveAsync(StockAdjustmentRequest request)
        {
            try
            {
                var adjNo = await _context.SaveStockAdjustmentAsync(_locationId, request);
                return (await GetByAdjNoAsync(adjNo))!;
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex.Message}");
                throw;
            }
        }

        public async Task<StockAdjustment?> GetByAdjNoAsync(string adjNo)
        {
            try
            {
                var header = await _context.StockAdjustments
                    .FirstOrDefaultAsync(x => x.AdjNo == adjNo && x.LocationId == _locationId);
                if (header == null) return null;

                header.ReasonName = await _context.StockAdjReasons
                    .Where(r => r.ReasonId == header.ReasonId)
                    .Select(r => r.ReasonName)
                    .FirstOrDefaultAsync();

                header.Items = await (from l in _context.StockAdjustmentItems
                                      join i in _context.Itemzs on l.ItemId equals i.ItemId into it
                                      from i in it.DefaultIfEmpty()
                                      where l.AdjId == header.AdjId
                                      orderby l.LineNum
                                      select new StockAdjustmentItem
                                      {
                                          AdjId = l.AdjId,
                                          LineNum = l.LineNum,
                                          ItemId = l.ItemId,
                                          SystemQty = l.SystemQty,
                                          CountedQty = l.CountedQty,
                                          AdjQty = l.AdjQty,
                                          CostPrice = l.CostPrice,
                                          ReasonId = l.ReasonId,
                                          Remark = l.Remark,
                                          RefCode = i != null ? i.RefCode : null,
                                          Descrip = i != null ? i.Descrip : null
                                      }).ToListAsync();

                return header;
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex.Message}");
                throw;
            }
        }

        public async Task<List<StockAdjustment>> SearchAsync(StockAdjustmentSearchRequest request)
        {
            try
            {
                var query = _context.StockAdjustments.Where(x => x.LocationId == _locationId);

                if (!string.IsNullOrWhiteSpace(request.AdjNo))
                    query = query.Where(x => EF.Functions.Like(x.AdjNo, $"%{request.AdjNo}%"));

                if (request.FromDate != null)
                    query = query.Where(x => x.AdjDate >= request.FromDate.Value.Date);

                if (request.ToDate != null)
                    query = query.Where(x => x.AdjDate < request.ToDate.Value.Date.AddDays(1));

                if (request.ReasonId != null && request.ReasonId != 0)
                    query = query.Where(x => x.ReasonId == request.ReasonId);

                var list = await (from a in query
                                  join r in _context.StockAdjReasons on a.ReasonId equals r.ReasonId into rs
                                  from r in rs.DefaultIfEmpty()
                                  orderby a.AdjId descending
                                  select new { a, ReasonName = r != null ? r.ReasonName : null })
                                  .Take(500)
                                  .ToListAsync();

                return list.Select(x => { x.a.ReasonName = x.ReasonName; return x.a; }).ToList();
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex.Message}");
                throw;
            }
        }

        public async Task<List<StockAdjReason>> GetReasonsAsync()
        {
            try
            {
                return await _context.StockAdjReasons
                    .Where(x => x.Status == 1)
                    .OrderBy(x => x.ReasonId)
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
