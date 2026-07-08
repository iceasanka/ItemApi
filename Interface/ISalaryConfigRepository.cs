using ItemApi.Models;

namespace ItemApi.Interface
{
    public interface ISalaryConfigRepository
    {
        Task<SalaryConfig> GetConfigAsync();
        Task UpdateConfigAsync(SalaryConfig config);
    }
}
