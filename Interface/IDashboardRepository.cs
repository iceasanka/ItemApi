using ItemApi.Models;

namespace ItemApi.Interface
{
    public interface IDashboardRepository
    {
        Task<DashboardToday> GetTodayAsync(int? terminalId);
        Task<DashboardSales> GetSalesAsync(DateTime fromDate, DateTime toDate, int? terminalId, int top);
    }
}
