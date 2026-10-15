using System.Data;
using ItemApi.Models;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;

namespace ItemApi.Data
{
    // Stock take — tables and procs from DBScript/Updates/U006_BackOffice_StockTake.sql. See Docs/StockSystem.md §6.18.
    // The DbSets are for reading only; every write goes through a z_sp_*StockTake* proc.
    // Business errors from the procs come back as SqlException 50000 (RAISERROR) → the controller answers 400.
    public partial class AppDbContext
    {
        public DbSet<StockTake> StockTakes { get; set; }
        public DbSet<StockTakeSheet> StockTakeSheets { get; set; }
        public DbSet<StockTakeItem> StockTakeItems { get; set; }

        partial void ConfigureStockTake(ModelBuilder modelBuilder)
        {
            modelBuilder.Entity<StockTakeItem>().HasKey(x => new { x.SheetId, x.ItemId });
        }

        public async Task<StockTakeCreateResult> CreateStockTakeAsync(int locationId, StockTakeCreateRequest r)
        {
            var rows = await Database.SqlQueryRaw<StockTakeCreateResult>(
                "EXEC dbo.z_sp_CreateStockTake @LocationId = @LocationId, @Title = @Title, @CatId = @CatId, @SubCatId = @SubCatId, " +
                "@SupId = @SupId, @IncludeZeroStock = @IncludeZeroStock, @ItemsPerSheet = @ItemsPerSheet, @UserId = @UserId",
                new SqlParameter("@LocationId", locationId),
                new SqlParameter("@Title", SqlDbType.NVarChar, 100) { Value = Db(r.Title) },
                new SqlParameter("@CatId", SqlDbType.Int) { Value = Db(r.CatId is > 0 ? r.CatId : null) },
                new SqlParameter("@SubCatId", SqlDbType.Int) { Value = Db(r.SubCatId is > 0 ? r.SubCatId : null) },
                new SqlParameter("@SupId", SqlDbType.Int) { Value = Db(r.SupId is > 0 ? r.SupId : null) },
                new SqlParameter("@IncludeZeroStock", r.IncludeZeroStock),
                new SqlParameter("@ItemsPerSheet", SqlDbType.Int) { Value = Db(r.ItemsPerSheet) },
                new SqlParameter("@UserId", SqlDbType.VarChar, 20) { Value = Db(r.UserId) }).ToListAsync();

            return rows.First();
        }

        public async Task<int> AddStockTakeSheetAsync(int stockTakeId, string sheetName, string? countedBy)
        {
            var sheetId = new SqlParameter("@SheetId", SqlDbType.Int) { Direction = ParameterDirection.Output };
            await Database.ExecuteSqlRawAsync(
                "EXEC dbo.z_sp_AddStockTakeSheet @StockTakeId = @StockTakeId, @SheetName = @SheetName, @CountedBy = @CountedBy, @SheetId = @SheetId OUTPUT",
                new SqlParameter("@StockTakeId", stockTakeId),
                new SqlParameter("@SheetName", SqlDbType.NVarChar, 100) { Value = sheetName },
                new SqlParameter("@CountedBy", SqlDbType.NVarChar, 50) { Value = Db(countedBy) },
                sheetId);
            return (int)sheetId.Value;
        }

        public async Task AddStockTakeItemAsync(int stockTakeId, int sheetId, int itemId)
        {
            await Database.ExecuteSqlRawAsync(
                "EXEC dbo.z_sp_AddStockTakeItem @StockTakeId = @StockTakeId, @SheetId = @SheetId, @ItemId = @ItemId",
                new SqlParameter("@StockTakeId", stockTakeId),
                new SqlParameter("@SheetId", sheetId),
                new SqlParameter("@ItemId", itemId));
        }

        public async Task SaveStockTakeCountsAsync(int stockTakeId, int sheetId, StockTakeCountsRequest r)
        {
            // column order = dbo.z_tt_StockTakeCount
            var counts = new DataTable();
            counts.Columns.Add("ItemId", typeof(int));
            counts.Columns.Add("CountedQty", typeof(decimal));
            counts.Columns.Add("Remark", typeof(string));
            foreach (var c in r.Counts)
                counts.Rows.Add(c.ItemId, Db(c.CountedQty), Db(c.Remark));

            await Database.ExecuteSqlRawAsync(
                "EXEC dbo.z_sp_SaveStockTakeCounts @StockTakeId = @StockTakeId, @SheetId = @SheetId, @Counts = @Counts, " +
                "@CountedBy = @CountedBy, @Done = @Done, @UserId = @UserId",
                new SqlParameter("@StockTakeId", stockTakeId),
                new SqlParameter("@SheetId", sheetId),
                Tvp("@Counts", "dbo.z_tt_StockTakeCount", counts),
                new SqlParameter("@CountedBy", SqlDbType.NVarChar, 50) { Value = Db(r.CountedBy) },
                new SqlParameter("@Done", SqlDbType.Bit) { Value = Db(r.Done) },
                new SqlParameter("@UserId", SqlDbType.VarChar, 20) { Value = Db(r.UserId) });
        }

        public async Task<List<StockTakeVarianceRow>> GetStockTakeVarianceAsync(int stockTakeId)
        {
            return await Database.SqlQueryRaw<StockTakeVarianceRow>(
                "EXEC dbo.z_sp_GetStockTakeVariance @StockTakeId = @StockTakeId",
                new SqlParameter("@StockTakeId", stockTakeId)).ToListAsync();
        }

        public async Task<StockTakePostResult> PostStockTakeAsync(int stockTakeId, StockTakePostRequest r)
        {
            var rows = await Database.SqlQueryRaw<StockTakePostResult>(
                "EXEC dbo.z_sp_PostStockTake @StockTakeId = @StockTakeId, @UncountedAsZero = @UncountedAsZero, " +
                "@ReasonId = @ReasonId, @UserId = @UserId",
                new SqlParameter("@StockTakeId", stockTakeId),
                new SqlParameter("@UncountedAsZero", r.UncountedAsZero),
                new SqlParameter("@ReasonId", SqlDbType.Int) { Value = r.ReasonId is > 0 ? r.ReasonId : 1 },
                new SqlParameter("@UserId", SqlDbType.VarChar, 20) { Value = Db(r.UserId) }).ToListAsync();

            return rows.First();
        }

        public async Task CancelStockTakeAsync(int stockTakeId, string? userId)
        {
            await Database.ExecuteSqlRawAsync(
                "EXEC dbo.z_sp_CancelStockTake @StockTakeId = @StockTakeId, @UserId = @UserId",
                new SqlParameter("@StockTakeId", stockTakeId),
                new SqlParameter("@UserId", SqlDbType.VarChar, 20) { Value = Db(userId) });
        }

        // A count sheet with item names; SystemQty only when asked (blind count by default).
        public async Task<List<StockTakeSheetLine>> GetStockTakeSheetLinesAsync(int sheetId, int locationId, bool showSystemQty)
        {
            return await Database.SqlQueryRaw<StockTakeSheetLine>(@"
                SELECT x.LineNum, x.ItemId, i.RefCode, i.Barcode, i.Descrip, u.UnitCode,
                       x.CountedQty, x.Remark, x.CountedBy, x.CountedAt,
                       CASE WHEN @Show = 1 THEN x.FrozenQty END AS SystemQty
                FROM dbo.z_tb_StockTakeItem x
                LEFT JOIN dbo.z_tb_Item i ON i.ItemId = x.ItemId
                LEFT JOIN dbo.z_tb_ItemDet d ON d.ItemId = x.ItemId AND d.LocationId = @LocationId
                LEFT JOIN dbo.z_tb_Unit u ON u.UnitId = d.UnitId
                WHERE x.SheetId = @SheetId
                ORDER BY x.LineNum",
                new SqlParameter("@SheetId", sheetId),
                new SqlParameter("@LocationId", locationId),
                new SqlParameter("@Show", showSystemQty)).ToListAsync();
        }
    }
}
