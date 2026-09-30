using ItemApi.Models;

namespace ItemApi.Interface
{
    public interface ISyncRepository
    {
        Task<Terminal> RegisterTerminalAsync(TerminalRegisterRequest request);
        Task<List<TerminalStatus>> GetTerminalsAsync();
        Task<SyncDownload<SyncItem>> GetItemsAsync(int terminalId, DateTime? since);
        Task<SyncDownload<SyncStockBalance>> GetStockBalancesAsync(int terminalId, DateTime? since);
        Task<List<SyncInvoiceResult>> UploadInvoicesAsync(SyncInvoiceBatch batch);
        Task<ZReportSubmitResponse> SubmitZReportAsync(ZReportSubmit z);
        Task<ZReportSubmitResponse> ReconcileZReportAsync(int terminalId, int zNo);
        Task<ZReport?> GetZReportAsync(int terminalId, int zNo);
        Task<List<ZReport>> SearchZReportsAsync(ZReportSearchRequest request);
    }
}
