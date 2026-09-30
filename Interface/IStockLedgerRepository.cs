using ItemApi.Models;

namespace ItemApi.Interface
{
    public interface IStockLedgerRepository
    {
        Task<StockBalanceRow?> GetBalanceAsync(int itemId);
        Task<StockBalancePage> SearchBalancesAsync(StockBalanceSearchRequest request);
        Task<ItemCard?> GetItemCardAsync(int itemId, DateTime fromDate, DateTime toDate);
        Task<int> PostGrnAsync(string grnNo, string? userId);
        Task<int> PostPrnAsync(string prnNo, string? userId);
    }
}
