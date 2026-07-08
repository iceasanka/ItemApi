using ItemApi.Data;
using ItemApi.Interface;
using ItemApi.Models;
using Microsoft.EntityFrameworkCore;

namespace ItemApi.Repositories
{
    public class SalaryEmployeeRepository : ISalaryEmployeeRepository
    {
        private readonly SalaryContext _context;

        public SalaryEmployeeRepository(SalaryContext context)
        {
            _context = context;
        }

        public async Task<List<SalaryEmployee>> GetAllActiveAsync()
        {
            return await _context.SalaryEmployees
                .Where(e => e.Status == "Active")
                .OrderBy(e => e.EmployeeName)
                .ToListAsync();
        }

        public async Task<List<SalaryEmployee>> GetAllAsync()
        {
            return await _context.SalaryEmployees
                .OrderBy(e => e.EmployeeName)
                .ToListAsync();
        }

        public async Task<SalaryEmployee?> GetByIdAsync(int employeeId)
        {
            return await _context.SalaryEmployees.FindAsync(employeeId);
        }

        public async Task<bool> ExistsAsync(int employeeId)
        {
            return await _context.SalaryEmployees
                .AsNoTracking()
                .AnyAsync(e => e.EmployeeId == employeeId);
        }

        public async Task AddAsync(SalaryEmployee employee)
        {
            await _context.SalaryEmployees.AddAsync(employee);
            await _context.SaveChangesAsync();
        }

        public async Task UpdateAsync(SalaryEmployee employee)
        {
            _context.SalaryEmployees.Update(employee);
            await _context.SaveChangesAsync();
        }

        public async Task DeactivateAsync(int employeeId)
        {
            var employee = await _context.SalaryEmployees.FindAsync(employeeId);
            if (employee == null)
                return;

            employee.Status = "Inactive";
            await _context.SaveChangesAsync();
        }
    }
}
