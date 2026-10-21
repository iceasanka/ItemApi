using ItemApi.Models;

namespace ItemApi.Interface
{
    public interface ILabelRepository
    {
        Task<List<LabelLayout>> GetLayoutsAsync(int? kind, bool includeDeleted);
        Task<LabelLayout?> GetLayoutAsync(int labelLayoutId);
        Task<LabelLayout> SaveLayoutAsync(int? labelLayoutId, LabelLayout request);
        Task DeleteLayoutAsync(int labelLayoutId, int? userId);
        List<string> GetPrinters();
        Task<LabelPrintResult> PrintTestAsync(int labelLayoutId);
        Task<byte[]> PreviewTestAsync(int labelLayoutId);

        // barcode labels (ZPL)
        Task<(LabelLayout Layout, string Zpl, LabelPrintResult Result)> BuildAsync(LabelPrintRequest request);
        Task<LabelPrintResult> PrintAsync(LabelPrintRequest request);

        // price labels (Windows printer driver)
        Task<LabelPrintResult> PrintPriceAsync(PriceLabelRequest request);
        Task<byte[]> PreviewPriceAsync(PriceLabelRequest request, int page);
    }
}
