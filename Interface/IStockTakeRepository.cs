using ItemApi.Models;

namespace ItemApi.Interface
{
    public interface IStockTakeRepository
    {
        Task<StockTake> CreateAsync(StockTakeCreateRequest request);
        Task<List<StockTake>> SearchAsync(StockTakeSearchRequest request);
        Task<StockTake?> GetAsync(int stockTakeId);
        Task<StockTakeSheetView?> GetSheetAsync(int stockTakeId, int sheetId, bool showSystemQty);
        Task<StockTakeSheet> AddSheetAsync(int stockTakeId, StockTakeAddSheetRequest request);
        Task<StockTakeSheetLine> AddItemAsync(int stockTakeId, int sheetId, StockTakeAddItemRequest request);
        Task SaveCountsAsync(int stockTakeId, int sheetId, StockTakeCountsRequest request);
        Task<StockTakeVariance?> GetVarianceAsync(int stockTakeId, bool onlyDiff);
        Task<StockTakePostResult> PostAsync(int stockTakeId, StockTakePostRequest request);
        Task CancelAsync(int stockTakeId, string? userId);
    }
}
