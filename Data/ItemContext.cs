using Microsoft.EntityFrameworkCore;
using ItemApi.Models;

namespace ItemApi.Data
{
    public class ItemContext : DbContext
    {
        public ItemContext(DbContextOptions<ItemContext> options) : base(options) { }

        public DbSet<Item> Items { get; set; }

        public DbSet<ItemDetail> ItemDetails { get; set; }

        public DbSet<ItemWithDetails> ItemWithDetails { get; set; }
        public DbSet<PriceLink> PriceLinks { get; set; }

        protected override void OnModelCreating(ModelBuilder modelBuilder)
        {
            modelBuilder.Entity<Item>().ToTable("tb_Item");
            modelBuilder.Entity<ItemDetail>().ToTable("tb_ItemDet");
            modelBuilder.Entity<ItemWithDetails>().HasNoKey();
            modelBuilder.Entity<PriceLink>().HasNoKey();
        }

        public async Task<ItemWithDetails> GetItemWithDetailsByBarcodeAsync(string barcode)
        {
            string sql = @"
                SELECT 
                    tb_item.*, 
                    tb_itemdet.Item_Code AS Detail_Item_Code, tb_itemdet.Loca_Code, tb_itemdet.PRet_Price, tb_itemdet.PWhole_Price, tb_itemdet.PSp_Price,
                    tb_itemdet.ERet_Price, tb_itemdet.EWhole_Price, tb_itemdet.ESp_Price, tb_itemdet.Cost_Price, tb_itemdet.AvgCost, tb_itemdet.Cost_Code,
                    tb_itemdet.Lock_S, tb_itemdet.Lock_P, tb_itemdet.NoDiscount, tb_itemdet.Re_Qty, tb_itemdet.Rol, tb_itemdet.Qty, tb_itemdet.User_Id,
                    tb_itemdet.CDate, tb_itemdet.EditDate, tb_itemdet.BinNo, tb_itemdet.SPQ, tb_itemdet.SPR, tb_itemdet.TPQ, tb_itemdet.TPR, tb_itemdet.FPQ,
                    tb_itemdet.FPR, tb_itemdet.FIPQ, tb_itemdet.FIPR, tb_itemdet.SIPQ, tb_itemdet.SIPR, tb_itemdet.SEPQ, tb_itemdet.SEPR, tb_itemdet.EIPQ,
                    tb_itemdet.EIPR, tb_itemdet.Commission, tb_itemdet.SPHSQ, tb_itemdet.SPHSR, tb_itemdet.TPHSQ, tb_itemdet.TPHSR, tb_itemdet.FPHSQ, tb_itemdet.FPHSR,
                    tb_itemdet.FIPHSQ, tb_itemdet.FIPHSR, tb_itemdet.SIPHSQ, tb_itemdet.SIPHSR, tb_itemdet.SEPHSQ, tb_itemdet.SEPHSR, tb_itemdet.EIPHSQ, tb_itemdet.EIPHSR,
                    tb_itemdet.C_Price,
                    CASE WHEN tb_item.pack_size > 1 THEN 'PACK' ELSE 'EACH' END AS PackScale
                FROM tb_item WITH (INDEX=item_item_code)
                JOIN tb_itemdet WITH (INDEX=itemdet_loca_code_item_code)
                ON tb_item.item_code = tb_itemdet.item_code
                WHERE tb_itemdet.loca_code = '01'
                AND (tb_itemdet.item_code = {0}
                OR tb_item.barcode = {0}
                OR tb_item.ref_code = {0})";

            try
            {
                return await ItemWithDetails.FromSqlRaw(sql, barcode).FirstOrDefaultAsync();
            }
            catch (Exception ex)
            {
                // Log the exception here if needed
               // Console.WriteLine($"Error fetching item details: {ex.Message}");
               // return null; // Or throw, depending on how you want to handle the error
                throw ex;
            }
        }

        public async Task<ItemWithDetails> GetItemWithDetailsByItemCodeAsync(string itemCode)
        {
            string sql = @"
                SELECT 
                    tb_item.*, 
                    tb_itemdet.Item_Code AS Detail_Item_Code, tb_itemdet.Loca_Code, tb_itemdet.PRet_Price, tb_itemdet.PWhole_Price, tb_itemdet.PSp_Price,
                    tb_itemdet.ERet_Price, tb_itemdet.EWhole_Price, tb_itemdet.ESp_Price, tb_itemdet.Cost_Price, tb_itemdet.AvgCost, tb_itemdet.Cost_Code,
                    tb_itemdet.Lock_S, tb_itemdet.Lock_P, tb_itemdet.NoDiscount, tb_itemdet.Re_Qty, tb_itemdet.Rol, tb_itemdet.Qty, tb_itemdet.User_Id,
                    tb_itemdet.CDate, tb_itemdet.EditDate,
                    tb_itemdet.C_Price,
                    CASE WHEN tb_item.pack_size > 1 THEN 'PACK' ELSE 'EACH' END AS PackScale
                FROM tb_item WITH (INDEX=item_item_code)
                JOIN tb_itemdet WITH (INDEX=itemdet_loca_code_item_code)
                ON tb_item.item_code = tb_itemdet.item_code
                WHERE tb_itemdet.loca_code = '01'
                AND (tb_itemdet.item_code = {0})";

            try
            {
                return await ItemWithDetails.FromSqlRaw(sql, itemCode).FirstOrDefaultAsync();
            }
            catch (Exception ex)
            {
                // Log the exception here if needed
               // Console.WriteLine($"Error fetching item details: {ex.Message}");
               // return null; // Or throw, depending on how you want to handle the error
                throw ex;
            }
        }

        public async Task<List<PriceLink>> GetPriceLink(string itemCode)
        {
            string sql = @"
        SELECT itemcode,
               packsize,
               costprice,
               price,
               ewholeprice,
               pretprice,
               pwholeprice
                    FROM tb_pricelink
                    WHERE itemcode = {0}
                    AND status = 1 
                    AND loca = '01'
                    ORDER  BY createdate DESC 
    ";
            // status = 1 AND

            try
            {
                return await PriceLinks.FromSqlRaw(sql, itemCode).ToListAsync();
            }
            catch (Exception ex)
            {
                throw ex;
            }
        }
    }
}
