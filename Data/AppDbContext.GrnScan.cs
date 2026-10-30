using System.Data;
using ItemApi.Models;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;

namespace ItemApi.Data
{
    // GRN scan - matching invoice lines to our items (DBScript/25_BackOffice_GrnScan.sql, Updates/U029).
    public partial class AppDbContext
    {
        // saved scans (U031)
        public DbSet<GrnScanDoc> GrnScanDocs { get; set; }

        // rows: (line key, supplier code, name key, barcode)
        public async Task<List<GrnScanMatchRow>> GrnScanMatchAsync(int suppId, IEnumerable<(int Key, string? Code, string? NameKey, string? Barcode)> rows)
        {
            // column order = dbo.z_tt_GrnScanLine
            var t = new DataTable();
            t.Columns.Add("LineKey", typeof(int));
            t.Columns.Add("SupplierCode", typeof(string));
            t.Columns.Add("DescripKey", typeof(string));
            t.Columns.Add("Barcode", typeof(string));
            foreach (var r in rows)
                t.Rows.Add(r.Key, (object?)r.Code ?? DBNull.Value, (object?)r.NameKey ?? DBNull.Value, (object?)r.Barcode ?? DBNull.Value);

            return await Database.SqlQueryRaw<GrnScanMatchRow>(
                "EXEC dbo.z_sp_GrnScanMatch @SuppId = @SuppId, @Lines = @Lines",
                new SqlParameter("@SuppId", suppId),
                new SqlParameter("@Lines", SqlDbType.Structured) { TypeName = "dbo.z_tt_GrnScanLine", Value = t }).ToListAsync();
        }

        public async Task<int> GrnScanSaveMapsAsync(int suppId, IEnumerable<GrnScanMapRow> rows, int? userId)
        {
            // column order = dbo.z_tt_GrnScanMap
            var t = new DataTable();
            t.Columns.Add("SupplierCode", typeof(string));
            t.Columns.Add("SupplierDescrip", typeof(string));
            t.Columns.Add("DescripKey", typeof(string));
            t.Columns.Add("ItemId", typeof(int));
            t.Columns.Add("CaseSize", typeof(decimal));
            foreach (var r in rows)
                t.Rows.Add((object?)r.SupplierCode ?? DBNull.Value, r.SupplierDescrip, r.DescripKey, r.ItemId, (object?)r.CaseSize ?? DBNull.Value);

            var saved = await Database.SqlQueryRaw<GrnScanSavedRow>(
                "EXEC dbo.z_sp_GrnScanSaveMaps @SuppId = @SuppId, @Rows = @Rows, @UserId = @UserId",
                new SqlParameter("@SuppId", suppId),
                new SqlParameter("@Rows", SqlDbType.Structured) { TypeName = "dbo.z_tt_GrnScanMap", Value = t },
                new SqlParameter("@UserId", SqlDbType.Int) { Value = (object?)userId ?? DBNull.Value }).ToListAsync();
            return saved.FirstOrDefault()?.Saved ?? 0;
        }

        public Task<List<GrnScanMap>> GrnScanGetMapsAsync(int suppId) =>
            Database.SqlQueryRaw<GrnScanMap>("EXEC dbo.z_sp_GrnScanGetMaps @SuppId = @SuppId",
                new SqlParameter("@SuppId", suppId)).ToListAsync();

        public async Task<int> GrnScanDeleteMapAsync(int mapId) =>
            (await Database.SqlQueryRaw<GrnScanDeletedRow>("EXEC dbo.z_sp_GrnScanDeleteMap @MapId = @MapId",
                new SqlParameter("@MapId", mapId)).ToListAsync()).FirstOrDefault()?.Deleted ?? 0;

        public async Task<GrnScanDraftResult> GrnScanMakeDraftAsync(int suppId, string? refNo, string? remark, bool allowSameRef, IEnumerable<GrnScanDraftRow> rows)
        {
            // column order = dbo.z_tt_GrnScanDraftLine
            var t = new DataTable();
            t.Columns.Add("LineKey", typeof(int));
            t.Columns.Add("ItemId", typeof(int));
            t.Columns.Add("Qty", typeof(decimal));
            t.Columns.Add("CostPrice", typeof(decimal));
            t.Columns.Add("SellPrice", typeof(decimal));
            t.Columns.Add("GAmount", typeof(decimal));
            t.Columns.Add("FreeQty", typeof(decimal));
            foreach (var r in rows)
                t.Rows.Add(r.LineKey, r.ItemId, r.Qty, (object?)r.CostPrice ?? DBNull.Value, (object?)r.SellPrice ?? DBNull.Value, r.GAmount,
                           (object?)r.FreeQty ?? DBNull.Value);

            var result = await Database.SqlQueryRaw<GrnScanDraftResult>(
                "EXEC dbo.z_sp_GrnScanMakeDraft @SuppId = @SuppId, @RefNo = @RefNo, @Remark = @Remark, @Lines = @Lines, @AllowSameRef = @AllowSameRef",
                new SqlParameter("@SuppId", suppId),
                new SqlParameter("@RefNo", SqlDbType.VarChar, 30) { Value = (object?)refNo ?? DBNull.Value },
                new SqlParameter("@Remark", SqlDbType.VarChar, 200) { Value = (object?)remark ?? DBNull.Value },
                new SqlParameter("@Lines", SqlDbType.Structured) { TypeName = "dbo.z_tt_GrnScanDraftLine", Value = t },
                new SqlParameter("@AllowSameRef", allowSameRef)).ToListAsync();
            return result.First();
        }

        // active items for the closest-name suggestions
        public Task<List<GrnScanItemRow>> GrnScanItemsAsync() =>
            Database.SqlQueryRaw<GrnScanItemRow>(
                "SELECT i.ItemId, i.RefCode, i.Barcode, i.Descrip, i.SupId, d.RetailPrice, d.CostPrice " +
                "FROM dbo.z_tb_Item i LEFT JOIN dbo.z_tb_ItemDet d ON d.ItemId = i.ItemId AND d.LocationId = 1 " +
                "WHERE i.Status = 1").ToListAsync();
    }
}
