using ItemApi.Data;
using ItemApi.Interface;
using ItemApi.Models;
using Microsoft.EntityFrameworkCore;

namespace ItemApi.Repositories
{
    public class SalaryPayslipRepository : ISalaryPayslipRepository
    {
        private readonly SalaryContext _context;

        public SalaryPayslipRepository(SalaryContext context)
        {
            _context = context;
        }

        public async Task<List<SalaryPayslip>> GetByMonthAsync(int month, int year)
        {
            return await _context.SalaryPayslips
                .Where(p => p.PayMonth == month && p.PayYear == year)
                .ToListAsync();
        }

        public async Task<SalaryPayslip?> GetByEmployeeAndMonthAsync(int employeeId, int month, int year)
        {
            return await _context.SalaryPayslips.FirstOrDefaultAsync(p =>
                p.EmployeeId == employeeId && p.PayMonth == month && p.PayYear == year);
        }

        // Upserts by (EmployeeId, PayMonth, PayYear) so regenerating a month replaces the previous draft.
        public async Task UpsertAsync(SalaryPayslip payslip)
        {
            var existing = await GetByEmployeeAndMonthAsync(payslip.EmployeeId, payslip.PayMonth, payslip.PayYear);

            if (existing == null)
            {
                await _context.SalaryPayslips.AddAsync(payslip);
            }
            else
            {
                existing.TotalDaysInMonth = payslip.TotalDaysInMonth;
                existing.DaysPresent = payslip.DaysPresent;
                existing.BasicEarned = payslip.BasicEarned;
                existing.OtHours = payslip.OtHours;
                existing.OtAmount = payslip.OtAmount;
                existing.ByShop = payslip.ByShop;
                existing.AttendanceBonus = payslip.AttendanceBonus;
                existing.MhCount = payslip.MhCount;
                existing.MhAmount = payslip.MhAmount;
                existing.MhOtHours = payslip.MhOtHours;
                existing.MhOtAmount = payslip.MhOtAmount;
                existing.TargetBonus = payslip.TargetBonus;
                existing.AdvanceDeduction = payslip.AdvanceDeduction;
                existing.NetSalary = payslip.NetSalary;
                existing.GeneratedDate = DateTime.Now;
            }

            await _context.SaveChangesAsync();
        }
    }
}
