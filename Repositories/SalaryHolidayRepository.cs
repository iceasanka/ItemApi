using ItemApi.Data;
using ItemApi.Interface;
using ItemApi.Models;
using Microsoft.EntityFrameworkCore;

namespace ItemApi.Repositories
{
    public class SalaryHolidayRepository : ISalaryHolidayRepository
    {
        private readonly SalaryContext _context;

        public SalaryHolidayRepository(SalaryContext context)
        {
            _context = context;
        }

        public async Task<List<SalaryHoliday>> GetByMonthAsync(int month, int year)
        {
            return await _context.SalaryHolidays
                .Where(h => h.HolidayDate.Month == month && h.HolidayDate.Year == year)
                .OrderBy(h => h.HolidayDate)
                .ToListAsync();
        }

        public async Task AddAsync(SalaryHoliday holiday)
        {
            await _context.SalaryHolidays.AddAsync(holiday);
            await _context.SaveChangesAsync();
        }

        public async Task DeleteAsync(int holidayId)
        {
            var holiday = await _context.SalaryHolidays.FindAsync(holidayId);
            if (holiday == null)
                return;

            _context.SalaryHolidays.Remove(holiday);
            await _context.SaveChangesAsync();
        }
    }
}
