using ItemApi.Models;

namespace ItemApi.Interface
{
    public interface ISettingRepository
    {
        Task<List<SettingRow>> ListAsync();
        Task SetAsync(string key, string? value, int updatedBy);
        Task<UserSettingsList> ListUsersAsync();
        Task SetUserAsync(int userId, string key, string? value, int updatedBy);
    }
}
