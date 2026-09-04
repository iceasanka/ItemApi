using ItemApi.Models;
using Microsoft.EntityFrameworkCore;

namespace ItemApi.Data
{
    // Temp purchase summary (z_tb_TempPurchaseSummary) — consolidated from the former
    // TempPurchaseSummaryContext. Joins against the shared SupplierEntities DbSet declared in
    // AppDbContext.Supplierz.cs (both used to declare their own DbSet<SupplierEntity> over the same
    // z_tb_Supplier table — merged into one here).
    public partial class AppDbContext
    {
        public DbSet<TempPurchaseSummary> TempPurchaseSummaries { get; set; }

        partial void ConfigureTempPurchaseSummary(ModelBuilder modelBuilder)
        {
            modelBuilder.Entity<TempPurchaseSummary>().ToTable("z_tb_TempPurchaseSummary");
        }
    }
}
