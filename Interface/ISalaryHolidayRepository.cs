using ItemApi.Models;

namespace ItemApi.Interface
{
    public interface ISalaryHolidayRepository
    {
        Task<List<SalaryHoliday>> GetByMonthAsync(int month, int year);
        Task AddAsync(SalaryHoliday holiday);
        Task DeleteAsync(int holidayId);
    }
}
