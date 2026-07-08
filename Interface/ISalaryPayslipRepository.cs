using ItemApi.Models;

namespace ItemApi.Interface
{
    public interface ISalaryPayslipRepository
    {
        Task<List<SalaryPayslip>> GetByMonthAsync(int month, int year);
        Task<SalaryPayslip?> GetByEmployeeAndMonthAsync(int employeeId, int month, int year);
        Task UpsertAsync(SalaryPayslip payslip);
    }
}
