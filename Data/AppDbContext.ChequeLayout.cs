using System.Data;
using System.Text.Json;
using ItemApi.Models;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;

namespace ItemApi.Data
{
    // Cheque layout (DBScript/29_BackOffice_ChequeLayout.sql, Updates/U049_BackOffice_ChequeLayout.sql).
    public partial class AppDbContext
    {
        private static readonly JsonSerializerOptions LayoutJson = new() { PropertyNameCaseInsensitive = true };

        public class ChequeLayoutRow
        {
            public string LayoutJson { get; set; } = "";
            public bool HasPrevious { get; set; }
            public DateTime UpdatedAt { get; set; }
            public string? UpdatedBy { get; set; }
        }

        // no row (never adjusted) = the defaults measured from the old BarTender template
        public async Task<ChequeLayoutInfo> GetChequeLayoutAsync()
        {
            var row = (await Database.SqlQueryRaw<ChequeLayoutRow>(
                "SELECT LayoutJson, CAST(CASE WHEN PrevLayoutJson IS NULL THEN 0 ELSE 1 END AS BIT) AS HasPrevious, UpdatedAt, UpdatedBy " +
                "FROM dbo.z_tb_ChequeLayout WHERE LayoutId = 1").ToListAsync()).FirstOrDefault();
            if (row == null)
                return new ChequeLayoutInfo { Layout = new ChequeLayout() };
            return new ChequeLayoutInfo
            {
                Layout = JsonSerializer.Deserialize<ChequeLayout>(row.LayoutJson, LayoutJson) ?? new ChequeLayout(),
                Saved = true,
                HasPrevious = row.HasPrevious,
                UpdatedAt = row.UpdatedAt,
                UpdatedBy = row.UpdatedBy,
            };
        }

        // the layout it replaces is kept (PrevLayoutJson) for undo
        public Task SaveChequeLayoutAsync(ChequeLayout layout, string? user) =>
            Database.ExecuteSqlRawAsync(
                "IF EXISTS (SELECT 1 FROM dbo.z_tb_ChequeLayout WHERE LayoutId = 1) " +
                "  UPDATE dbo.z_tb_ChequeLayout SET PrevLayoutJson = LayoutJson, LayoutJson = @Json, UpdatedAt = GETDATE(), UpdatedBy = @User WHERE LayoutId = 1; " +
                "ELSE INSERT dbo.z_tb_ChequeLayout (LayoutId, LayoutJson, UpdatedAt, UpdatedBy) VALUES (1, @Json, GETDATE(), @User);",
                new SqlParameter("@Json", SqlDbType.NVarChar, -1) { Value = JsonSerializer.Serialize(layout) },
                new SqlParameter("@User", SqlDbType.NVarChar, 50) { Value = (object?)Trim50(user) ?? DBNull.Value });

        // back to the layout before the last save (and that one becomes the "previous")
        public Task<int> UndoChequeLayoutAsync(string? user) =>
            Database.ExecuteSqlRawAsync(
                "UPDATE dbo.z_tb_ChequeLayout SET LayoutJson = PrevLayoutJson, PrevLayoutJson = LayoutJson, UpdatedAt = GETDATE(), UpdatedBy = @User " +
                "WHERE LayoutId = 1 AND PrevLayoutJson IS NOT NULL;",
                new SqlParameter("@User", SqlDbType.NVarChar, 50) { Value = (object?)Trim50(user) ?? DBNull.Value });

        private static string? Trim50(string? s) => string.IsNullOrWhiteSpace(s) ? null : s.Trim().Length > 50 ? s.Trim()[..50] : s.Trim();
    }
}
