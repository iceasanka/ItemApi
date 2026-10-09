using ItemApi.Data;
using ItemApi.Interface;
using ItemApi.Models;
using Microsoft.EntityFrameworkCore;

namespace ItemApi.Repositories
{
    // Simple customer list for quotations and invoices (z_tb_Customer). Delete = Status 0, so old documents keep
    // their customer link; documents also carry their own copy of the name / address / phone.
    public class CustomerRepository : ICustomerRepository
    {
        private readonly AppDbContext _context;

        public CustomerRepository(AppDbContext context)
        {
            _context = context;
        }

        public async Task<List<Customer>> SearchAsync(string? text, int top)
        {
            var q = _context.Customers.AsNoTracking().Where(c => c.Status == 1);
            var t = (text ?? "").Trim();
            if (t.Length > 0)
                q = q.Where(c => c.Name.Contains(t) || (c.Phone != null && c.Phone.Contains(t)));
            return await q.OrderBy(c => c.Name).Take(top).ToListAsync();
        }

        public async Task<Customer?> GetByIdAsync(int customerId)
        {
            return await _context.Customers.AsNoTracking()
                .FirstOrDefaultAsync(c => c.CustomerId == customerId && c.Status == 1);
        }

        public async Task<Customer> AddAsync(Customer customer)
        {
            Clean(customer);
            await CheckAsync(customer, 0);
            customer.CustomerId = 0;
            customer.Status = 1;
            customer.CDate = customer.UDate = DateTime.Now;
            _context.Customers.Add(customer);
            await _context.SaveChangesAsync();
            return customer;
        }

        public async Task<Customer> UpdateAsync(int customerId, Customer customer)
        {
            var row = await _context.Customers.FirstOrDefaultAsync(c => c.CustomerId == customerId && c.Status == 1)
                      ?? throw new KeyNotFoundException();
            Clean(customer);
            await CheckAsync(customer, customerId);
            row.Name = customer.Name;
            row.Address = customer.Address;
            row.Phone = customer.Phone;
            row.Email = customer.Email;
            row.UserId = customer.UserId;
            row.UDate = DateTime.Now;
            await _context.SaveChangesAsync();
            return row;
        }

        public async Task DeleteAsync(int customerId, int? userId)
        {
            var row = await _context.Customers.FirstOrDefaultAsync(c => c.CustomerId == customerId && c.Status == 1)
                      ?? throw new KeyNotFoundException();
            row.Status = 0;
            row.UserId = userId;
            row.UDate = DateTime.Now;
            await _context.SaveChangesAsync();
        }

        private static void Clean(Customer c)
        {
            c.Name = (c.Name ?? "").Trim();
            c.Address = Blank(c.Address);
            c.Phone = Blank(c.Phone);
            c.Email = Blank(c.Email);
        }

        private async Task CheckAsync(Customer c, int customerId)
        {
            if (c.Name.Length == 0) throw new SalesDocException("Customer name is required.");
            if (c.Name.Length > 100) throw new SalesDocException("Customer name: max 100 characters.");
            if (c.Address?.Length > 200) throw new SalesDocException("Address: max 200 characters.");
            if (c.Phone?.Length > 20) throw new SalesDocException("Phone: max 20 characters.");
            if (c.Email?.Length > 100) throw new SalesDocException("Email: max 100 characters.");
            if (c.Email != null && !c.Email.Contains('@')) throw new SalesDocException("Email is not valid.");
            if (await _context.Customers.AnyAsync(x => x.Status == 1 && x.CustomerId != customerId && x.Name == c.Name))
                throw new SalesDocException($"A customer named '{c.Name}' already exists.");
        }

        private static string? Blank(string? s) => string.IsNullOrWhiteSpace(s) ? null : s.Trim();
    }
}
