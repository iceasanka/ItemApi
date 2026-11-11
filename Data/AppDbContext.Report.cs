using System.Data;
using ItemApi.Models;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;

namespace ItemApi.Data
{
    // Back office > Reports - z_sp_Rpt* procs (DBScript U057 / 36_BackOffice_Reports.sql). Read only, except
    // SetItemsActiveAsync (z_tb_Item.Status; refused with RAISERROR → SqlException 50000 when an item has stock).
    public partial class AppDbContext
    {
        public Task<List<RptPeriodRow>> GetRptPeriodAsync(DateTime from, DateTime to, bool month, int locationId = 1) =>
            Database.SqlQueryRaw<RptPeriodRow>(
                "EXEC dbo.z_sp_RptPeriod @FromDate = @FromDate, @ToDate = @ToDate, @LocationId = @LocationId, @Month = @Month",
                new SqlParameter("@FromDate", SqlDbType.Date) { Value = from.Date },
                new SqlParameter("@ToDate", SqlDbType.Date) { Value = to.Date },
                new SqlParameter("@LocationId", locationId),
                new SqlParameter("@Month", month)).ToListAsync();

        public async Task<RptStockNow?> GetRptStockNowAsync(int locationId = 1) =>
            (await Database.SqlQueryRaw<RptStockNow>("EXEC dbo.z_sp_RptStockNow @LocationId = @LocationId",
                new SqlParameter("@LocationId", locationId)).ToListAsync()).FirstOrDefault();

        public Task<List<RptMoneyRow>> GetRptMoneyAsync(DateTime from, DateTime to, bool chequeByDate, int locationId = 1) =>
            Database.SqlQueryRaw<RptMoneyRow>(
                "EXEC dbo.z_sp_RptMoney @FromDate = @FromDate, @ToDate = @ToDate, @LocationId = @LocationId, @ChequeByDate = @ChequeByDate",
                new SqlParameter("@FromDate", SqlDbType.Date) { Value = from.Date },
                new SqlParameter("@ToDate", SqlDbType.Date) { Value = to.Date },
                new SqlParameter("@LocationId", locationId),
                new SqlParameter("@ChequeByDate", chequeByDate)).ToListAsync();

        public Task<List<RptStockHealthRow>> GetRptStockHealthAsync(bool inactive, int locationId = 1) =>
            Database.SqlQueryRaw<RptStockHealthRow>(
                "EXEC dbo.z_sp_RptStockHealth @LocationId = @LocationId, @Inactive = @Inactive",
                new SqlParameter("@LocationId", locationId),
                new SqlParameter("@Inactive", inactive)).ToListAsync();

        // returns how many items changed
        public async Task<int> SetItemsActiveAsync(IEnumerable<int> ids, bool active, int locationId = 1) =>
            (await Database.SqlQueryRaw<RptChanged>(
                "EXEC dbo.z_sp_RptItemSetStatus @Ids = @Ids, @Status = @Status, @LocationId = @LocationId",
                Tvp("@Ids", "dbo.z_tt_IdList", IdTable(ids)),
                new SqlParameter("@Status", active ? 1 : 0),
                new SqlParameter("@LocationId", locationId)).ToListAsync()).FirstOrDefault()?.Changed ?? 0;
    }
}
