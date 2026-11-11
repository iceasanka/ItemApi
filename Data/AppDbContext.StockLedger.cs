using System.Data;
using ItemApi.Models;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;

namespace ItemApi.Data
{
    // Stock ledger, adjustments, cashier sync and Z reports — tables and procs from
    // DBScript/01_BackOffice_Stock.sql. See Docs/StockSystem.md.
    //
    // All WRITES go through the z_sp_* procs (they keep z_tb_StockLedger and z_tb_StockBalance in step
    // in one transaction). The DbSets below are for reading only — never Add/Update them from EF.
    // Business errors from the procs are THROW 50001..50099 → SqlException.Number >= 50000.
    public partial class AppDbContext
    {
        public DbSet<StockLedger> StockLedgers { get; set; }
        public DbSet<StockBalance> StockBalances { get; set; }
        public DbSet<StockBatch> StockBatches { get; set; }
        public DbSet<StockAdjustment> StockAdjustments { get; set; }
        public DbSet<StockAdjustmentItem> StockAdjustmentItems { get; set; }
        public DbSet<StockAdjReason> StockAdjReasons { get; set; }
        public DbSet<Terminal> Terminals { get; set; }
        public DbSet<ZReport> ZReports { get; set; }
        public DbSet<ZReportItem> ZReportItems { get; set; }

        partial void ConfigureStockLedger(ModelBuilder modelBuilder)
        {
            modelBuilder.Entity<StockBalance>().HasKey(x => new { x.LocationId, x.ItemId });
            modelBuilder.Entity<StockAdjustmentItem>().HasKey(x => new { x.AdjId, x.LineNum });
            modelBuilder.Entity<ZReportItem>().HasKey(x => new { x.ZId, x.ItemId });
        }

        // ─── Posting ─────────────────────────────────────────────────────────────

        // GRN (type 1, +qty) or PRN (type 2, -qty) → stock. Returns the number of lines posted.
        public async Task<int> PostPurchaseDocAsync(string docNo, int type, string? userId)
        {
            var posted = new SqlParameter("@PostedLines", SqlDbType.Int) { Direction = ParameterDirection.Output };

            await Database.ExecuteSqlRawAsync(
                "EXEC dbo.z_sp_PostPurchaseDoc @DocNo = @DocNo, @Type = @Type, @UserId = @UserId, @PostedLines = @PostedLines OUTPUT",
                new SqlParameter("@DocNo", docNo),
                new SqlParameter("@Type", type),
                new SqlParameter("@UserId", (object?)userId ?? DBNull.Value),
                posted);

            return posted.Value is int n ? n : 0;
        }

        // Saves and posts an adjustment. Returns the new AdjNo (ADJ00000001).
        public async Task<string> SaveStockAdjustmentAsync(int locationId, StockAdjustmentRequest request)
        {
            // column order = dbo.z_tt_AdjustmentItem
            var lines = new DataTable();
            lines.Columns.Add("LineNum", typeof(int));
            lines.Columns.Add("ItemId", typeof(int));
            lines.Columns.Add("CountedQty", typeof(decimal));
            lines.Columns.Add("AdjQty", typeof(decimal));
            lines.Columns.Add("ReasonId", typeof(int));
            lines.Columns.Add("Remark", typeof(string));

            int lineNum = 1;
            foreach (var l in request.Lines)
                lines.Rows.Add(lineNum++, l.ItemId, Db(l.CountedQty), Db(l.AdjQty), Db(l.ReasonId), Db(l.Remark));

            var adjNo = new SqlParameter("@AdjNo", SqlDbType.VarChar, 20) { Direction = ParameterDirection.Output };

            await Database.ExecuteSqlRawAsync(
                "EXEC dbo.z_sp_SaveStockAdjustment @LocationId = @LocationId, @AdjDate = @AdjDate, @ReasonId = @ReasonId, " +
                "@Remark = @Remark, @UserId = @UserId, @Items = @Items, @AdjNo = @AdjNo OUTPUT",
                new SqlParameter("@LocationId", locationId),
                new SqlParameter("@AdjDate", SqlDbType.DateTime) { Value = Db(request.AdjDate) },
                new SqlParameter("@ReasonId", SqlDbType.Int) { Value = Db(request.ReasonId) },
                new SqlParameter("@Remark", SqlDbType.VarChar, 200) { Value = Db(request.Remark) },
                new SqlParameter("@UserId", SqlDbType.VarChar, 20) { Value = Db(request.UserId) },
                Tvp("@Items", "dbo.z_tt_AdjustmentItem", lines),
                adjNo);

            return (string)adjNo.Value;
        }

        // ─── Cashier sync ────────────────────────────────────────────────────────

        public async Task<DateTime> GetServerTimeAsync()
        {
            return (await Database.SqlQueryRaw<DateTime>("SELECT GETDATE() AS Value").ToListAsync()).First();
        }

        public async Task<List<SyncItem>> GetItemsForSyncAsync(int terminalId, DateTime? since)
        {
            return await Database.SqlQueryRaw<SyncItem>(
                "EXEC dbo.z_sp_GetItemsForSync @TerminalId = @TerminalId, @Since = @Since",
                new SqlParameter("@TerminalId", terminalId),
                new SqlParameter("@Since", SqlDbType.DateTime) { Value = Db(since) }).ToListAsync();
        }

        // proc lives in DBScript/03_BackOffice_PriceLink.sql
        public async Task<List<SyncPriceLink>> GetPriceLinksForSyncAsync(int terminalId, DateTime? since)
        {
            return await Database.SqlQueryRaw<SyncPriceLink>(
                "EXEC dbo.z_sp_GetPriceLinksForSync @TerminalId = @TerminalId, @Since = @Since",
                new SqlParameter("@TerminalId", terminalId),
                new SqlParameter("@Since", SqlDbType.DateTime) { Value = Db(since) }).ToListAsync();
        }

        public async Task<List<SyncStockBalance>> GetStockBalanceForSyncAsync(int terminalId, DateTime? since)
        {
            return await Database.SqlQueryRaw<SyncStockBalance>(
                "EXEC dbo.z_sp_GetStockBalanceForSync @TerminalId = @TerminalId, @Since = @Since",
                new SqlParameter("@TerminalId", terminalId),
                new SqlParameter("@Since", SqlDbType.DateTime) { Value = Db(since) }).ToListAsync();
        }

        public async Task<List<SyncInvoiceResult>> SyncSalesInvoicesAsync(int terminalId, List<SyncInvoice> invoices)
        {
            // column order = dbo.z_tt_SalesInvoice / z_tt_SalesInvoiceItem / z_tt_SalesPayment
            var inv = new DataTable();
            inv.Columns.Add("InvoiceNo", typeof(string));
            inv.Columns.Add("InvoiceSeq", typeof(int));
            inv.Columns.Add("ZNo", typeof(int));
            inv.Columns.Add("InvType", typeof(int));
            inv.Columns.Add("InvDate", typeof(DateTime));
            inv.Columns.Add("CashierId", typeof(string));
            inv.Columns.Add("GrossAmount", typeof(decimal));
            inv.Columns.Add("Discount", typeof(decimal));
            inv.Columns.Add("NetAmount", typeof(decimal));
            inv.Columns.Add("Status", typeof(int));
            inv.Columns.Add("PriceType", typeof(int));

            var items = new DataTable();
            items.Columns.Add("InvoiceNo", typeof(string));
            items.Columns.Add("LineNum", typeof(int));
            items.Columns.Add("ItemId", typeof(int));
            items.Columns.Add("Qty", typeof(decimal));
            items.Columns.Add("UnitPrice", typeof(decimal));
            items.Columns.Add("Discount", typeof(decimal));
            items.Columns.Add("Amount", typeof(decimal));
            items.Columns.Add("LineDescrip", typeof(string));
            items.Columns.Add("PriceType", typeof(int));
            items.Columns.Add("UnitCost", typeof(decimal));

            var pays = new DataTable();
            pays.Columns.Add("InvoiceNo", typeof(string));
            pays.Columns.Add("LineNum", typeof(int));
            pays.Columns.Add("PayType", typeof(int));
            pays.Columns.Add("Amount", typeof(decimal));
            pays.Columns.Add("RefNo", typeof(string));

            foreach (var i in invoices)
            {
                inv.Rows.Add(i.InvoiceNo, i.InvoiceSeq, i.ZNo, i.InvType, i.InvDate, Db(i.CashierId),
                             i.GrossAmount, i.Discount, i.NetAmount, i.Status, i.PriceType);
                foreach (var it in i.Items)
                    items.Rows.Add(i.InvoiceNo, it.LineNum, it.ItemId, it.Qty, it.UnitPrice, it.Discount, it.Amount, Db(it.LineDescrip), Db(it.PriceType), Db(it.UnitCost));
                foreach (var p in i.Payments)
                    pays.Rows.Add(i.InvoiceNo, p.LineNum, p.PayType, p.Amount, Db(p.RefNo));
            }

            return await Database.SqlQueryRaw<SyncInvoiceResult>(
                "EXEC dbo.z_sp_SyncSalesInvoices @TerminalId = @TerminalId, @Invoices = @Invoices, @Items = @Items, @Payments = @Payments",
                new SqlParameter("@TerminalId", terminalId),
                Tvp("@Invoices", "dbo.z_tt_SalesInvoice", inv),
                Tvp("@Items", "dbo.z_tt_SalesInvoiceItem", items),
                Tvp("@Payments", "dbo.z_tt_SalesPayment", pays)).ToListAsync();
        }

        public async Task<ZReportResult?> SubmitZReportAsync(ZReportSubmit z)
        {
            // column order = dbo.z_tt_ZReportItem
            var items = new DataTable();
            items.Columns.Add("ItemId", typeof(int));
            items.Columns.Add("Qty", typeof(decimal));
            items.Columns.Add("Amount", typeof(decimal));
            foreach (var i in z.Items)
                items.Rows.Add(i.ItemId, i.Qty, i.Amount);

            var rows = await Database.SqlQueryRaw<ZReportResult>(
                "EXEC dbo.z_sp_SubmitZReport @TerminalId = @TerminalId, @ZNo = @ZNo, @BusinessDate = @BusinessDate, " +
                "@CashierId = @CashierId, @OpenedAt = @OpenedAt, @ClosedAt = @ClosedAt, @FromSeq = @FromSeq, @ToSeq = @ToSeq, " +
                "@InvoiceCount = @InvoiceCount, @LineCount = @LineCount, @TotalQty = @TotalQty, @SalesAmount = @SalesAmount, " +
                "@RefundAmount = @RefundAmount, @NetSales = @NetSales, @CashAmount = @CashAmount, @CardAmount = @CardAmount, " +
                "@OtherAmount = @OtherAmount, @BankAmount = @BankAmount, @ChequeAmount = @ChequeAmount, @Items = @Items, " +
                "@CardSettlement = @CardSettlement",
                new SqlParameter("@TerminalId", z.TerminalId),
                new SqlParameter("@ZNo", z.ZNo),
                new SqlParameter("@BusinessDate", SqlDbType.Date) { Value = z.BusinessDate.Date },
                new SqlParameter("@CashierId", SqlDbType.VarChar, 20) { Value = Db(z.CashierId) },
                new SqlParameter("@OpenedAt", SqlDbType.DateTime) { Value = Db(z.OpenedAt) },
                new SqlParameter("@ClosedAt", SqlDbType.DateTime) { Value = Db(z.ClosedAt) },
                new SqlParameter("@FromSeq", SqlDbType.Int) { Value = Db(z.FromSeq) },
                new SqlParameter("@ToSeq", SqlDbType.Int) { Value = Db(z.ToSeq) },
                new SqlParameter("@InvoiceCount", z.InvoiceCount),
                new SqlParameter("@LineCount", z.LineCount),
                Dec("@TotalQty", z.TotalQty, 3),
                Dec("@SalesAmount", z.SalesAmount),
                Dec("@RefundAmount", z.RefundAmount),
                Dec("@NetSales", z.NetSales),
                Dec("@CashAmount", z.CashAmount),
                Dec("@CardAmount", z.CardAmount),
                Dec("@OtherAmount", z.OtherAmount),
                new SqlParameter("@BankAmount", SqlDbType.Decimal) { Precision = 18, Scale = 2, Value = Db(z.BankAmount) },
                new SqlParameter("@ChequeAmount", SqlDbType.Decimal) { Precision = 18, Scale = 2, Value = Db(z.ChequeAmount) },
                Tvp("@Items", "dbo.z_tt_ZReportItem", items),
                new SqlParameter("@CardSettlement", SqlDbType.Decimal) { Precision = 18, Scale = 2, Value = Db(z.CardSettlement) }).ToListAsync();

            // counted cash (U054): stored on the Z the proc just saved; a db without the column skips it
            if (z.CountedCash != null)
                await Database.ExecuteSqlRawAsync(
                    "IF COL_LENGTH('dbo.z_tb_ZReport', 'CountedCash') IS NOT NULL " +
                    "EXEC sp_executesql N'UPDATE dbo.z_tb_ZReport SET CountedCash = @C WHERE TerminalId = @T AND ZNo = @Z', " +
                    "N'@C DECIMAL(18,2), @T INT, @Z INT', @C = @C, @T = @T, @Z = @Z",
                    new SqlParameter("@C", SqlDbType.Decimal) { Precision = 18, Scale = 2, Value = z.CountedCash.Value },
                    new SqlParameter("@T", z.TerminalId),
                    new SqlParameter("@Z", z.ZNo));

            // Cash Management slip scanned at day end (U055): linked to this Z (a problem is only logged)
            if (z.SettlementId is int settlementId && rows.Count > 0)
                await LinkCashSettlementAsync(settlementId, z.TerminalId, z.ZNo);

            return rows.FirstOrDefault();
        }

        // The cheque sheet's day: cash to bank and card sales of every Z of the day (U054). Per Z, the first there is:
        //   1. the Cash Management slip linked to the Z (U055): its cash to bank - the cash that really goes to the bank;
        //   2. counted cash - opening cash when the cashier counted;
        //   3. cash sales + paid in - paid out (what should be in the drawer without the opening cash).
        // ZCount 0 = no Z that day. SlipZCount = Z's with a slip.
        public async Task<DayTakings> GetDayTakingsAsync(DateTime day, int locationId)
        {
            var has = (await Database.SqlQueryRaw<int>(
                "SELECT CASE WHEN COL_LENGTH('dbo.z_tb_ZReport', 'CountedCash') IS NULL THEN 0 ELSE 1 END + " +
                "       CASE WHEN OBJECT_ID('dbo.z_tb_CashSettlement', 'U') IS NULL THEN 0 ELSE 2 END AS Value").ToListAsync())[0];
            string counted = (has & 1) != 0 ? "z.CountedCash" : "CAST(NULL AS DECIMAL(18,2))";
            string slip = (has & 2) != 0
                ? "(SELECT TOP 1 s.BankCash FROM dbo.z_tb_CashSettlement s WHERE s.TerminalId = z.TerminalId AND s.ZNo = z.ZNo AND s.Status = 1)"
                : "CAST(NULL AS DECIMAL(18,2))";
            var rows = await Database.SqlQueryRaw<DayTakings>(
                "SELECT COUNT(*) AS ZCount, " +
                "  ISNULL(SUM(CASE WHEN x.SlipBank IS NOT NULL THEN x.SlipBank " +
                "                  WHEN x.Counted IS NOT NULL THEN x.Counted - ISNULL(x.Opening, 0) " +
                "                  ELSE x.CashAmount + ISNULL(x.PaidIn, 0) - ISNULL(x.PaidOut, 0) END), 0) AS BankCash, " +
                "  SUM(CASE WHEN x.SlipBank IS NULL AND x.Counted IS NOT NULL THEN 1 ELSE 0 END) AS CountedZCount, " +
                "  SUM(CASE WHEN x.SlipBank IS NOT NULL THEN 1 ELSE 0 END) AS SlipZCount, " +
                "  ISNULL(SUM(x.CardAmount), 0) AS Card " +
                $"FROM (SELECT z.CashAmount, z.CardAmount, {counted} AS Counted, {slip} AS SlipBank, " +
                "             m.Opening, m.PaidIn, m.PaidOut " +
                "FROM dbo.z_tb_ZReport z " +
                "LEFT JOIN (SELECT TerminalId, ZNo, " +
                "                  SUM(CASE WHEN Kind = 1 THEN Amount ELSE 0 END) AS Opening, " +
                "                  SUM(CASE WHEN Kind = 2 THEN Amount ELSE 0 END) AS PaidIn, " +
                "                  SUM(CASE WHEN Kind = 3 THEN Amount ELSE 0 END) AS PaidOut " +
                "           FROM dbo.z_tb_CashMovement WHERE Status = 1 GROUP BY TerminalId, ZNo) m " +
                "       ON m.TerminalId = z.TerminalId AND m.ZNo = z.ZNo " +
                "WHERE z.LocationId = @LocationId AND z.BusinessDate = @Day) x",
                new SqlParameter("@LocationId", locationId),
                new SqlParameter("@Day", SqlDbType.Date) { Value = day.Date }).ToListAsync();
            return rows.FirstOrDefault() ?? new DayTakings();
        }

        public async Task<ZReportResult?> ReconcileZReportAsync(int terminalId, int zNo)
        {
            var rows = await Database.SqlQueryRaw<ZReportResult>(
                "EXEC dbo.z_sp_ReconcileZReport @TerminalId = @TerminalId, @ZNo = @ZNo",
                new SqlParameter("@TerminalId", terminalId),
                new SqlParameter("@ZNo", zNo)).ToListAsync();

            return rows.FirstOrDefault();
        }

        public async Task<List<ZMissingInvoice>> GetZMissingInvoicesAsync(int terminalId, int zNo)
        {
            return await Database.SqlQueryRaw<ZMissingInvoice>(
                "EXEC dbo.z_sp_GetZMissingInvoices @TerminalId = @TerminalId, @ZNo = @ZNo",
                new SqlParameter("@TerminalId", terminalId),
                new SqlParameter("@ZNo", zNo)).ToListAsync();
        }

        // ─── helpers ─────────────────────────────────────────────────────────────

        private static object Db(object? value) => value ?? DBNull.Value;

        private static SqlParameter Tvp(string name, string typeName, DataTable table) =>
            new SqlParameter(name, SqlDbType.Structured) { TypeName = typeName, Value = table };

        private static SqlParameter Dec(string name, decimal value, byte scale = 2) =>
            new SqlParameter(name, SqlDbType.Decimal) { Precision = 18, Scale = scale, Value = value };
    }
}
