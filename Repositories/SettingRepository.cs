using ItemApi.Data;
using ItemApi.Interface;
using ItemApi.Models;
using Microsoft.EntityFrameworkCore;

namespace ItemApi.Repositories
{
    // Settings page: general values and users' own values. The procs check the key and the value (SQL error → 400).
    // Tills get the change on their next download (≤ 5 min / Reload).
    public class SettingRepository : ISettingRepository
    {
        private readonly AppDbContext _context;

        public SettingRepository(AppDbContext context)
        {
            _context = context;
        }

        public Task<List<SettingRow>> ListAsync() => _context.GetSettingsAsync();

        public Task SetAsync(string key, string? value, int updatedBy) =>
            _context.SetSettingAsync(key, Blank(value), updatedBy);

        public async Task<UserSettingsList> ListUsersAsync()
        {
            var settings = (await _context.GetSettingsAsync()).Where(s => s.Scope == 2).ToList();
            var values = await _context.GetUserSettingValuesAsync(null);
            var users = await _context.AppUsers.AsNoTracking()
                .Where(u => u.LoginName != null)
                .OrderByDescending(u => u.Status).ThenBy(u => u.LoginName)
                .ToListAsync();

            return new UserSettingsList
            {
                Settings = settings,
                Users = users.Select(u => new UserSettingsRow
                {
                    UserId = u.UserId,
                    LoginName = u.LoginName,
                    UserName = u.UserName,
                    RoleId = u.RoleId,
                    Status = u.Status,
                    Values = values.Where(v => v.UserId == u.UserId).ToDictionary(v => v.SettingKey, v => v.Value)
                }).ToList()
            };
        }

        public Task SetUserAsync(int userId, string key, string? value, int updatedBy) =>
            _context.SetUserSettingAsync(userId, key, Blank(value), updatedBy);

        private static string? Blank(string? value) => string.IsNullOrWhiteSpace(value) ? null : value.Trim();
    }
}
