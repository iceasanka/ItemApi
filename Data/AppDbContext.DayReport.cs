using System.Data;
using ItemApi.Models;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;

namespace ItemApi.Data
{
    // Day Reports — read-only calls to the z_sp_DayReport* procs, and the till upload of cash movements
    // (DBScript/21_BackOffice_DayReports.sql, Updates/U018_BackOffice_DayReports.sql).
    public partial class AppDbContext
    {
        public Task<List<DayTill>> GetDayTillsAsync(DateTime date, int locationId, int? terminalId) =>
            DayQuery<DayTill>("z_sp_DayReportTills", date, locationId, terminalId);

        public Task<List<DayZ>> GetDayZReportsAsync(DateTime date, int locationId, int? terminalId) =>
            DayQuery<DayZ>("z_sp_DayReportZ", date, locationId, terminalId);

        public Task<List<DayCashMovement>> GetDayCashMovementsAsync(DateTime date, int locationId, int? terminalId) =>
            DayQuery<DayCashMovement>("z_sp_DayReportCash", date, locationId, terminalId);

        public Task<List<DayItem>> GetDayItemsAsync(DateTime date, int locationId, int? terminalId) =>
            DayQuery<DayItem>("z_sp_DayReportItems", date, locationId, terminalId);

        public Task<List<DayBill>> GetDayBillsAsync(DateTime date, int locationId, int? terminalId) =>
            DayQuery<DayBill>("z_sp_DayReportBills", date, locationId, terminalId);

        // null = no such bill
        public async Task<DayBillDetail?> GetDayBillAsync(string invoiceNo)
        {
            var bill = (await BillQuery<DayBillDetail>("z_sp_DayReportBill", invoiceNo)).FirstOrDefault();
            if (bill == null)
                return null;

            bill.Lines = await BillQuery<DayBillLine>("z_sp_DayReportBillLines", invoiceNo);
            bill.Payments = await BillQuery<DayBillPayment>("z_sp_DayReportBillPayments", invoiceNo);
            return bill;
        }

        public async Task<SyncCashMovementResult> SyncCashMovementsAsync(int terminalId, List<SyncCashMovement> rows)
        {
            // column order = dbo.z_tt_CashMovement
            var t = new DataTable();
            t.Columns.Add("MoveId", typeof(int));
            t.Columns.Add("ZNo", typeof(int));
            t.Columns.Add("Kind", typeof(int));
            t.Columns.Add("Amount", typeof(decimal));
            t.Columns.Add("Reason", typeof(string));
            t.Columns.Add("CashierId", typeof(string));
            t.Columns.Add("CreatedAt", typeof(DateTime));
            t.Columns.Add("Status", typeof(int));
            foreach (var m in rows.GroupBy(r => r.MoveId).Select(g => g.Last()))
                t.Rows.Add(m.MoveId, m.ZNo, m.Kind, m.Amount, (object?)m.Reason ?? DBNull.Value,
                           (object?)m.CashierId ?? DBNull.Value, m.CreatedAt, m.Status);

            var result = await Database.SqlQueryRaw<SyncCashMovementResult>(
                "EXEC dbo.z_sp_SyncCashMovements @TerminalId = @TerminalId, @Rows = @Rows",
                new SqlParameter("@TerminalId", terminalId),
                new SqlParameter("@Rows", SqlDbType.Structured) { TypeName = "dbo.z_tt_CashMovement", Value = t }).ToListAsync();
            return result.FirstOrDefault() ?? new SyncCashMovementResult();
        }

        public Task<List<DayLossCashier>> GetDayLossCashiersAsync(DateTime date, int locationId, int? terminalId) =>
            DayQuery<DayLossCashier>("z_sp_DayReportLossCashiers", date, locationId, terminalId);

        public Task<List<DayVoidLine>> GetDayVoidsAsync(DateTime date, int locationId, int? terminalId) =>
            DayQuery<DayVoidLine>("z_sp_DayReportVoids", date, locationId, terminalId);

        public Task<List<DayNoSale>> GetDayNoSalesAsync(DateTime date, int locationId, int? terminalId) =>
            DayQuery<DayNoSale>("z_sp_DayReportNoSales", date, locationId, terminalId);

        // void lines and drawer openings of a till (DBScript/22_BackOffice_VoidReport.sql)
        public async Task<SyncTillLogResult> SyncTillLogAsync(int terminalId, List<SyncVoidLog> voids, List<SyncDrawerLog> drawer)
        {
            // column order = dbo.z_tt_TillVoidLog
            var v = new DataTable();
            v.Columns.Add("VoidId", typeof(int));
            v.Columns.Add("GroupNo", typeof(int));
            v.Columns.Add("LoggedAt", typeof(DateTime));
            v.Columns.Add("Kind", typeof(int));
            v.Columns.Add("ZNo", typeof(int));
            v.Columns.Add("CashierId", typeof(string));
            v.Columns.Add("Refund", typeof(bool));
            v.Columns.Add("ItemId", typeof(int));
            v.Columns.Add("Descrip", typeof(string));
            v.Columns.Add("Qty", typeof(decimal));
            v.Columns.Add("UnitPrice", typeof(decimal));
            v.Columns.Add("Amount", typeof(decimal));
            foreach (var r in voids.GroupBy(r => r.VoidId).Select(g => g.Last()))
                v.Rows.Add(r.VoidId, r.GroupNo, r.LoggedAt, r.Kind, (object?)r.ZNo ?? DBNull.Value, (object?)r.CashierId ?? DBNull.Value,
                           r.Refund, r.ItemId, (object?)r.Descrip ?? DBNull.Value, r.Qty, r.UnitPrice, r.Amount);

            // column order = dbo.z_tt_TillDrawerLog
            var d = new DataTable();
            d.Columns.Add("DrawerLogId", typeof(int));
            d.Columns.Add("OpenedAt", typeof(DateTime));
            d.Columns.Add("Kind", typeof(int));
            d.Columns.Add("InvoiceNo", typeof(string));
            d.Columns.Add("CashierId", typeof(string));
            d.Columns.Add("Reason", typeof(string));
            d.Columns.Add("Opened", typeof(bool));
            foreach (var r in drawer.GroupBy(r => r.DrawerLogId).Select(g => g.Last()))
                d.Rows.Add(r.DrawerLogId, r.OpenedAt, r.Kind, (object?)r.InvoiceNo ?? DBNull.Value, (object?)r.CashierId ?? DBNull.Value,
                           (object?)r.Reason ?? DBNull.Value, r.Opened);

            var result = await Database.SqlQueryRaw<SyncTillLogResult>(
                "EXEC dbo.z_sp_SyncTillLog @TerminalId = @TerminalId, @Voids = @Voids, @Drawer = @Drawer",
                new SqlParameter("@TerminalId", terminalId),
                new SqlParameter("@Voids", SqlDbType.Structured) { TypeName = "dbo.z_tt_TillVoidLog", Value = v },
                new SqlParameter("@Drawer", SqlDbType.Structured) { TypeName = "dbo.z_tt_TillDrawerLog", Value = d }).ToListAsync();
            return result.FirstOrDefault() ?? new SyncTillLogResult();
        }

        public Task<List<DayAbandonedBill>> GetDayAbandonedAsync(DateTime date, int locationId, int? terminalId) =>
            DayQuery<DayAbandonedBill>("z_sp_DayReportAbandoned", date, locationId, terminalId);

        public Task<List<DayAbandonedLine>> GetDayAbandonedLinesAsync(DateTime date, int locationId, int? terminalId) =>
            DayQuery<DayAbandonedLine>("z_sp_DayReportAbandonedLines", date, locationId, terminalId);

        // bills a till found still open after a restart (DBScript/23_BackOffice_AbandonedBills.sql)
        public async Task<SyncAbandonedResult> SyncAbandonedBillsAsync(int terminalId, List<SyncAbandonedBill> bills, List<SyncAbandonedLine> lines)
        {
            // column order = dbo.z_tt_TillAbandonedBill
            var b = new DataTable();
            b.Columns.Add("AbandonId", typeof(int));
            b.Columns.Add("DraftKey", typeof(Guid));
            b.Columns.Add("ZNo", typeof(int));
            b.Columns.Add("CashierId", typeof(string));
            b.Columns.Add("InvType", typeof(int));
            b.Columns.Add("LineCount", typeof(int));
            b.Columns.Add("NetAmount", typeof(decimal));
            b.Columns.Add("StartedAt", typeof(DateTime));
            b.Columns.Add("LastSavedAt", typeof(DateTime));
            b.Columns.Add("FoundAt", typeof(DateTime));
            b.Columns.Add("FoundBy", typeof(string));
            b.Columns.Add("Outcome", typeof(int));
            b.Columns.Add("Reason", typeof(string));
            b.Columns.Add("FinalStatus", typeof(int));
            b.Columns.Add("FinalAt", typeof(DateTime));
            b.Columns.Add("InvoiceNo", typeof(string));
            b.Columns.Add("SuspendId", typeof(int));
            foreach (var r in bills.GroupBy(r => r.AbandonId).Select(g => g.Last()))
                b.Rows.Add(r.AbandonId, r.DraftKey, (object?)r.ZNo ?? DBNull.Value, (object?)r.CashierId ?? DBNull.Value, r.InvType,
                           r.LineCount, r.NetAmount, r.StartedAt, r.LastSavedAt, r.FoundAt, (object?)r.FoundBy ?? DBNull.Value,
                           r.Outcome, (object?)r.Reason ?? DBNull.Value, (object?)r.FinalStatus ?? DBNull.Value,
                           (object?)r.FinalAt ?? DBNull.Value, (object?)r.InvoiceNo ?? DBNull.Value, (object?)r.SuspendId ?? DBNull.Value);

            // column order = dbo.z_tt_TillAbandonedLine
            var l = new DataTable();
            l.Columns.Add("AbandonId", typeof(int));
            l.Columns.Add("LineNum", typeof(int));
            l.Columns.Add("ItemId", typeof(int));
            l.Columns.Add("Descrip", typeof(string));
            l.Columns.Add("Qty", typeof(decimal));
            l.Columns.Add("UnitPrice", typeof(decimal));
            l.Columns.Add("Discount", typeof(decimal));
            l.Columns.Add("Amount", typeof(decimal));
            foreach (var r in lines.GroupBy(r => (r.AbandonId, r.LineNum)).Select(g => g.Last()))
                l.Rows.Add(r.AbandonId, r.LineNum, r.ItemId, (object?)r.Descrip ?? DBNull.Value, r.Qty, r.UnitPrice, r.Discount, r.Amount);

            var result = await Database.SqlQueryRaw<SyncAbandonedResult>(
                "EXEC dbo.z_sp_SyncAbandonedBills @TerminalId = @TerminalId, @Bills = @Bills, @Lines = @Lines",
                new SqlParameter("@TerminalId", terminalId),
                new SqlParameter("@Bills", SqlDbType.Structured) { TypeName = "dbo.z_tt_TillAbandonedBill", Value = b },
                new SqlParameter("@Lines", SqlDbType.Structured) { TypeName = "dbo.z_tt_TillAbandonedLine", Value = l }).ToListAsync();
            return result.FirstOrDefault() ?? new SyncAbandonedResult();
        }

        private async Task<List<T>> DayQuery<T>(string proc, DateTime date, int locationId, int? terminalId)
        {
            return await Database.SqlQueryRaw<T>(
                $"EXEC dbo.{proc} @Date = @Date, @LocationId = @LocationId, @TerminalId = @TerminalId",
                new SqlParameter("@Date", SqlDbType.Date) { Value = date.Date },
                new SqlParameter("@LocationId", locationId),
                new SqlParameter("@TerminalId", SqlDbType.Int) { Value = (object?)terminalId ?? DBNull.Value }).ToListAsync();
        }

        private async Task<List<T>> BillQuery<T>(string proc, string invoiceNo)
        {
            return await Database.SqlQueryRaw<T>(
                $"EXEC dbo.{proc} @InvoiceNo = @InvoiceNo",
                new SqlParameter("@InvoiceNo", SqlDbType.VarChar, 30) { Value = invoiceNo }).ToListAsync();
        }
    }
}
