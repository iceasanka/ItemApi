using ItemApi.Common;
using ItemApi.Data;
using ItemApi.Interface;
using ItemApi.Models;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using Serilog;

namespace ItemApi.Repositories
{
    // Stock take: count sheets → counts → one stock adjustment for the differences (z_sp_PostStockTake).
    public class StockTakeRepository : IStockTakeRepository
    {
        private readonly AppDbContext _context;
        // Hard-coded in appsettings.json (AppSettings:LocationId) until the user table is implemented
        private readonly int _locationId;

        public StockTakeRepository(AppDbContext context, IOptions<AppSettings> appSettings)
        {
            _context = context;
            _locationId = appSettings.Value.LocationId;
        }

        public async Task<StockTake> CreateAsync(StockTakeCreateRequest request)
        {
            try
            {
                var created = await _context.CreateStockTakeAsync(_locationId, request);
                return (await GetAsync(created.StockTakeId))!;
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex.Message}");
                throw;
            }
        }

        public async Task<List<StockTake>> SearchAsync(StockTakeSearchRequest request)
        {
            try
            {
                var query = _context.StockTakes.AsNoTracking().Where(x => x.LocationId == _locationId);

                if (!string.IsNullOrWhiteSpace(request.StockTakeNo))
                    query = query.Where(x => EF.Functions.Like(x.StockTakeNo!, $"%{request.StockTakeNo}%"));
                if (request.FromDate != null)
                    query = query.Where(x => x.FreezeAt >= request.FromDate.Value.Date);
                if (request.ToDate != null)
                    query = query.Where(x => x.FreezeAt < request.ToDate.Value.Date.AddDays(1));
                if (request.Status != null && request.Status != 0)
                    query = query.Where(x => x.Status == request.Status);

                var list = await query.OrderByDescending(x => x.StockTakeId).Take(500).ToListAsync();
                await FillCountsAsync(list);
                return list;
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex.Message}");
                throw;
            }
        }

        public async Task<StockTake?> GetAsync(int stockTakeId)
        {
            try
            {
                var header = await _context.StockTakes.AsNoTracking()
                    .FirstOrDefaultAsync(x => x.StockTakeId == stockTakeId && x.LocationId == _locationId);
                if (header == null) return null;

                var sheets = await _context.StockTakeSheets.AsNoTracking()
                    .Where(s => s.StockTakeId == stockTakeId)
                    .OrderBy(s => s.SheetNo)
                    .ToListAsync();
                var lineStats = await _context.StockTakeItems.AsNoTracking()
                    .Where(x => x.StockTakeId == stockTakeId)
                    .GroupBy(x => x.SheetId)
                    .Select(g => new { SheetId = g.Key, Lines = g.Count(), Counted = g.Count(x => x.CountedQty != null) })
                    .ToListAsync();
                foreach (var s in sheets)
                {
                    var st = lineStats.FirstOrDefault(x => x.SheetId == s.SheetId);
                    s.LineCount = st?.Lines ?? 0;
                    s.CountedLines = st?.Counted ?? 0;
                }

                header.Sheets = sheets;
                await FillCountsAsync(new List<StockTake> { header });
                return header;
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex.Message}");
                throw;
            }
        }

        public async Task<StockTakeSheetView?> GetSheetAsync(int stockTakeId, int sheetId, bool showSystemQty)
        {
            try
            {
                var header = await _context.StockTakes.AsNoTracking()
                    .FirstOrDefaultAsync(x => x.StockTakeId == stockTakeId && x.LocationId == _locationId);
                var sheet = await _context.StockTakeSheets.AsNoTracking()
                    .FirstOrDefaultAsync(s => s.SheetId == sheetId && s.StockTakeId == stockTakeId);
                if (header == null || sheet == null) return null;

                var lines = await _context.GetStockTakeSheetLinesAsync(sheetId, _locationId, showSystemQty);
                sheet.LineCount = lines.Count;
                sheet.CountedLines = lines.Count(l => l.CountedQty != null);
                return new StockTakeSheetView { Header = header, Sheet = sheet, Lines = lines };
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex.Message}");
                throw;
            }
        }

        public async Task<StockTakeSheet> AddSheetAsync(int stockTakeId, StockTakeAddSheetRequest request)
        {
            try
            {
                await EnsureHereAsync(stockTakeId);
                var sheetId = await _context.AddStockTakeSheetAsync(stockTakeId, request.SheetName.Trim(), request.CountedBy);
                return await _context.StockTakeSheets.AsNoTracking().FirstAsync(s => s.SheetId == sheetId);
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex.Message}");
                throw;
            }
        }

        public async Task<StockTakeSheetLine> AddItemAsync(int stockTakeId, int sheetId, StockTakeAddItemRequest request)
        {
            try
            {
                await EnsureHereAsync(stockTakeId);
                var itemId = request.ItemId ?? 0;
                if (itemId == 0)
                {
                    // scanned or typed: barcode first, then item code
                    var code = (request.Code ?? "").Trim();
                    itemId = await _context.Itemzs.AsNoTracking()
                                 .Where(i => i.Barcode == code).Select(i => i.ItemId).FirstOrDefaultAsync();
                    if (itemId == 0)
                        itemId = await _context.Itemzs.AsNoTracking()
                                     .Where(i => i.RefCode == code).Select(i => i.ItemId).FirstOrDefaultAsync();
                    if (itemId == 0)
                        throw new KeyNotFoundException($"No item with barcode or code \"{code}\".");
                }

                await _context.AddStockTakeItemAsync(stockTakeId, sheetId, itemId);
                var lines = await _context.GetStockTakeSheetLinesAsync(sheetId, _locationId, false);
                return lines.First(l => l.ItemId == itemId);
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex.Message}");
                throw;
            }
        }

        public async Task SaveCountsAsync(int stockTakeId, int sheetId, StockTakeCountsRequest request)
        {
            try
            {
                await EnsureHereAsync(stockTakeId);
                await _context.SaveStockTakeCountsAsync(stockTakeId, sheetId, request);
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex.Message}");
                throw;
            }
        }

        public async Task<StockTakeVariance?> GetVarianceAsync(int stockTakeId, bool onlyDiff)
        {
            try
            {
                var header = await _context.StockTakes.AsNoTracking()
                    .FirstOrDefaultAsync(x => x.StockTakeId == stockTakeId && x.LocationId == _locationId);
                if (header == null) return null;

                var rows = await _context.GetStockTakeVarianceAsync(stockTakeId);
                var result = new StockTakeVariance
                {
                    Header = header,
                    ItemCount = rows.Count,
                    CountedItems = rows.Count(r => r.CountedQty != null),
                    UncountedItems = rows.Count(r => r.CountedQty == null),
                    ItemsWithDiff = rows.Count(r => (r.DiffQty ?? 0) != 0),
                    ShortValue = rows.Where(r => r.DiffValue < 0).Sum(r => r.DiffValue ?? 0),
                    ExcessValue = rows.Where(r => r.DiffValue > 0).Sum(r => r.DiffValue ?? 0),
                };
                result.NetValue = result.ShortValue + result.ExcessValue;
                result.Rows = onlyDiff ? rows.Where(r => r.CountedQty == null || r.DiffQty != 0).ToList() : rows;
                return result;
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex.Message}");
                throw;
            }
        }

        public async Task<StockTakePostResult> PostAsync(int stockTakeId, StockTakePostRequest request)
        {
            try
            {
                await EnsureHereAsync(stockTakeId);
                return await _context.PostStockTakeAsync(stockTakeId, request);
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex.Message}");
                throw;
            }
        }

        public async Task CancelAsync(int stockTakeId, string? userId)
        {
            try
            {
                await EnsureHereAsync(stockTakeId);
                await _context.CancelStockTakeAsync(stockTakeId, userId);
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex.Message}");
                throw;
            }
        }

        // ─── helpers ─────────────────────────────────────────────────────────────

        private async Task EnsureHereAsync(int stockTakeId)
        {
            if (!await _context.StockTakes.AnyAsync(x => x.StockTakeId == stockTakeId && x.LocationId == _locationId))
                throw new KeyNotFoundException($"Stock take {stockTakeId} not found.");
        }

        // item and sheet counts for the list / header
        private async Task FillCountsAsync(List<StockTake> list)
        {
            if (list.Count == 0) return;
            var ids = list.Select(x => x.StockTakeId).ToList();

            var items = await _context.StockTakeItems.AsNoTracking()
                .Where(x => ids.Contains(x.StockTakeId))
                .GroupBy(x => new { x.StockTakeId, x.ItemId })
                .Select(g => new { g.Key.StockTakeId, Counted = g.Any(x => x.CountedQty != null) })
                .ToListAsync();
            var sheets = await _context.StockTakeSheets.AsNoTracking()
                .Where(s => ids.Contains(s.StockTakeId))
                .Select(s => new { s.StockTakeId, s.Status })
                .ToListAsync();

            foreach (var t in list)
            {
                t.ItemCount = items.Count(x => x.StockTakeId == t.StockTakeId);
                t.CountedItems = items.Count(x => x.StockTakeId == t.StockTakeId && x.Counted);
                t.SheetCount = sheets.Count(x => x.StockTakeId == t.StockTakeId);
                t.SheetsDone = sheets.Count(x => x.StockTakeId == t.StockTakeId && x.Status == 2);
            }
        }
    }
}
