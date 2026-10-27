using System.Data;
using ItemApi.Models;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;

namespace ItemApi.Data
{
    // Settings (z_tb_Setting, z_tb_UserSetting — DBScript/24_BackOffice_Settings.sql, Updates/U023_BackOffice_Settings.sql).
    public partial class AppDbContext
    {
        public async Task<List<SettingRow>> GetSettingsAsync()
        {
            return await Database.SqlQueryRaw<SettingRow>("EXEC dbo.z_sp_GetSettings").ToListAsync();
        }

        public async Task SetSettingAsync(string key, string? value, int updatedBy)
        {
            await Database.ExecuteSqlRawAsync(
                "EXEC dbo.z_sp_SetSetting @SettingKey = @SettingKey, @Value = @Value, @UpdatedBy = @UpdatedBy",
                new SqlParameter("@SettingKey", SqlDbType.VarChar, 50) { Value = key },
                new SqlParameter("@Value", SqlDbType.NVarChar, 200) { Value = (object?)value ?? DBNull.Value },
                new SqlParameter("@UpdatedBy", updatedBy));
        }

        public async Task<List<UserSettingValue>> GetUserSettingValuesAsync(int? userId)
        {
            return await Database.SqlQueryRaw<UserSettingValue>(
                "EXEC dbo.z_sp_GetUserSettingValues @UserId = @UserId",
                new SqlParameter("@UserId", SqlDbType.Int) { Value = (object?)userId ?? DBNull.Value }).ToListAsync();
        }

        public async Task SetUserSettingAsync(int userId, string key, string? value, int updatedBy)
        {
            await Database.ExecuteSqlRawAsync(
                "EXEC dbo.z_sp_SetUserSetting @UserId = @UserId, @SettingKey = @SettingKey, @Value = @Value, @UpdatedBy = @UpdatedBy",
                new SqlParameter("@UserId", userId),
                new SqlParameter("@SettingKey", SqlDbType.VarChar, 50) { Value = key },
                new SqlParameter("@Value", SqlDbType.NVarChar, 200) { Value = (object?)value ?? DBNull.Value },
                new SqlParameter("@UpdatedBy", updatedBy));
        }

        public async Task<List<SyncSetting>> GetSettingsForSyncAsync()
        {
            return await Database.SqlQueryRaw<SyncSetting>("EXEC dbo.z_sp_GetSettingsForSync").ToListAsync();
        }
    }
}
