using ItemApi.Common;
using ItemApi.Models;
using Microsoft.EntityFrameworkCore;

namespace ItemApi.Data
{
    // SupplierEntity (z_tb_Supplier) — consolidated from the former SupplierzContext.
    // Shared by AppDbContext.TempPurchaseSummary.cs (summary rows join against the supplier list).
    // NOTE: not the same table/entity as Supplier (tb_Supplier) in AppDbContext.Supplier.cs.
    public partial class AppDbContext
    {
        public DbSet<SupplierEntity> SupplierEntities { get; set; }

        partial void ConfigureSupplierz(ModelBuilder modelBuilder)
        {
            modelBuilder.Entity<SupplierEntity>().ToTable("z_tb_Supplier");
        }

        // Add a new supplier
        public async Task AddSupplierAsync(SupplierEntity supplier)
        {
            SupplierEntities.Add(supplier);
            await SaveChangesAsync();
        }

        // Update an existing supplier
        public async Task UpdateSupplierAsync(SupplierEntity supplier)
        {
            SupplierEntities.Update(supplier);
            await SaveChangesAsync();
        }

        // "Delete" a supplier by Id — soft delete: mark inactive instead of removing the row
        public async Task DeleteSupplierAsync(int id)
        {
            var entity = await SupplierEntities.FindAsync(id);
            if (entity != null)
            {
                entity.Status = (int)Meta.SupplierStatus.Inactive;
                entity.UDate = DateTime.Now;
                await SaveChangesAsync();
            }
        }

        // Get a supplier by Id
        public async Task<SupplierEntity> GetSupplierByIdAsync(int id)
        {
            return await SupplierEntities.FindAsync(id);
        }

        // Search suppliers by SuppName
        public async Task<List<SupplierEntity>> SearchSupplierByNameAsync(string suppName)
        {
            return await SupplierEntities
                .Where(s => s.SuppName.Contains(suppName))
                .ToListAsync();
        }

        // Get all suppliers
        public async Task<List<SupplierEntity>> GetAllSuppliersAsync()
        {
            return await SupplierEntities.ToListAsync();
        }
    }
}
