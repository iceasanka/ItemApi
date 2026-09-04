using ItemApi.Data;
using ItemApi.Models;
using System.Collections.Generic;
using System.Threading.Tasks;

namespace ItemApi.Repositories
{
    public class SupplierzRepository : ISupplierzRepository
    {
        private readonly AppDbContext _context;

        public SupplierzRepository(AppDbContext context)
        {
            _context = context;
        }

        public async Task<List<SupplierEntity>> GetAllAsync()
        {
            return await _context.GetAllSuppliersAsync();
        }

        public async Task<SupplierEntity?> GetByIdAsync(int id)
        {
            return await _context.GetSupplierByIdAsync(id);
        }

        public async Task AddAsync(SupplierEntity supplier)
        {
            await _context.AddSupplierAsync(supplier);
        }

        public async Task UpdateAsync(SupplierEntity supplier)
        {
            await _context.UpdateSupplierAsync(supplier);
        }

        public async Task DeleteAsync(int id)
        {
            await _context.DeleteSupplierAsync(id);
        }

        public async Task<List<SupplierEntity>> SearchSupplierByNameAsync(string suppName)
        {
            return await _context.SearchSupplierByNameAsync(suppName);
        }
    }
}
