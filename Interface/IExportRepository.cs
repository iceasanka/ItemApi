using ItemApi.Models;

namespace ItemApi.Interface
{
    public interface IExportRepository
    {
        Task<List<ExportSetting>> GetSettingsAsync();
        Task<ExportSetting?> GetSettingAsync(string exportCode);
        Task<ExportSetting> UpdateSettingAsync(string exportCode, ExportSettingUpdate request);
        Task<ExportPreview> GetScalePreviewAsync();
        Task<ExportResult> RunScaleExportAsync(int? userId);
        Task<(string FileName, byte[] Content)> BuildScaleFileAsync();
        Task<List<ExportLog>> GetLogAsync(string exportCode, int top);
    }
}
