using ItemApi.Data;
using ItemApi.Interface;
using ItemApi.Models;
using Microsoft.EntityFrameworkCore;

namespace ItemApi.Repositories
{
    public class PayeeRepository : IPayeeRepository
    {
        private readonly AppDbContext _context;

        public PayeeRepository(AppDbContext context)
        {
            _context = context;
        }

        public async Task<List<Payee>> GetPayeesByNameAsync(string query)
        {
            return await _context.Payees
                .Where(p => EF.Functions.Like(p.SupplierName, $"%{query}%"))
                .ToListAsync();
        }

        public async Task<IEnumerable<Payee>> GetAllPayeesAsync()
        {
            return await _context.Payees.ToListAsync();
        }

        public async Task AddPayeeAsync(Payee payee)
        {
            await _context.Payees.AddAsync(payee);
            await _context.SaveChangesAsync();
        }

        public async Task UpdatePayeeAsync(Payee payee)
        {
            _context.Payees.Update(payee);
            await _context.SaveChangesAsync();
        }

        public async Task DeletePayeeAsync(int id)
        {
            var payee = await _context.Payees.FindAsync(id);
            if (payee != null)
            {
                _context.Payees.Remove(payee);
                await _context.SaveChangesAsync();
            }
        }

        public async Task<Payee> GetById(int id)
        {
            return await _context.Payees.FindAsync(id);
        }

       
    }
}
