using ItemApi.Models;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;

namespace ItemApi.Data
{
    // File exports (z_tb_ExportSetting, z_tb_ExportLog, z_tb_ScaleExportItem — DBScript/05_BackOffice_Export.sql).
    public partial class AppDbContext
    {
        public DbSet<ExportSetting> ExportSettings { get; set; }
        public DbSet<ExportLog> ExportLogs { get; set; }
        public DbSet<ScaleExportItem> ScaleExportItems { get; set; }

        partial void ConfigureExport(ModelBuilder modelBuilder)
        {
            modelBuilder.Entity<ExportSetting>().ToTable("z_tb_ExportSetting");
            modelBuilder.Entity<ExportLog>().ToTable("z_tb_ExportLog");
            modelBuilder.Entity<ScaleExportItem>().ToTable("z_tb_ScaleExportItem");
        }

        // Scale items = active items whose unit at the location is KGS
        public async Task<List<ScaleItemSource>> GetScaleItemSourcesAsync(int locationId)
        {
            return await Database.SqlQueryRaw<ScaleItemSource>(@"
                SELECT i.ItemId, i.RefCode, i.Descrip, d.RetailPrice, d.IsSaleLocked
                FROM dbo.z_tb_Item i
                JOIN dbo.z_tb_ItemDet d ON d.ItemId = i.ItemId AND d.LocationId = @LocationId
                JOIN dbo.z_tb_Unit u    ON u.UnitId = d.UnitId
                WHERE i.Status = 1 AND LTRIM(RTRIM(u.UnitCode)) = 'KGS'",
                new SqlParameter("@LocationId", locationId)).ToListAsync();
        }

        // Replaces the "last exported" snapshot and records the export, in one transaction
        public async Task SaveScaleExportAsync(ExportSetting setting, List<ScaleExportItem> items, ExportLog log)
        {
            await using var tx = await Database.BeginTransactionAsync();
            await Database.ExecuteSqlRawAsync("DELETE FROM dbo.z_tb_ScaleExportItem");
            ScaleExportItems.AddRange(items);
            ExportLogs.Add(log);
            ExportSettings.Update(setting);
            await SaveChangesAsync();
            await tx.CommitAsync();
        }
    }
}
