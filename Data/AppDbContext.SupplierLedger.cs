using ItemApi.Models;
using Microsoft.EntityFrameworkCore;
using Serilog;

namespace ItemApi.Data
{
    // Supplier ledger (z_tb_SupplierLedger) — consolidated from the former SupplierLedgerContext.
    public partial class AppDbContext
    {
        public DbSet<SupplierLedger> SupplierLedgers { get; set; }
        public DbSet<SupplierLedgerSummary> SupplierLedgerSummaries { get; set; }

        partial void ConfigureSupplierLedger(ModelBuilder modelBuilder)
        {
            modelBuilder.Entity<SupplierLedger>().ToTable("z_tb_SupplierLedger");
            modelBuilder.Entity<SupplierLedgerSummary>().HasNoKey();
        }

        // Insert a new ledger entry
        public async Task<SupplierLedger> AddLedgerAsync(SupplierLedger ledger)
        {
            try
            {
                ledger.CDate = DateTime.Now;
                ledger.UDate = DateTime.Now;
                await SupplierLedgers.AddAsync(ledger);
                await SaveChangesAsync();
                return ledger;
            }
            catch (Exception ex)
            {
                Log.Error($"Error adding ledger entry: {ex.Message}");
                throw;
            }
        }

        // Update an existing ledger entry
        public async Task<SupplierLedger> UpdateLedgerAsync(SupplierLedger ledger)
        {
            try
            {
                ledger.UDate = DateTime.Now;
                SupplierLedgers.Update(ledger);
                await SaveChangesAsync();
                return ledger;
            }
            catch (Exception ex)
            {
                Log.Error($"Error updating ledger entry: {ex.Message}");
                throw;
            }
        }

        // Delete a ledger entry by Id
        public async Task<bool> DeleteLedgerAsync(int ledgerId)
        {
            try
            {
                var entity = await SupplierLedgers.FindAsync(ledgerId);
                if (entity == null) return false;

                SupplierLedgers.Remove(entity);
                await SaveChangesAsync();
                return true;
            }
            catch (Exception ex)
            {
                Log.Error($"Error deleting ledger entry: {ex.Message}");
                throw;
            }
        }

        // Get full ledger for a supplier (with running balance via SP)
        public async Task<List<SupplierLedger>> GetLedgerBySuppIdAsync(int suppId)
        {
            try
            {
                string sql = "EXEC [dbo].[z_Sp_GetSupplierLedger] @SuppId = {0}";
                return await Database.SqlQueryRaw<SupplierLedger>(sql, suppId).ToListAsync();
            }
            catch (Exception ex)
            {
                Log.Error($"Error fetching ledger for SuppId {suppId}: {ex.Message}");
                throw;
            }
        }

        // Get ledger filtered by date range (with running balance via SP)
        public async Task<List<SupplierLedger>> GetLedgerByDateRangeAsync(int suppId, DateTime fromDate, DateTime toDate)
        {
            try
            {
                string sql = "EXEC [dbo].[z_sp_GetSupplierLedger_ByDate] @SuppId = {0}, @FromDate = {1}, @ToDate = {2}";
                return await Database.SqlQueryRaw<SupplierLedger>(sql, suppId, fromDate.Date, toDate.Date).ToListAsync();
            }
            catch (Exception ex)
            {
                Log.Error($"Error fetching ledger by date range: {ex.Message}");
                throw;
            }
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
    }
}
