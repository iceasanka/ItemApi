using System.Data;
using ItemApi.Models;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;

namespace ItemApi.Data
{
    // Supplier bills paid in cash from a till (DBScript/26_BackOffice_TillPayments.sql, Updates/U032).
    public partial class AppDbContext
    {
        public async Task<int> AddTillPayRequestAsync(TillPayRequestCreate r, int? userId)
        {
            // column order = dbo.z_tt_TillPayLine
            var t = new DataTable();
            t.Columns.Add("LedgerId", typeof(int));
            t.Columns.Add("Amount", typeof(decimal));
            foreach (var l in r.Lines.GroupBy(x => x.LedgerId).Select(g => g.Last()))
                t.Rows.Add(l.LedgerId, l.Amount);

            var rows = await Database.SqlQueryRaw<TillPayRequestId>(
                "EXEC dbo.z_sp_TillPayRequestAdd @SuppId = @SuppId, @TerminalId = @TerminalId, @Amount = @Amount, @Remark = @Remark, @Lines = @Lines, @UserId = @UserId",
                new SqlParameter("@SuppId", r.SuppId),
                new SqlParameter("@TerminalId", SqlDbType.Int) { Value = (object?)r.TerminalId ?? DBNull.Value },
                new SqlParameter("@Amount", SqlDbType.Decimal) { Precision = 18, Scale = 2, Value = r.Amount },
                new SqlParameter("@Remark", SqlDbType.NVarChar, 100) { Value = (object?)r.Remark?.Trim() ?? DBNull.Value },
                new SqlParameter("@Lines", SqlDbType.Structured) { TypeName = "dbo.z_tt_TillPayLine", Value = t },
                new SqlParameter("@UserId", SqlDbType.Int) { Value = (object?)userId ?? DBNull.Value }).ToListAsync();
            return rows.First().RequestId;
        }

        public Task<int> CancelTillPayRequestAsync(int requestId, int? userId) =>
            Database.ExecuteSqlRawAsync("EXEC dbo.z_sp_TillPayRequestCancel @RequestId = @RequestId, @UserId = @UserId",
                new SqlParameter("@RequestId", requestId),
                new SqlParameter("@UserId", SqlDbType.Int) { Value = (object?)userId ?? DBNull.Value });

        public Task<List<TillPayRequestRow>> GetTillPayRequestsAsync(int? suppId, int? status) =>
            Database.SqlQueryRaw<TillPayRequestRow>("EXEC dbo.z_sp_GetTillPayRequests @SuppId = @SuppId, @Status = @Status",
                new SqlParameter("@SuppId", SqlDbType.Int) { Value = (object?)suppId ?? DBNull.Value },
                new SqlParameter("@Status", SqlDbType.Int) { Value = (object?)status ?? DBNull.Value }).ToListAsync();

        public Task<List<SyncTillPayRequest>> GetTillPayRequestsForSyncAsync(int terminalId) =>
            Database.SqlQueryRaw<SyncTillPayRequest>("EXEC dbo.z_sp_GetTillPayRequestsForSync @TerminalId = @TerminalId",
                new SqlParameter("@TerminalId", terminalId)).ToListAsync();

        public async Task<int> TillPayRequestsPaidAsync(int terminalId, List<SyncTillPayPaid> rows)
        {
            // column order = dbo.z_tt_TillPayPaid
            var t = new DataTable();
            t.Columns.Add("MoveId", typeof(int));
            t.Columns.Add("RequestId", typeof(int));
            t.Columns.Add("ZNo", typeof(int));
            t.Columns.Add("Amount", typeof(decimal));
            t.Columns.Add("CashierId", typeof(string));
            t.Columns.Add("PaidAt", typeof(DateTime));
            foreach (var r in rows.GroupBy(x => x.MoveId).Select(g => g.Last()))
                t.Rows.Add(r.MoveId, r.RequestId, (object?)r.ZNo ?? DBNull.Value, r.Amount, (object?)r.CashierId ?? DBNull.Value, r.PaidAt);

            var result = await Database.SqlQueryRaw<SyncTillPayPaidResult>(
                "EXEC dbo.z_sp_TillPayRequestsPaid @TerminalId = @TerminalId, @Rows = @Rows",
                new SqlParameter("@TerminalId", terminalId),
                new SqlParameter("@Rows", SqlDbType.Structured) { TypeName = "dbo.z_tt_TillPayPaid", Value = t }).ToListAsync();
            return result.FirstOrDefault()?.Received ?? 0;
        }
    }
}
