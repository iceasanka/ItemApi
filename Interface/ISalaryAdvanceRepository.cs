using ItemApi.Models;

namespace ItemApi.Interface
{
    public interface ISalaryAdvanceRepository
    {
        Task<List<SalaryAdvance>> GetByEmployeeAndMonthAsync(int? employeeId, int month, int year);
        Task AddAsync(SalaryAdvance advance);
        Task DeleteAsync(int advanceId);
    }
}
