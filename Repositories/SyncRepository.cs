using ItemApi.Common;
using ItemApi.Data;
using ItemApi.Interface;
using ItemApi.Models;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using Serilog;

namespace ItemApi.Repositories
{
    // Cashier till <-> back office sync. Items/prices/stock go DOWN, invoices and Z reports come UP.
    // Tills never change stock or items on the server; the server never changes bills.
    public class SyncRepository : ISyncRepository
    {
        // A till that has not called POST api/Sync/Invoices (it also works as a heartbeat) for this long
        // may be holding unsent bills — shown as a warning before stock counts.
        private static readonly TimeSpan StaleAfter = TimeSpan.FromMinutes(30);

        private readonly AppDbContext _context;
        // Hard-coded in appsettings.json (AppSettings:LocationId) until the user table is implemented
        private readonly int _locationId;

        public SyncRepository(AppDbContext context, IOptions<AppSettings> appSettings)
        {
            _context = context;
            _locationId = appSettings.Value.LocationId;
        }

        public async Task<Terminal> RegisterTerminalAsync(TerminalRegisterRequest request)
        {
            try
            {
                var terminal = await _context.Terminals.FindAsync(request.TerminalId);
                if (terminal == null)
                {
                    terminal = new Terminal
                    {
                        TerminalId = request.TerminalId,
                        LocationId = _locationId,
                        CDate = DateTime.Now
                    };
                    await _context.Terminals.AddAsync(terminal);
                }

                terminal.TerminalCode = request.TerminalCode.Trim().ToUpperInvariant();
                terminal.TerminalName = request.TerminalName;
                terminal.Status = request.Status;

                await _context.SaveChangesAsync();
                return terminal;
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex.Message}");
                throw;
            }
        }

        public async Task<List<TerminalStatus>> GetTerminalsAsync()
        {
            try
            {
                var now = await _context.GetServerTimeAsync();

                var list = await (from t in _context.Terminals
                                  where t.LocationId == _locationId
                                  orderby t.TerminalId
                                  select new TerminalStatus
                                  {
                                      TerminalId = t.TerminalId,
                                      TerminalCode = t.TerminalCode,
                                      TerminalName = t.TerminalName,
                                      Status = t.Status,
                                      LastSyncAt = t.LastSyncAt,
                                      LastItemSyncAt = t.LastItemSyncAt,
                                      LastZNo = t.LastZNo,
                                      OpenZCount = _context.ZReports.Count(z => z.TerminalId == t.TerminalId
                                          && z.Status != (int)Meta.ZReportStatus.Reconciled)
                                  }).ToListAsync();

                foreach (var t in list)
                    t.IsStale = t.Status == 1 && (t.LastSyncAt == null || now - t.LastSyncAt.Value > StaleAfter);

                return list;
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex.Message}");
                throw;
            }
        }

        public async Task<SyncDownload<SyncItem>> GetItemsAsync(int terminalId, DateTime? since)
        {
            try
            {
                // taken BEFORE reading, so anything changed while reading is sent again next time
                var serverTime = await _context.GetServerTimeAsync();
                var rows = await _context.GetItemsForSyncAsync(terminalId, since);
                return new SyncDownload<SyncItem> { ServerTime = serverTime, Rows = rows };
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex.Message}");
                throw;
            }
        }

        public async Task<SyncDownload<SyncStockBalance>> GetStockBalancesAsync(int terminalId, DateTime? since)
        {
            try
            {
                var serverTime = await _context.GetServerTimeAsync();
                var rows = await _context.GetStockBalanceForSyncAsync(terminalId, since);
                return new SyncDownload<SyncStockBalance> { ServerTime = serverTime, Rows = rows };
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex.Message}");
                throw;
            }
        }

        public async Task<List<SyncInvoiceResult>> UploadInvoicesAsync(SyncInvoiceBatch batch)
        {
            try
            {
                // an empty batch is a heartbeat: it only updates z_tb_Terminal.LastSyncAt
                return await _context.SyncSalesInvoicesAsync(batch.TerminalId, batch.Invoices);
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex.Message}");
                throw;
            }
        }

        public async Task<ZReportSubmitResponse> SubmitZReportAsync(ZReportSubmit z)
        {
            try
            {
                var result = await _context.SubmitZReportAsync(z);
                return await WithMissingAsync(result);
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex.Message}");
                throw;
            }
        }

        public async Task<ZReportSubmitResponse> ReconcileZReportAsync(int terminalId, int zNo)
        {
            try
            {
                var result = await _context.ReconcileZReportAsync(terminalId, zNo);
                return await WithMissingAsync(result);
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex.Message}");
                throw;
            }
        }

        public async Task<ZReport?> GetZReportAsync(int terminalId, int zNo)
        {
            try
            {
                var z = await _context.ZReports
                    .FirstOrDefaultAsync(x => x.TerminalId == terminalId && x.ZNo == zNo && x.LocationId == _locationId);
                if (z == null) return null;

                z.TerminalCode = await _context.Terminals
                    .Where(t => t.TerminalId == terminalId)
                    .Select(t => t.TerminalCode)
                    .FirstOrDefaultAsync();

                z.Items = await (from zi in _context.ZReportItems
                                 join i in _context.Itemzs on zi.ItemId equals i.ItemId into it
                                 from i in it.DefaultIfEmpty()
                                 where zi.ZId == z.ZId
                                 orderby i.Descrip
                                 select new ZReportItem
                                 {
                                     ZId = zi.ZId,
                                     ItemId = zi.ItemId,
                                     Qty = zi.Qty,
                                     Amount = zi.Amount,
                                     SrvQty = zi.SrvQty,
                                     SrvAmount = zi.SrvAmount,
                                     RefCode = i != null ? i.RefCode : null,
                                     Descrip = i != null ? i.Descrip : null
                                 }).ToListAsync();

                return z;
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex.Message}");
                throw;
            }
        }

        public async Task<List<ZReport>> SearchZReportsAsync(ZReportSearchRequest request)
        {
            try
            {
                var query = _context.ZReports.Where(x => x.LocationId == _locationId);

                if (request.FromDate != null)
                    query = query.Where(x => x.BusinessDate >= request.FromDate.Value.Date);

                if (request.ToDate != null)
                    query = query.Where(x => x.BusinessDate <= request.ToDate.Value.Date);

                if (request.TerminalId != null && request.TerminalId != 0)
                    query = query.Where(x => x.TerminalId == request.TerminalId);

                if (request.Status != null && request.Status != 0)
                    query = query.Where(x => x.Status == request.Status);

                var list = await (from z in query
                                  join t in _context.Terminals on z.TerminalId equals t.TerminalId into ts
                                  from t in ts.DefaultIfEmpty()
                                  orderby z.BusinessDate descending, z.TerminalId
                                  select new { z, Code = t != null ? t.TerminalCode : null })
                                  .Take(500)
                                  .ToListAsync();

                return list.Select(x => { x.z.TerminalCode = x.Code; return x.z; }).ToList();
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex.Message}");
                throw;
            }
        }

        private async Task<ZReportSubmitResponse> WithMissingAsync(ZReportResult? result)
        {
            var response = new ZReportSubmitResponse { Result = result! };

            if (result != null && result.Status == (int)Meta.ZReportStatus.Mismatch && result.MissingCount > 0)
                response.MissingInvoiceNos = (await _context.GetZMissingInvoicesAsync(result.TerminalId, result.ZNo))
                    .Select(x => x.InvoiceNo)
                    .ToList();

            return response;
        }
    }
}
