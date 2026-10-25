using ItemApi.Models;

namespace ItemApi.Interface
{
    public interface IDayReportRepository
    {
        Task<DayReport> GetDayAsync(DateTime date, int? terminalId);
        Task<List<DayItem>> GetItemsAsync(DateTime date, int? terminalId);
        Task<List<DayBill>> GetBillsAsync(DateTime date, int? terminalId);
        Task<DayBillDetail?> GetBillAsync(string invoiceNo);
        Task<DayLoss> GetLossAsync(DateTime date, int? terminalId);
    }
}
