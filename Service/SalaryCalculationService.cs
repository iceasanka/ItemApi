using ItemApi.Interface;
using ItemApi.Models;

namespace ItemApi.Service
{
    /// <summary>
    /// Implements the payslip formula from the salary system design doc:
    /// Basic earned (prorated by days present) + OT + ByShop + Attendance bonus (if full attendance)
    /// + Mercantile-holiday pay/OT + Target bonus (if enabled) - Advance deductions = Net salary.
    ///
    /// Business-rule assumptions made explicit here (not fully specified in the design doc):
    /// - "Full attendance" = no attendance row in the month marked absent (IsPresent=false, IsMercantileHoliday=false).
    /// - Mercantile-holiday pay/OT is only paid for holiday rows where the employee actually attended (IsPresent=true).
    /// - Target bonus is a flat admin-controlled toggle/amount, not computed from actual sales targets.
    /// </summary>
    public class SalaryCalculationService : ISalaryCalculationService
    {
        private readonly ISalaryEmployeeRepository _employeeRepository;
        private readonly ISalaryAttendanceRepository _attendanceRepository;
        private readonly ISalaryAdvanceRepository _advanceRepository;
        private readonly ISalaryConfigRepository _configRepository;
        private readonly ISalaryPayslipRepository _payslipRepository;

        public SalaryCalculationService(
            ISalaryEmployeeRepository employeeRepository,
            ISalaryAttendanceRepository attendanceRepository,
            ISalaryAdvanceRepository advanceRepository,
            ISalaryConfigRepository configRepository,
            ISalaryPayslipRepository payslipRepository)
        {
            _employeeRepository = employeeRepository;
            _attendanceRepository = attendanceRepository;
            _advanceRepository = advanceRepository;
            _configRepository = configRepository;
            _payslipRepository = payslipRepository;
        }

        public async Task<List<SalaryPayslip>> CalculateAndSaveMonthAsync(int month, int year)
        {
            var config = await _configRepository.GetConfigAsync();
            var employees = await _employeeRepository.GetAllActiveAsync();
            var totalDaysInMonth = DateTime.DaysInMonth(year, month);

            var results = new List<SalaryPayslip>();

            foreach (var employee in employees)
            {
                var attendance = await _attendanceRepository.GetByEmployeeAndMonthAsync(employee.EmployeeId, month, year);
                var advances = await _advanceRepository.GetByEmployeeAndMonthAsync(employee.EmployeeId, month, year);

                var basicRate = employee.BasicOverride ?? config.BasicSalary;
                var byShop = employee.ByShopOverride ?? config.ByShop;
                var attendanceBonusRate = employee.AttendanceBonusOverride ?? config.AttendanceBonus;
                var otRate = employee.OtRateOverride ?? config.OtRate;
                var mhPay = employee.MhPayOverride ?? config.MhPay;
                var mhOtRate = employee.MhOtRateOverride ?? config.MhOtRate;
                var targetBonusAmount = employee.TargetBonusOverride ?? config.TargetBonus;
                var isTargetBonusEnabled = employee.IsTargetBonusEnabledOverride ?? config.IsTargetBonusEnabled;

                var regularDays = attendance.Where(a => !a.IsMercantileHoliday).ToList();
                var holidayDays = attendance.Where(a => a.IsMercantileHoliday).ToList();

                var absentDays = regularDays.Count(a => !a.IsPresent);
                var otHours = regularDays.Where(a => a.IsPresent).Sum(a => a.OtHours);

                var mhWorkedDays = holidayDays.Where(a => a.IsPresent).ToList();
                var mhCount = mhWorkedDays.Count;
                var mhOtHours = mhWorkedDays.Sum(a => a.OtHours);

                // Basic pay is prorated by every day actually attended, including holidays
                // worked - those also earn the separate mhAmount/mhOtAmount bonus on top.
                var daysPresent = regularDays.Count(a => a.IsPresent) + mhCount;

                var basicEarned = Math.Round(basicRate * daysPresent / totalDaysInMonth, 2);
                var otAmount = Math.Round(otHours * otRate, 2);
                var mhAmount = Math.Round(mhCount * mhPay, 2);
                var mhOtAmount = Math.Round(mhOtHours * mhOtRate, 2);
                var isFullAttendance = absentDays == 0;
                var attendanceBonus = isFullAttendance ? attendanceBonusRate : 0m;
                var targetBonus = isTargetBonusEnabled ? targetBonusAmount : 0m;
                var advanceDeduction = advances.Sum(a => a.Amount);

                var netSalary = basicEarned + otAmount + byShop + attendanceBonus
                    + mhAmount + mhOtAmount + targetBonus - advanceDeduction;

                var payslip = new SalaryPayslip
                {
                    EmployeeId = employee.EmployeeId,
                    EmployeeName = employee.EmployeeName,
                    PayMonth = month,
                    PayYear = year,
                    TotalDaysInMonth = totalDaysInMonth,
                    DaysPresent = daysPresent,
                    BasicEarned = basicEarned,
                    OtHours = otHours,
                    OtAmount = otAmount,
                    ByShop = byShop,
                    AttendanceBonus = attendanceBonus,
                    MhCount = mhCount,
                    MhAmount = mhAmount,
                    MhOtHours = mhOtHours,
                    MhOtAmount = mhOtAmount,
                    TargetBonus = targetBonus,
                    AdvanceDeduction = advanceDeduction,
                    NetSalary = Math.Round(netSalary, 2),
                    Status = "Draft"
                };

                await _payslipRepository.UpsertAsync(payslip);
                results.Add(payslip);
            }

            return results;
        }
    }
}
