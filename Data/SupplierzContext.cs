using ItemApi.Models;
using Microsoft.EntityFrameworkCore;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;

namespace ItemApi.Data
{
    public class SupplierzContext : DbContext
    {
        public SupplierzContext(DbContextOptions<SupplierzContext> options)
            : base(options)
        {
        }

        public DbSet<SupplierEntity> _suppliers { get; set; }

        protected override void OnModelCreating(ModelBuilder modelBuilder)
        {
            modelBuilder.Entity<SupplierEntity>().ToTable("z_tb_Supplier");
        }

        // Add a new supplier
        public async Task AddSupplierAsync(SupplierEntity supplier)
        {
            _suppliers.Add(supplier);
            await SaveChangesAsync();
        }

        // Update an existing supplier
        public async Task UpdateSupplierAsync(SupplierEntity supplier)
        {
            _suppliers.Update(supplier);
            await SaveChangesAsync();
        }

        // Delete a supplier by Id
        public async Task DeleteSupplierAsync(int id)
        {
            var entity = await _suppliers.FindAsync(id);
            if (entity != null)
            {
                _suppliers.Remove(entity);
                await SaveChangesAsync();
            }
        }

        // Get a supplier by Id
        public async Task<SupplierEntity> GetSupplierByIdAsync(int id)
        {
            return await _suppliers.FindAsync(id);
        }

        // Search suppliers by SuppName
        public async Task<List<SupplierEntity>> SearchSupplierByNameAsync(string suppName)
        {
            return await _suppliers
                .Where(s => s.SuppName.Contains(suppName))
                .ToListAsync();
        }

        // Get all suppliers
        public async Task<List<SupplierEntity>> GetAllSuppliersAsync()
        {
            return await _suppliers.ToListAsync();
        }
    }
}

