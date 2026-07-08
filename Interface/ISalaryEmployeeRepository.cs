using ItemApi.Models;

namespace ItemApi.Interface
{
    public interface ISalaryEmployeeRepository
    {
        Task<List<SalaryEmployee>> GetAllActiveAsync();
        Task<List<SalaryEmployee>> GetAllAsync();
        Task<SalaryEmployee?> GetByIdAsync(int employeeId);
        Task<bool> ExistsAsync(int employeeId);
        Task AddAsync(SalaryEmployee employee);
        Task UpdateAsync(SalaryEmployee employee);
        Task DeactivateAsync(int employeeId);
    }
}
