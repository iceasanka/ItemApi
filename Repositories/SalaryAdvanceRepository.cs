using ItemApi.Data;
using ItemApi.Interface;
using ItemApi.Models;
using Microsoft.EntityFrameworkCore;

namespace ItemApi.Repositories
{
    public class SalaryAdvanceRepository : ISalaryAdvanceRepository
    {
        private readonly AppDbContext _context;

        public SalaryAdvanceRepository(AppDbContext context)
        {
            _context = context;
        }

        public async Task<List<SalaryAdvance>> GetByEmployeeAndMonthAsync(int? employeeId, int month, int year)
        {
            var query = _context.SalaryAdvances
                .Where(a => a.AdvanceDate.Month == month && a.AdvanceDate.Year == year);

            if (employeeId.HasValue)
                query = query.Where(a => a.EmployeeId == employeeId.Value);

            return await query.OrderBy(a => a.AdvanceDate).ToListAsync();
        }

        public async Task AddAsync(SalaryAdvance advance)
        {
            await _context.SalaryAdvances.AddAsync(advance);
            await _context.SaveChangesAsync();
        }

        public async Task DeleteAsync(int advanceId)
        {
            var advance = await _context.SalaryAdvances.FindAsync(advanceId);
            if (advance == null)
                return;

            _context.SalaryAdvances.Remove(advance);
            await _context.SaveChangesAsync();
        }
    }
}
