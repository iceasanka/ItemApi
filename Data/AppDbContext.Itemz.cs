using System.Data;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using ItemApi.Models;
using Serilog;

namespace ItemApi.Data
{
    // Itemz / ItemzDet (z_tb_Item, z_tb_ItemDet) — consolidated from the former ItemzContext.
    // NOTE: this is a different table/entity family from Item (tb_Item) in AppDbContext.Item.cs —
    // kept deliberately separate on the user's instruction, do not merge the two.
    public partial class AppDbContext
    {
        public DbSet<Itemz> Itemzs { get; set; }
        public DbSet<ItemzDet> ItemzDets { get; set; }
        public DbSet<ItemzWithDetails> ItemzWithDetails { get; set; }

        partial void ConfigureItemz(ModelBuilder modelBuilder)
        {
            modelBuilder.Entity<Itemz>().ToTable("z_tb_Item");
            modelBuilder.Entity<ItemzDet>().ToTable("z_tb_ItemDet");
            modelBuilder.Entity<ItemzWithDetails>().HasNoKey();
        }

        // ─── Queries ─────────────────────────────────────────────────────────────

        public async Task<ItemzWithDetails?> GetItemzWithDetailsByItemIdAsync(int itemId, int locationId)
        {
            string sql = @"
                SELECT
                    i.*,
    d.ItemDetId,
    d.LocationId ,
    d.RetailPrice,
    d.WholesalePrice,
    d.SpecialPrice,
    d.CostPrice,
    d.AverageCost,
    d.UnitId,
    d.WholesaleMargin,
    d.RetailMargin,
    d.IsSaleLocked,
    d.NoDiscount,
    d.ReorderLevel,
    d.ReorderQty,
    d.QtyLevel2,
    d.PriceLevel2,
    d.QtyLevel3,
    d.PriceLevel3,
    d.QtyLevel4,
    d.PriceLevel4,
    d.DiscountAmount,
    d.DiscountPercent
                FROM z_tb_Item i
                JOIN z_tb_ItemDet d ON i.ItemId = d.ItemId
                WHERE i.ItemId = {0} and d.LocationId = {1}";

            try
            {
                return await ItemzWithDetails.FromSqlRaw(sql, itemId, locationId).FirstOrDefaultAsync();
            }
            catch (Exception ex)
            {
                Log.Error($"Error fetching itemz by ItemId: {ex.Message}");
                throw;
            }
        }

        public async Task<ItemzWithDetails?> GetItemzWithDetailsByBarcodeAsync(string barcode, int locationId)
        {
            string sql = @"
                SELECT
                    i.*,
    d.ItemDetId,
    d.LocationId ,
    d.RetailPrice,
    d.WholesalePrice,
    d.SpecialPrice,
    d.CostPrice,
    d.AverageCost,
    d.UnitId,
    d.WholesaleMargin,
    d.RetailMargin,
    d.IsSaleLocked,
    d.NoDiscount,
    d.ReorderLevel,
    d.ReorderQty,
    d.QtyLevel2,
    d.PriceLevel2,
    d.QtyLevel3,
    d.PriceLevel3,
    d.QtyLevel4,
    d.PriceLevel4,
    d.DiscountAmount,
    d.DiscountPercent
                FROM z_tb_Item i
                JOIN z_tb_ItemDet d ON i.ItemId = d.ItemId
                WHERE i.Barcode = {0} and d.LocationId = {1}";

            try
            {
                return await ItemzWithDetails.FromSqlRaw(sql, barcode, locationId).FirstOrDefaultAsync();
            }
            catch (Exception ex)
            {
                Log.Error($"Error fetching itemz by Barcode: {ex.Message}");
                throw;
            }
        }

        public async Task<ItemzWithDetails?> GetItemzWithDetailsByRefCodeAsync(string refCode, int locationId)
        {
            string sql = @"
                SELECT
                    i.*,
    d.ItemDetId,
    d.LocationId ,
    d.RetailPrice,
    d.WholesalePrice,
    d.SpecialPrice,
    d.CostPrice,
    d.AverageCost,
    d.UnitId,
    d.WholesaleMargin,
    d.RetailMargin,
    d.IsSaleLocked,
    d.NoDiscount,
    d.ReorderLevel,
    d.ReorderQty,
    d.QtyLevel2,
    d.PriceLevel2,
    d.QtyLevel3,
    d.PriceLevel3,
    d.QtyLevel4,
    d.PriceLevel4,
    d.DiscountAmount,
    d.DiscountPercent
                FROM z_tb_Item i
                JOIN z_tb_ItemDet d ON i.ItemId = d.ItemId
                WHERE i.RefCode = {0} and d.LocationId = {1}";

            try
            {
                return await ItemzWithDetails.FromSqlRaw(sql, refCode, locationId).FirstOrDefaultAsync();
            }
            catch (Exception ex)
            {
                Log.Error($"Error fetching itemz by RefCode: {ex.Message}");
                throw;
            }
        }

        public async Task<List<ItemzWithDetails>> SearchItemzAsync(string query, int locationId)
        {
            string sql = @"
                SELECT
                   i.*,
    d.ItemDetId,

    d.LocationId,
    d.RetailPrice,
    d.WholesalePrice,
    d.SpecialPrice,
    d.CostPrice,
    d.AverageCost,
    d.UnitId,
    d.WholesaleMargin,
    d.RetailMargin,
    d.IsSaleLocked,
    d.NoDiscount,
    d.ReorderLevel,
    d.ReorderQty,
    d.QtyLevel2,
    d.PriceLevel2,
    d.QtyLevel3,
    d.PriceLevel3,
    d.QtyLevel4,
    d.PriceLevel4,
    d.DiscountAmount,
    d.DiscountPercent
                FROM z_tb_Item i
                JOIN z_tb_ItemDet d ON i.ItemId = d.ItemId
                WHERE (i.Descrip LIKE {0}
                   OR i.RefCode LIKE {0}
                   OR i.Barcode LIKE {0}) and d.LocationId = {1}";

            try
            {
                return await ItemzWithDetails.FromSqlRaw(sql, $"%{query}%", locationId).ToListAsync();
            }
            catch (Exception ex)
            {
                Log.Error($"Error searching itemz: {ex.Message}");
                throw;
            }
        }

        public async Task<List<ItemzWithDetails>> SearchByCodeItemzAsync(string query, int locationId)
        {
            string sql = @"
                SELECT
                    i.*,
    d.ItemDetId,
    d.LocationId ,
    d.RetailPrice,
    d.WholesalePrice,
    d.SpecialPrice,
    d.CostPrice,
    d.AverageCost,
    d.UnitId,
    d.WholesaleMargin,
    d.RetailMargin,
    d.IsSaleLocked,
    d.NoDiscount,
    d.ReorderLevel,
    d.ReorderQty,
    d.QtyLevel2,
    d.PriceLevel2,
    d.QtyLevel3,
    d.PriceLevel3,
    d.QtyLevel4,
    d.PriceLevel4,
    d.DiscountAmount,
    d.DiscountPercent
                FROM z_tb_Item i
                JOIN z_tb_ItemDet d ON i.ItemId = d.ItemId
                WHERE (i.ItemId LIKE {0}
                   OR i.RefCode LIKE {0}
                   OR i.Barcode LIKE {0}) and d.LocationId = {1}";

            try
            {
                return await ItemzWithDetails.FromSqlRaw(sql, $"%{query}%", locationId).ToListAsync();
            }
            catch (Exception ex)
            {
                Log.Error($"Error searching itemz: {ex.Message}");
                throw;
            }
        }

        public async Task<List<ItemzWithDetails>> SearchByDesItemzAsync(string query, int locationId)
        {
            string sql = @"
                SELECT
                    i.*,
    d.ItemDetId,
    d.LocationId,
    d.RetailPrice,
    d.WholesalePrice,
    d.SpecialPrice,
    d.CostPrice,
    d.AverageCost,
    d.UnitId,
    d.WholesaleMargin,
    d.RetailMargin,
    d.IsSaleLocked,
    d.NoDiscount,
    d.ReorderLevel,
    d.ReorderQty,
    d.QtyLevel2,
    d.PriceLevel2,
    d.QtyLevel3,
    d.PriceLevel3,
    d.QtyLevel4,
    d.PriceLevel4,
    d.DiscountAmount,
    d.DiscountPercent
                FROM z_tb_Item i
                JOIN z_tb_ItemDet d ON i.ItemId = d.ItemId
                WHERE i.Descrip LIKE {0} and d.LocationId = {1}";

            try
            {
                return await ItemzWithDetails.FromSqlRaw(sql, $"%{query}%", locationId).ToListAsync();
            }
            catch (Exception ex)
            {
                Log.Error($"Error searching itemz: {ex.Message}");
                throw;
            }
        }

        // ─── CRUD ─────────────────────────────────────────────────────────────────

        public async Task<Itemz> InsertItemzAsync(Itemz item)
        {
            try
            {
                Itemzs.Add(item);
                await SaveChangesAsync();
                return item;
            }
            catch (Exception ex)
            {
                Log.Error($"Error inserting itemz: {ex.Message}");
                throw;
            }
        }

        public async Task<Itemz> UpdateItemzAsync(Itemz item)
        {
            try
            {
                Itemzs.Update(item);
                await SaveChangesAsync();
                return item;
            }
            catch (Exception ex)
            {
                Log.Error($"Error updating itemz: {ex.Message}");
                throw;
            }
        }

        public async Task DeleteItemzAsync(int itemId)
        {
            try
            {
                var item = await Itemzs.FindAsync(itemId);
                if (item != null)
                {
                    Itemzs.Remove(item);
                    await SaveChangesAsync();
                }
            }
            catch (Exception ex)
            {
                Log.Error($"Error deleting itemz: {ex.Message}");
                throw;
            }
        }

        public async Task<ItemzDet> InsertItemzDetAsync(ItemzDet det)
        {
            try
            {
                ItemzDets.Add(det);
                await SaveChangesAsync();
                return det;
            }
            catch (Exception ex)
            {
                Log.Error($"Error inserting itemzDet: {ex.Message}");
                throw;
            }
        }

        public async Task<ItemzDet> UpdateItemzDetAsync(ItemzDet det)
        {
            try
            {
                ItemzDets.Update(det);
                await SaveChangesAsync();
                return det;
            }
            catch (Exception ex)
            {
                Log.Error($"Error updating itemzDet: {ex.Message}");
                throw;
            }
        }

        // ─── Price links (z_tb_ItemPriceLink, DBScript/03_BackOffice_PriceLink.sql) ───

        public async Task<List<ItemzPriceLink>> GetPriceLinksAsync(int itemId, int locationId)
        {
            return await Database.SqlQueryRaw<ItemzPriceLink>(@"
                SELECT PriceLinkId, ItemId, LocationId, RetailPrice, WholesalePrice, CostPrice, Remark, Status, UserId, CDate, UDate
                FROM dbo.z_tb_ItemPriceLink
                WHERE ItemId = @ItemId AND LocationId = @LocationId AND Status = 1
                ORDER BY RetailPrice",
                new SqlParameter("@ItemId", itemId),
                new SqlParameter("@LocationId", locationId)).ToListAsync();
        }

        // Business errors come back as SqlException 50041–50045
        public async Task<ItemzPriceLink> AddPriceLinkAsync(AddPriceLinkRequest request, int locationId)
        {
            var rows = await Database.SqlQueryRaw<ItemzPriceLink>(
                "EXEC dbo.z_sp_AddPriceLink @ItemId = @ItemId, @LocationId = @LocationId, @RetailPrice = @RetailPrice, " +
                "@WholesalePrice = @WholesalePrice, @CostPrice = @CostPrice, @Remark = @Remark, @UserId = @UserId",
                new SqlParameter("@ItemId", request.ItemId),
                new SqlParameter("@LocationId", locationId),
                new SqlParameter("@RetailPrice", SqlDbType.Decimal) { Precision = 18, Scale = 2, Value = request.RetailPrice },
                new SqlParameter("@WholesalePrice", SqlDbType.Decimal) { Precision = 18, Scale = 2, Value = (object?)request.WholesalePrice ?? DBNull.Value },
                new SqlParameter("@CostPrice", SqlDbType.Decimal) { Precision = 18, Scale = 2, Value = (object?)request.CostPrice ?? DBNull.Value },
                new SqlParameter("@Remark", SqlDbType.NVarChar, 50) { Value = (object?)request.Remark ?? DBNull.Value },
                new SqlParameter("@UserId", SqlDbType.Int) { Value = (object?)request.UserId ?? DBNull.Value }).ToListAsync();
            return rows.First();
        }

        public async Task DeletePriceLinkAsync(int priceLinkId, int? userId)
        {
            await Database.ExecuteSqlRawAsync(
                "EXEC dbo.z_sp_DeletePriceLink @PriceLinkId = @PriceLinkId, @UserId = @UserId",
                new SqlParameter("@PriceLinkId", priceLinkId),
                new SqlParameter("@UserId", SqlDbType.Int) { Value = (object?)userId ?? DBNull.Value });
        }
    }
}
