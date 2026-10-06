using ItemApi.Data;
using ItemApi.Interface;
using ItemApi.Models;
using Microsoft.Extensions.Options;
using Serilog;

namespace ItemApi.Repositories
{
    // Sales + profit from the bills the tills uploaded (home page "today" and the sales analysis screen).
    // The numbers are only as fresh as the uploads: a till that is offline shows its bills when it reconnects.
    public class DashboardRepository : IDashboardRepository
    {
        private readonly AppDbContext _context;
        private readonly int _locationId;
        private readonly bool _livePush;

        public DashboardRepository(AppDbContext context, IOptions<AppSettings> appSettings, IConfiguration config)
        {
            _context = context;
            _locationId = appSettings.Value.LocationId;
            _livePush = config.GetValue("Dashboard:LivePush", true);
        }

        public async Task<DashboardToday> GetTodayAsync(int? terminalId)
        {
            try
            {
                // the server's date, not the browser's — bills carry the till's clock, which should match the server
                var now = await _context.GetServerTimeAsync();
                var today = now.Date;
                return new DashboardToday
                {
                    ServerTime = now,
                    Date = today,
                    LivePush = _livePush,
                    Totals = await _context.GetDashTotalsAsync(today, today, _locationId, terminalId),
                    Terminals = await _context.GetDashTerminalsAsync(today, today, _locationId),
                    Hourly = await _context.GetDashHourlyAsync(today, today, _locationId, terminalId),
                    TopItems = await _context.GetDashTopItemsAsync(today, today, _locationId, terminalId, 10, 1)
                };
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex.Message}");
                throw;
            }
        }

        public async Task<DashboardSales> GetSalesAsync(DateTime fromDate, DateTime toDate, int? terminalId, int top)
        {
            try
            {
                var from = fromDate.Date;
                var to = toDate.Date;
                return new DashboardSales
                {
                    FromDate = from,
                    ToDate = to,
                    TerminalId = terminalId,
                    Totals = await _context.GetDashTotalsAsync(from, to, _locationId, terminalId),
                    Daily = await _context.GetDashDailyAsync(from, to, _locationId, terminalId),
                    Terminals = await _context.GetDashTerminalsAsync(from, to, _locationId),
                    Hourly = await _context.GetDashHourlyAsync(from, to, _locationId, terminalId),
                    TopItems = await _context.GetDashTopItemsAsync(from, to, _locationId, terminalId, top, 1),
                    TopProfitItems = await _context.GetDashTopItemsAsync(from, to, _locationId, terminalId, top, 2),
                    Categories = await _context.GetDashCategoriesAsync(from, to, _locationId, terminalId)
                };
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex.Message}");
                throw;
            }
        }
    }
}
