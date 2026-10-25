using ItemApi.Data;
using ItemApi.Interface;
using ItemApi.Models;
using Microsoft.Extensions.Options;
using Serilog;

namespace ItemApi.Repositories
{
    // Back office Day Reports: any past day — per till sales and drawer cash, the Zs, paid in / out, items, bills.
    // Only as complete as the uploads: a till that is offline shows its bills (and cash in / out) when it reconnects.
    public class DayReportRepository : IDayReportRepository
    {
        private readonly AppDbContext _context;
        private readonly int _locationId;

        public DayReportRepository(AppDbContext context, IOptions<AppSettings> appSettings)
        {
            _context = context;
            _locationId = appSettings.Value.LocationId;
        }

        public async Task<DayReport> GetDayAsync(DateTime date, int? terminalId)
        {
            try
            {
                return new DayReport
                {
                    Date = date.Date,
                    TerminalId = terminalId,
                    Tills = await _context.GetDayTillsAsync(date, _locationId, terminalId),
                    ZReports = await _context.GetDayZReportsAsync(date, _locationId, terminalId),
                    CashMovements = await _context.GetDayCashMovementsAsync(date, _locationId, terminalId)
                };
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex.Message}");
                throw;
            }
        }

        public async Task<List<DayItem>> GetItemsAsync(DateTime date, int? terminalId)
        {
            try
            {
                return await _context.GetDayItemsAsync(date, _locationId, terminalId);
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex.Message}");
                throw;
            }
        }

        public async Task<List<DayBill>> GetBillsAsync(DateTime date, int? terminalId)
        {
            try
            {
                return await _context.GetDayBillsAsync(date, _locationId, terminalId);
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex.Message}");
                throw;
            }
        }

        // void lines / bills, qty cuts and No Sale only show for tills with U019 (zf_tb_VoidLog) and the new TillService
        public async Task<DayLoss> GetLossAsync(DateTime date, int? terminalId)
        {
            try
            {
                return new DayLoss
                {
                    Date = date.Date,
                    TerminalId = terminalId,
                    Cashiers = await _context.GetDayLossCashiersAsync(date, _locationId, terminalId),
                    Voids = await _context.GetDayVoidsAsync(date, _locationId, terminalId),
                    NoSales = await _context.GetDayNoSalesAsync(date, _locationId, terminalId)
                };
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex.Message}");
                throw;
            }
        }

        public async Task<DayBillDetail?> GetBillAsync(string invoiceNo)
        {
            try
            {
                return await _context.GetDayBillAsync(invoiceNo.Trim().ToUpperInvariant());
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex.Message}");
                throw;
            }
        }
    }
}
