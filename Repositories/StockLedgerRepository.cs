using ItemApi.Common;
using ItemApi.Data;
using ItemApi.Interface;
using ItemApi.Models;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using Serilog;

namespace ItemApi.Repositories
{
    // Stock balance / item card reads, and GRN/PRN posting (through z_sp_PostPurchaseDoc).
    public class StockLedgerRepository : IStockLedgerRepository
    {
        private readonly AppDbContext _context;
        // Hard-coded in appsettings.json (AppSettings:LocationId) until the user table is implemented
        private readonly int _locationId;

        public StockLedgerRepository(AppDbContext context, IOptions<AppSettings> appSettings)
        {
            _context = context;
            _locationId = appSettings.Value.LocationId;
        }

        public async Task<StockBalanceRow?> GetBalanceAsync(int itemId)
        {
            try
            {
                return await BalanceQuery().FirstOrDefaultAsync(x => x.ItemId == itemId);
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex.Message}");
                throw;
            }
        }

        public async Task<StockBalancePage> SearchBalancesAsync(StockBalanceSearchRequest request)
        {
            try
            {
                var query = from i in _context.Itemzs
                            join b in _context.StockBalances.Where(b => b.LocationId == _locationId)
                                on i.ItemId equals b.ItemId into bal
                            from b in bal.DefaultIfEmpty()
                            select new { i, b };

                if (!string.IsNullOrWhiteSpace(request.Query))
                    query = query.Where(x => EF.Functions.Like(x.i.RefCode, $"%{request.Query}%")
                                          || EF.Functions.Like(x.i.Barcode, $"%{request.Query}%")
                                          || EF.Functions.Like(x.i.Descrip, $"%{request.Query}%"));

                if (request.CatId != null && request.CatId != 0)
                    query = query.Where(x => x.i.CatId == request.CatId);

                if (request.SupId != null && request.SupId != 0)
                    query = query.Where(x => x.i.SupId == request.SupId);

                if (request.OnlyNegative)
                    query = query.Where(x => x.b != null && x.b.Qty < 0);

                int pageSize = Math.Clamp(request.PageSize, 1, 500);
                int page = Math.Max(request.Page, 1);

                var total = await query.CountAsync();
                // production easyway runs on SQL Server 2008 R2: no OFFSET/FETCH, so TOP (page * pageSize) and skip here
                var rows = (await query
                    .OrderBy(x => x.i.Descrip).ThenBy(x => x.i.ItemId)
                    .Take(page * pageSize)
                    .Select(x => new StockBalanceRow
                    {
                        ItemId = x.i.ItemId,
                        RefCode = x.i.RefCode,
                        Barcode = x.i.Barcode,
                        Descrip = x.i.Descrip,
                        Qty = x.b != null ? x.b.Qty : 0,
                        AvgCost = x.b != null ? x.b.AvgCost : null,
                        StockValue = x.b != null ? x.b.Qty * (x.b.AvgCost ?? 0) : 0,
                        UDate = x.b != null ? x.b.UDate : null
                    })
                    .ToListAsync()).Skip((page - 1) * pageSize).ToList();

                return new StockBalancePage { Total = total, Rows = rows };
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex.Message}");
                throw;
            }
        }

        public async Task<ItemCard?> GetItemCardAsync(int itemId, DateTime fromDate, DateTime toDate)
        {
            try
            {
                var item = await _context.Itemzs.FirstOrDefaultAsync(x => x.ItemId == itemId);
                if (item == null) return null;

                var from = fromDate.Date;
                var toExclusive = toDate.Date.AddDays(1);

                var ledger = _context.StockLedgers.Where(x => x.LocationId == _locationId && x.ItemId == itemId);

                var opening = await ledger.Where(x => x.TxnDate < from).SumAsync(x => (decimal?)x.Qty) ?? 0;

                var moves = await ledger
                    .Where(x => x.TxnDate >= from && x.TxnDate < toExclusive)
                    .OrderBy(x => x.TxnDate).ThenBy(x => x.LedgerId)
                    .ToListAsync();

                // DB compatibility level 100 has no running SUM() OVER, so the balance column is built here
                var card = new ItemCard
                {
                    ItemId = itemId,
                    RefCode = item.RefCode,
                    Descrip = item.Descrip,
                    FromDate = from,
                    ToDate = toDate.Date,
                    OpeningQty = opening
                };

                decimal running = opening;
                foreach (var m in moves)
                {
                    running += m.Qty;
                    card.Rows.Add(new ItemCardRow
                    {
                        LedgerId = m.LedgerId,
                        TxnDate = m.TxnDate,
                        TxnType = m.TxnType,
                        TxnTypeName = ((Meta.StockTxnType)m.TxnType).ToString(),
                        DocNo = m.DocNo,
                        TerminalId = m.TerminalId,
                        ZNo = m.ZNo,
                        QtyIn = m.Qty > 0 ? m.Qty : 0,
                        QtyOut = m.Qty < 0 ? -m.Qty : 0,
                        Balance = running,
                        CostPrice = m.CostPrice,
                        SellPrice = m.SellPrice,
                        UserId = m.UserId
                    });
                }
                card.ClosingQty = running;

                return card;
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex.Message}");
                throw;
            }
        }

        public async Task<int> PostGrnAsync(string grnNo, string? userId)
        {
            return await _context.PostPurchaseDocAsync(grnNo, (int)Meta.StockTxnType.Grn, userId);
        }

        public async Task<int> PostPrnAsync(string prnNo, string? userId)
        {
            return await _context.PostPurchaseDocAsync(prnNo, (int)Meta.StockTxnType.Prn, userId);
        }

        private IQueryable<StockBalanceRow> BalanceQuery()
        {
            return from i in _context.Itemzs
                   join b in _context.StockBalances.Where(b => b.LocationId == _locationId)
                       on i.ItemId equals b.ItemId into bal
                   from b in bal.DefaultIfEmpty()
                   select new StockBalanceRow
                   {
                       ItemId = i.ItemId,
                       RefCode = i.RefCode,
                       Barcode = i.Barcode,
                       Descrip = i.Descrip,
                       Qty = b != null ? b.Qty : 0,
                       AvgCost = b != null ? b.AvgCost : null,
                       StockValue = b != null ? b.Qty * (b.AvgCost ?? 0) : 0,
                       UDate = b != null ? b.UDate : null
                   };
        }
    }
}
