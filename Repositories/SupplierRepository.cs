using ItemApi.Data;
using ItemApi.Interface;
using ItemApi.Models;
using Microsoft.EntityFrameworkCore;

namespace ItemApi.Repositories
{
    public class SupplierRepository : ISupplierRepository
    {
        private readonly SupplierContext _context;

        public SupplierRepository(SupplierContext context)
        {
            _context = context;
        }

        public async Task<IEnumerable<Supplier>> GetAllSuppliersAsync()
        {
            return await _context.Suppliers.ToListAsync();
        }

        public async Task<IEnumerable<Supplier>> SearchSuppliersAsync(string query)
        {
            return await _context.Suppliers
                .Where(s => s.Supp_Code.Contains(query) || s.Supp_Name.Contains(query))
                .ToListAsync();
        }
    }
}
