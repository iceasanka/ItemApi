using Microsoft.EntityFrameworkCore;

namespace ItemApi.Data
{
    /// <summary>
    /// Single DbContext for every entity that lives on the "DefaultConnection" database.
    /// Split into partial files under Data/AppDbContext.*.cs, one per domain area (Item, Return,
    /// Salary, ...), so this stays a single EF unit-of-work (one connection, shared transactions,
    /// one place to configure the model) without becoming an unreadable monolith file.
    ///
    /// Consolidated from 19 separate one-DbSet-per-table DbContext classes that all pointed at the
    /// same connection string. See Data/PosDbContext.cs for the one entity (PosStock) that lives on
    /// the separate "PosConnection" database.
    /// </summary>
    public partial class AppDbContext : DbContext
    {
        public AppDbContext(DbContextOptions<AppDbContext> options) : base(options) { }

        protected override void OnModelCreating(ModelBuilder modelBuilder)
        {
            base.OnModelCreating(modelBuilder);

            ConfigureItem(modelBuilder);
            ConfigureItemz(modelBuilder);
            ConfigureStock(modelBuilder);
            ConfigureReturn(modelBuilder);
            ConfigureSupplier(modelBuilder);
            ConfigureSupplierz(modelBuilder);
            ConfigurePosCountedStock(modelBuilder);
            ConfigureGrnTemp(modelBuilder);
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
            ConfigureExport(modelBuilder);
            ConfigureSalesDoc(modelBuilder);
            ConfigureUser(modelBuilder);
        }

        // Implemented in the matching Data/AppDbContext.<Area>.cs file.
        partial void ConfigureItem(ModelBuilder modelBuilder);
        partial void ConfigureItemz(ModelBuilder modelBuilder);
        partial void ConfigureStock(ModelBuilder modelBuilder);
        partial void ConfigureReturn(ModelBuilder modelBuilder);
        partial void ConfigureSupplier(ModelBuilder modelBuilder);
        partial void ConfigureSupplierz(ModelBuilder modelBuilder);
        partial void ConfigurePosCountedStock(ModelBuilder modelBuilder);
        partial void ConfigureGrnTemp(ModelBuilder modelBuilder);
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
        partial void ConfigureExport(ModelBuilder modelBuilder);
        partial void ConfigureSalesDoc(ModelBuilder modelBuilder);
        partial void ConfigureUser(ModelBuilder modelBuilder);
    }
}
