using System.Data;
using ItemApi.Models;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;

namespace ItemApi.Data
{
    // Sales dashboard — read-only calls to the z_sp_Dash* procs (DBScript/04_BackOffice_SalesDashboard.sql).
    public partial class AppDbContext
    {
        public async Task<DashTotals> GetDashTotalsAsync(DateTime from, DateTime to, int locationId, int? terminalId) =>
            (await DashQuery<DashTotals>("z_sp_DashTotals", from, to, locationId, terminalId)).First();

        public Task<List<DashDay>> GetDashDailyAsync(DateTime from, DateTime to, int locationId, int? terminalId) =>
            DashQuery<DashDay>("z_sp_DashDaily", from, to, locationId, terminalId);

        public Task<List<DashHour>> GetDashHourlyAsync(DateTime from, DateTime to, int locationId, int? terminalId) =>
            DashQuery<DashHour>("z_sp_DashHourly", from, to, locationId, terminalId);

        public Task<List<DashCategory>> GetDashCategoriesAsync(DateTime from, DateTime to, int locationId, int? terminalId) =>
            DashQuery<DashCategory>("z_sp_DashCategories", from, to, locationId, terminalId);

        // per till is never filtered by till — every till of the location is listed
        public async Task<List<DashTerminal>> GetDashTerminalsAsync(DateTime from, DateTime to, int locationId)
        {
            return await Database.SqlQueryRaw<DashTerminal>(
                "EXEC dbo.z_sp_DashTerminals @FromDate = @FromDate, @ToDate = @ToDate, @LocationId = @LocationId",
                DateParam("@FromDate", from), DateParam("@ToDate", to),
                new SqlParameter("@LocationId", locationId)).ToListAsync();
        }

        // orderBy 1 = by sales, 2 = by profit
        public async Task<List<DashItem>> GetDashTopItemsAsync(DateTime from, DateTime to, int locationId, int? terminalId, int top, int orderBy)
        {
            return await Database.SqlQueryRaw<DashItem>(
                "EXEC dbo.z_sp_DashTopItems @FromDate = @FromDate, @ToDate = @ToDate, @LocationId = @LocationId, " +
                "@TerminalId = @TerminalId, @Top = @Top, @OrderBy = @OrderBy",
                DateParam("@FromDate", from), DateParam("@ToDate", to),
                new SqlParameter("@LocationId", locationId),
                new SqlParameter("@TerminalId", SqlDbType.Int) { Value = (object?)terminalId ?? DBNull.Value },
                new SqlParameter("@Top", top), new SqlParameter("@OrderBy", orderBy)).ToListAsync();
        }

        private async Task<List<T>> DashQuery<T>(string proc, DateTime from, DateTime to, int locationId, int? terminalId)
        {
            return await Database.SqlQueryRaw<T>(
                $"EXEC dbo.{proc} @FromDate = @FromDate, @ToDate = @ToDate, @LocationId = @LocationId, @TerminalId = @TerminalId",
                DateParam("@FromDate", from), DateParam("@ToDate", to),
                new SqlParameter("@LocationId", locationId),
                new SqlParameter("@TerminalId", SqlDbType.Int) { Value = (object?)terminalId ?? DBNull.Value }).ToListAsync();
        }

        private static SqlParameter DateParam(string name, DateTime value) =>
            new(name, SqlDbType.Date) { Value = value.Date };
    }
}
