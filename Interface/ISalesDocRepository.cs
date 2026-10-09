using ItemApi.Models;

namespace ItemApi.Interface
{
    public interface ISalesDocRepository
    {
        Task<SalesDocSearchResult> SearchAsync(SalesDocSearchRequest request);
        Task<SalesDocDetail?> GetAsync(int docId);
        Task<SalesDoc> CreateAsync(SalesDocRequest request);
        Task<SalesDoc> UpdateAsync(int docId, SalesDocRequest request);
        Task<SalesDoc> CancelAsync(int docId, SalesDocCancelRequest request);
        Task<SalesDoc> ToInvoiceAsync(int quotationId, SalesDocToInvoiceRequest request);

        Task<SalesDocSetting> GetSettingAsync();
        Task<SalesDocSetting> UpdateSettingAsync(SalesDocSetting request);
        Task<SalesDocSetting> SetLogoAsync(string? logoFile, int? userId);
    }
}
