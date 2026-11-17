using Microsoft.EntityFrameworkCore;

namespace ItemApi.Data
{
    /// <summary>
    /// Single DbContext for every entity that lives on the "DefaultConnection" database.
    /// Split into partial files under Data/AppDbContext.*.cs, one per domain area (Itemz, Stock ledger,
    /// Salary, ...), so this stays a single EF unit-of-work (one connection, shared transactions,
    /// one place to configure the model) without becoming an unreadable monolith file.
    ///
    /// Consolidated from 19 separate one-DbSet-per-table DbContext classes that all pointed at the
    /// same connection string. (The old-system endpoints on tb_Item / tb_Stock / posdb were removed.)
    /// </summary>
    public partial class AppDbContext : DbContext
    {
        public AppDbContext(DbContextOptions<AppDbContext> options) : base(options) { }

        protected override void OnModelCreating(ModelBuilder modelBuilder)
        {
            base.OnModelCreating(modelBuilder);

            ConfigureItemz(modelBuilder);
            ConfigureSupplierz(modelBuilder);
            ConfigureFileLocation(modelBuilder);
            ConfigureChequeCreate(modelBuilder);
            ConfigurePayee(modelBuilder);
            ConfigureCategory(modelBuilder);
            ConfigureLocation(modelBuilder);
            ConfigureSubCategory(modelBuilder);
            ConfigureUnit(modelBuilder);
            ConfigureTempPurchaseSummary(modelBuilder);
            ConfigureTempPurchase(modelBuilder);
            ConfigureSystem(modelBuilder);
            ConfigureSupplierLedger(modelBuilder);
            ConfigureSalary(modelBuilder);
            ConfigureStockLedger(modelBuilder);
            ConfigureStockTake(modelBuilder);
            ConfigureExport(modelBuilder);
            ConfigureSalesDoc(modelBuilder);
            ConfigureUser(modelBuilder);
            ConfigureLabel(modelBuilder);
        }

        // Implemented in the matching Data/AppDbContext.<Area>.cs file.
        partial void ConfigureItemz(ModelBuilder modelBuilder);
        partial void ConfigureSupplierz(ModelBuilder modelBuilder);
        partial void ConfigureFileLocation(ModelBuilder modelBuilder);
        partial void ConfigureChequeCreate(ModelBuilder modelBuilder);
        partial void ConfigurePayee(ModelBuilder modelBuilder);
        partial void ConfigureCategory(ModelBuilder modelBuilder);
        partial void ConfigureLocation(ModelBuilder modelBuilder);
        partial void ConfigureSubCategory(ModelBuilder modelBuilder);
        partial void ConfigureUnit(ModelBuilder modelBuilder);
        partial void ConfigureTempPurchaseSummary(ModelBuilder modelBuilder);
        partial void ConfigureTempPurchase(ModelBuilder modelBuilder);
        partial void ConfigureSystem(ModelBuilder modelBuilder);
        partial void ConfigureSupplierLedger(ModelBuilder modelBuilder);
        partial void ConfigureSalary(ModelBuilder modelBuilder);
        partial void ConfigureStockLedger(ModelBuilder modelBuilder);
        partial void ConfigureStockTake(ModelBuilder modelBuilder);
        partial void ConfigureExport(ModelBuilder modelBuilder);
        partial void ConfigureSalesDoc(ModelBuilder modelBuilder);
        partial void ConfigureUser(ModelBuilder modelBuilder);
        partial void ConfigureLabel(ModelBuilder modelBuilder);
    }
}
