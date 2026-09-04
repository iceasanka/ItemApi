using ItemApi.Models;
using Microsoft.EntityFrameworkCore;

namespace ItemApi.Data
{
    // Supplier (tb_Supplier) — consolidated from the former SupplierContext.
    // Shared by AppDbContext.Return.cs (return items join against the supplier list).
    // NOTE: not the same table/entity as SupplierEntity (z_tb_Supplier) in AppDbContext.Supplierz.cs.
    public partial class AppDbContext
    {
        public DbSet<Supplier> Suppliers { get; set; }

        partial void ConfigureSupplier(ModelBuilder modelBuilder)
        {
            modelBuilder.Entity<Supplier>().ToTable("tb_Supplier");
        }
    }
}
