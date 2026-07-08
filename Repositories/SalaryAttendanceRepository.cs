using ItemApi.Data;
using ItemApi.Interface;
using ItemApi.Models;
using Microsoft.EntityFrameworkCore;

namespace ItemApi.Repositories
{
    public class SalaryAttendanceRepository : ISalaryAttendanceRepository
    {
        private readonly SalaryContext _context;

        public SalaryAttendanceRepository(SalaryContext context)
        {
            _context = context;
        }

        public async Task<List<SalaryAttendance>> GetByMonthAsync(int month, int year)
        {
            return await _context.SalaryAttendances
                .Where(a => a.AttendanceDate.Month == month && a.AttendanceDate.Year == year)
                .OrderBy(a => a.EmployeeId).ThenBy(a => a.AttendanceDate)
                .ToListAsync();
        }

        public async Task<List<SalaryAttendance>> GetByEmployeeAndMonthAsync(int employeeId, int month, int year)
        {
            return await _context.SalaryAttendances
                .Where(a => a.EmployeeId == employeeId
                         && a.AttendanceDate.Month == month
                         && a.AttendanceDate.Year == year)
                .OrderBy(a => a.AttendanceDate)
                .ToListAsync();
        }

        public async Task<SalaryAttendance?> GetByIdAsync(int attendanceId)
        {
            return await _context.SalaryAttendances.FindAsync(attendanceId);
        }

        public async Task<bool> ExistsAsync(int attendanceId)
        {
            return await _context.SalaryAttendances
                .AsNoTracking()
                .AnyAsync(a => a.AttendanceId == attendanceId);
        }

        // Upserts each entry by (EmployeeId, AttendanceDate) so re-marking a day updates it instead of duplicating.
        public async Task SaveBulkAsync(IEnumerable<SalaryAttendance> entries)
        {
            foreach (var entry in entries)
            {
                var existing = await _context.SalaryAttendances.FirstOrDefaultAsync(a =>
                    a.EmployeeId == entry.EmployeeId && a.AttendanceDate.Date == entry.AttendanceDate.Date);

                if (existing == null)
                {
                    await _context.SalaryAttendances.AddAsync(entry);
                }
                else
                {
                    existing.IsPresent = entry.IsPresent;
                    existing.OtHours = entry.OtHours;
                    existing.IsMercantileHoliday = entry.IsMercantileHoliday;
                }
            }

            await _context.SaveChangesAsync();
        }

        public async Task UpdateAsync(SalaryAttendance entry)
        {
            _context.SalaryAttendances.Update(entry);
            await _context.SaveChangesAsync();
        }
    }
}
