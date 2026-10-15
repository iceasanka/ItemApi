using System.Data;
using ItemApi.Models;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using Serilog;

namespace ItemApi.Data
{
    // Supplier ledger (z_tb_SupplierLedger) — consolidated from the former SupplierLedgerContext.
    // Bills, payments and the cheques that pay them: Docs/StockSystem.md §6.19 (U007).
    public partial class AppDbContext
    {
        public DbSet<SupplierLedger> SupplierLedgers { get; set; }
        public DbSet<SupplierLedgerSummary> SupplierLedgerSummaries { get; set; }
        public DbSet<SupplierPaymentAlloc> SupplierPaymentAllocs { get; set; }

        partial void ConfigureSupplierLedger(ModelBuilder modelBuilder)
        {
            modelBuilder.Entity<SupplierLedger>().ToTable("z_tb_SupplierLedger");
            modelBuilder.Entity<SupplierLedgerSummary>().HasNoKey();
            modelBuilder.Entity<SupplierPaymentAlloc>().ToTable("z_tb_SupplierPaymentAlloc");
        }

        // Add (LedgerId 0) or change a ledger entry. Empty ReferenceId → SUP001-00001; a bill with no DueDate is
        // due TxnDate + the supplier's CreditDays. Allocations (payment / return) replace the bills it pays when not null.
        public async Task<SupplierLedgerSaveResult> SaveLedgerAsync(SupplierLedger l)
        {
            var rows = await Database.SqlQueryRaw<SupplierLedgerSaveResult>(
                "EXEC dbo.z_sp_SaveSupplierLedger @LedgerId = @LedgerId, @SuppId = @SuppId, @TxnDate = @TxnDate, @Type = @Type, " +
                "@ReferenceId = @ReferenceId, @InvoiceNo = @InvoiceNo, @Remark = @Remark, @DebitAmount = @DebitAmount, " +
                "@CreditAmount = @CreditAmount, @DueDate = @DueDate, @UserId = @UserId, @SetAllocations = @SetAllocations, " +
                "@Allocations = @Allocations",
                new SqlParameter("@LedgerId", l.LedgerId),
                new SqlParameter("@SuppId", SqlDbType.Int) { Value = Db(l.SuppId) },
                new SqlParameter("@TxnDate", SqlDbType.Date) { Value = l.TxnDate.Date },
                new SqlParameter("@Type", l.Type),
                new SqlParameter("@ReferenceId", SqlDbType.NVarChar, 100) { Value = Db(l.ReferenceId) },
                new SqlParameter("@InvoiceNo", SqlDbType.NVarChar, 50) { Value = Db(l.InvoiceNo) },
                new SqlParameter("@Remark", SqlDbType.NVarChar, 500) { Value = Db(l.Remark) },
                Dec("@DebitAmount", l.DebitAmount),
                Dec("@CreditAmount", l.CreditAmount),
                new SqlParameter("@DueDate", SqlDbType.Date) { Value = Db(l.DueDate?.Date) },
                new SqlParameter("@UserId", SqlDbType.Int) { Value = Db(l.UserId) },
                new SqlParameter("@SetAllocations", l.Allocations != null),
                Tvp("@Allocations", "dbo.z_tt_SupplierAlloc", AllocTable(l.Allocations))).ToListAsync();
            return rows.First();
        }

        // Delete a ledger entry. A cheque payment goes with its cheque; a bill that is paid stays (z_sp_DeleteSupplierLedger).
        public async Task<bool> DeleteLedgerAsync(int ledgerId)
        {
            if (!await SupplierLedgers.AnyAsync(x => x.LedgerId == ledgerId)) return false;
            await Database.ExecuteSqlRawAsync("EXEC dbo.z_sp_DeleteSupplierLedger @LedgerId = @LedgerId",
                new SqlParameter("@LedgerId", ledgerId));
            return true;
        }

        // A supplier's ledger with the running balance. With a date range the balance still counts what came before.
        public async Task<List<SupplierLedgerRow>> GetLedgerRowsAsync(int suppId, DateTime? fromDate = null, DateTime? toDate = null)
        {
            try
            {
                return await Database.SqlQueryRaw<SupplierLedgerRow>(
                    "EXEC dbo.z_Sp_GetSupplierLedger @SuppId = @SuppId, @FromDate = @FromDate, @ToDate = @ToDate",
                    new SqlParameter("@SuppId", suppId),
                    new SqlParameter("@FromDate", SqlDbType.Date) { Value = Db(fromDate?.Date) },
                    new SqlParameter("@ToDate", SqlDbType.Date) { Value = Db(toDate?.Date) }).ToListAsync();
            }
            catch (Exception ex)
            {
                Log.Error($"Error fetching ledger for SuppId {suppId}: {ex.Message}");
                throw;
            }
        }

        // A supplier's bills (open ones first, oldest due first) with the cheques / payments that paid them
        public async Task<List<SupplierInvoiceRow>> GetSupplierInvoicesAsync(int suppId, bool includePaid)
        {
            return await Database.SqlQueryRaw<SupplierInvoiceRow>(
                "EXEC dbo.z_sp_GetSupplierInvoices @SuppId = @SuppId, @IncludePaid = @IncludePaid",
                new SqlParameter("@SuppId", suppId),
                new SqlParameter("@IncludePaid", includePaid)).ToListAsync();
        }

        // Open bills due on or before toDate (null = today + 30), overdue ones too
        public async Task<List<SupplierPaymentDueRow>> GetSupplierPaymentsDueAsync(DateTime? toDate, int? suppId)
        {
            return await Database.SqlQueryRaw<SupplierPaymentDueRow>(
                "EXEC dbo.z_sp_GetSupplierPaymentsDue @ToDate = @ToDate, @SuppId = @SuppId",
                new SqlParameter("@ToDate", SqlDbType.Date) { Value = Db(toDate?.Date) },
                new SqlParameter("@SuppId", SqlDbType.Int) { Value = Db(suppId is > 0 ? suppId : null) }).ToListAsync();
        }

        // A cheque just written for a supplier → ONE payment row in the ledger, paying the given bills.
        // Run inside the transaction that inserted the cheque.
        public async Task<SupplierLedgerSaveResult> LinkWrittenChequeAsync(int chequeId, int suppId, int? userId, List<SupplierAllocation>? allocations)
        {
            var rows = await Database.SqlQueryRaw<SupplierLedgerSaveResult>(
                "EXEC dbo.z_sp_LinkWrittenCheque @ChequeId = @ChequeId, @SuppId = @SuppId, @UserId = @UserId, @Allocations = @Allocations",
                new SqlParameter("@ChequeId", chequeId),
                new SqlParameter("@SuppId", suppId),
                new SqlParameter("@UserId", SqlDbType.Int) { Value = Db(userId) },
                Tvp("@Allocations", "dbo.z_tt_SupplierAlloc", AllocTable(allocations))).ToListAsync();
            return rows.First();
        }

        // Before a cheque is deleted: its payment row and what it paid go (the bills are open again)
        public async Task UnlinkWrittenChequeAsync(int chequeId)
        {
            await Database.ExecuteSqlRawAsync("EXEC dbo.z_sp_UnlinkWrittenCheque @ChequeId = @ChequeId",
                new SqlParameter("@ChequeId", chequeId));
        }

        // Get supplier summary (total purchase, paid, balance)
        public async Task<SupplierLedgerSummary?> GetSupplierSummaryAsync(int suppId)
        {
            try
            {
                string sql = "EXEC [dbo].[z_sp_GetSupplierSummary] @SuppId = {0}";
                var result = await Database
            .SqlQueryRaw<SupplierLedgerSummary>(sql, suppId)
            .ToListAsync();

                return result.FirstOrDefault();
            }
            catch (Exception ex)
            {
                Log.Error($"Error fetching supplier summary for SuppId {suppId}: {ex.Message}");
                throw;
            }
        }

        // column order = dbo.z_tt_SupplierAlloc
        private static DataTable AllocTable(IEnumerable<SupplierAllocation>? allocations)
        {
            var t = new DataTable();
            t.Columns.Add("LedgerId", typeof(int));
            t.Columns.Add("Amount", typeof(decimal));
            t.Columns.Add("Deduction", typeof(decimal));
            foreach (var a in allocations ?? Enumerable.Empty<SupplierAllocation>())
                t.Rows.Add(a.LedgerId, a.Amount, a.Deduction);
            return t;
        }
    }
}
