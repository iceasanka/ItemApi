using ItemApi.Models;

namespace ItemApi.Interface
{
    public interface ISalaryAttendanceRepository
    {
        Task<List<SalaryAttendance>> GetByMonthAsync(int month, int year);
        Task<List<SalaryAttendance>> GetByEmployeeAndMonthAsync(int employeeId, int month, int year);
        Task<SalaryAttendance?> GetByIdAsync(int attendanceId);
        Task<bool> ExistsAsync(int attendanceId);
        Task SaveBulkAsync(IEnumerable<SalaryAttendance> entries);
        Task UpdateAsync(SalaryAttendance entry);
    }
}
