using ItemApi.Data;
using ItemApi.Interface;
using ItemApi.Models;
using Microsoft.EntityFrameworkCore;
using Serilog;

namespace ItemApi.Repositories
{
    public class TempPurchaseSummaryRepository : ITempPurchaseSummaryRepository
    {
        private readonly TempPurchaseSummaryContext _context;

        public TempPurchaseSummaryRepository(TempPurchaseSummaryContext context)
        {
            _context = context;
        }

        public async Task<List<TempPurchaseSummary>> GetAllAsync()
        {
            try
            {
                return await _context.TempPurchaseSummaries.ToListAsync();
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
                return await _context.TempPurchaseSummaries.FindAsync(idx);
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
                existing.LocaId     = summary.LocaId;
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

        public async Task<List<TempPurchaseSummary>> SearchAsync(TempPurchaseSummarySearchRequest request)
        {
            try
            {
                var query = from t in _context.TempPurchaseSummaries
                            join s in _context.dbSetSuppliers
                                on t.SuppId equals s.SuppId into sup
                            from s in sup.DefaultIfEmpty()
                            select new TempPurchaseSummary
                            {
                                Idx = t.Idx,
                                GrnNo = t.GrnNo,
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
