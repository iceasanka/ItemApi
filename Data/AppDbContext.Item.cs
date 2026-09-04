using Microsoft.EntityFrameworkCore;
using ItemApi.Models;
using Serilog;

namespace ItemApi.Data
{
    // Item / ItemDetail (tb_Item, tb_ItemDet) — consolidated from the former ItemContext.
    // NOTE: this is a different table/entity family from Itemz (z_tb_Item) in AppDbContext.Itemz.cs —
    // kept deliberately separate, do not merge the two.
    public partial class AppDbContext
    {
        public DbSet<Item> Items { get; set; }

        public DbSet<ItemDetail> ItemDetails { get; set; }

        public DbSet<UpdateItemSp> updateItemSp { get; set; }

        public DbSet<ItemWithDetails> ItemWithDetails { get; set; }
        public DbSet<PriceLink> PriceLinks { get; set; }

        partial void ConfigureItem(ModelBuilder modelBuilder)
        {
            modelBuilder.Entity<Item>().ToTable("tb_Item");
            modelBuilder.Entity<ItemDetail>().ToTable("tb_ItemDet");
            modelBuilder.Entity<ItemWithDetails>().HasNoKey();
            modelBuilder.Entity<PriceLink>().HasNoKey();
            modelBuilder.Entity<UpdateItemSp>().HasNoKey();
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
                Log.Error($"Error fetching item details: {ex.Message}");
                throw ex;
            }
        }

        public async Task<ItemWithDetails> GetItemWithDetailsByRefCodeAsync(string refCode)
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
                AND tb_item.ref_code = {0}";

            try
            {
                return await ItemWithDetails.FromSqlRaw(sql, refCode).FirstOrDefaultAsync();
            }
            catch (Exception ex)
            {
                Log.Error($"Error fetching item details: {ex.Message}");
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
                Log.Error($"Error: {ex.Message}");
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
                Log.Error($"Error: {ex.Message}");

                throw ex;
            }
        }

        public async Task<int> UpdatePriceLink(PriceLinkUpdateDTO dto)
        {
            string sql = @"
        EXEC [dbo].[Sp_UpdatePriceLink]
            @ITEMCODE = @p0,
            @ITEMDESCRIP = @p1,
            @LOCA = @p2,
            @USERNAME = @p3,
            @STATUS = @p4,
            @PRICE = @p5,
            @COSTPRICE = @p6,
            @PACKSIZE = @p7,
            @EWHOLEPRICE = @p8,
            @PRETPRICE = @p9,
            @PWHOLEPRICE = @p10,
            @ISUPDATEALLLOCATION = @p11";

            try
            {
                return await this.Database.ExecuteSqlRawAsync(sql,
                    dto.ItemCode,
                    dto.ItemDescrip,
                    dto.Loca,
                    dto.UserName,
                    dto.Status,
                    dto.Price,
                    dto.CostPrice,
                    dto.PackSize,
                    dto.EWholePrice,
                    dto.PRetPrice,
                    dto.PWholePrice,
                    dto.IsUpdateAllLocation);
            }
            catch (Exception ex)
            {
                Log.Error($"Error updating PriceLink: {ex.Message}");
                throw;
            }
        }

        public async Task<int> UpdateItemRetPrice(string itemCode, decimal newERetPrice)
        {
            try
            {
                string sql = @"SELECT TOP 1
                    i.Item_Code AS ItemCode,
                    i.Ref_Code AS RefCode,
                    i.Barcode AS BarCode,
                    i.Inv_Descrip AS InvDescription,
                    i.Descrip AS Description,
                    i.SinhalaDescrip AS SinhalaDescription,
                    i.Cat_Code AS CatCode,
                    i.SubCat_Code AS SubCatCode,
                    i.L1_Code AS L1Code,
                    i.L2_Code AS L2Code,
                    i.L3_Code AS L3Code,
                    i.L4_Code AS L4Code,
                    i.L5_Code AS L5Code,
                    i.L6_Code AS L6Code,
                    i.L7_Code AS L7Code,
                    i.Supp_Code AS SupplierCode,
                    i.Pack_Size AS PackSize,
                    i.W_Margine AS MarginWholeSale,
                    i.R_Margine AS MarginRetail,
                    i.PUnit AS UnitOfPack,
                    i.EUnit AS UnitOfEach,
                    i.Tax1,
                    i.MaxPrice,
                    CAST(i.Tax2 AS decimal(18,2)) AS Tax2,
                    CAST(i.Tax3 AS decimal(18,2)) AS Tax3,
                    i.Countable,
                    i.Consign,
                    i.ConvertFact,
                    i.ConvertFactUnit,
                    i.isCombined AS IsCombine,
                    i.isTaxApply AS TaxApply,
                    i.isNbtApply AS NbtApply,
                    i.ComRate,
                    i.ItemType,
                    i.OpenPrice AS UseOpenPrice,
                    i.QrCodeDescrip,
                    i.Use_Exp,

                    d.ERet_Price AS EachRetail,
                    d.EWhole_Price AS EachWholeSale,
                    d.PRet_Price AS PackRetail,
                    d.PWhole_Price AS PackWholeSale,
                    d.Cost_Price AS CostPrice,
                    d.AvgCost,
                    d.Cost_Code AS CostCode,
                    d.Lock_S AS LockedForSale,
                    d.Lock_P AS LockedForPurchase,
                    d.NoDiscount,
                    d.BinNo AS BinLocation,
                    d.C_Price AS CCPrice,
                    d.Re_Qty AS ReOrderQty,
                    d.Rol AS ReOrderLevel,

                    d.SPQ AS SecondPriceQty,
                    d.SPR AS SecondPriceRate,
                    d.TPQ AS ThirdPriceQty,
                    d.TPR AS ThirdPriceRate,
                    d.FPQ AS FourthPriceQty,
                    d.FPR AS FourthPriceRate,
                    d.FIPQ AS FifthPriceQty,
                    d.FIPR AS FifthPriceRate,
                    d.SIPQ AS SixthPriceQty,
                    d.SIPR AS SixthPriceRate,
                    d.SEPQ AS SeventhPriceQty,
                    d.SEPR AS SeventhPriceRate,
                    d.EIPQ AS EightthPriceQty,
                    d.EIPR AS EightthPriceRate,
                    d.Commission,

                    d.User_Id AS UserId,
                    d.Loca_Code AS LocaCode,
                    '' AS CatName,
                    '' AS SubCatName,
                    '' AS L1Name,
                    '' AS L2Name,
                    '' AS L3Name,
                    '' AS L4Name,
                    '' AS L5Name,
                    '' AS L6Name,
                    '' AS L7Name,
                    '' AS SupplierName,
                    '' AS DateCreated,
                    '' AS LastModified,
                    '' AS LastModifiedBy,
                    '' AS QtyPurchased,
                    '' AS DatePurchased,
                    '' AS QtySold,
                    '' AS DateSold,
                    0.0 AS StockThisLocation,
                    0.0 AS StockAllLocations,
                    NULL AS Type,
                    NULL AS CsCode,
                    NULL AS Price,
                    NULL AS SerialNo
                FROM tb_Item i
                JOIN tb_ItemDet d ON i.Item_Code = d.Item_Code
                WHERE d.Loca_Code = '01' AND i.Item_Code = {0}
                ";

               var item = await updateItemSp.FromSqlRaw(sql, itemCode).FirstOrDefaultAsync();

                if (item.eachRetail == newERetPrice)
                    return 0; // No update needed

                item.eachRetail = newERetPrice; // Apply new price

                // Call SP
                var sql2 = @"
                    EXEC [dbo].[Sp_ITEM_UPDATE_PRL]
                        @ERR_SQL = {0},
                        @LOCA_CODE = {1},
                        @ITEM_CODE = {2},
                        @BARCODE = {3},
                        @REF_CODE = {4},
                        @INV_DESCRIPTION = {5},
                        @DESCRIPTION = {6},
                        @SINHALADESCRIP = {7},
                        @SUPP_CODE = {8},
                        @CAT_CODE = {9},
                        @SUBCAT_CODE = {10},
                        @L1_CODE = {11},
                        @L2_CODE = {12},
                        @L3_CODE = {13},
                        @L4_CODE = {14},
                        @L5_CODE = {15},
                        @L6_CODE = {16},
                        @L7_CODE = {17},
                        @PACK_SIZE = {18},
                        @COST_PRICE = {19},
                        @R_MARGINE = {20},
                        @W_MARGINE = {21},
                        @ERET_PRICE = {22},
                        @EWHOLE_PRICE = {23},
                        @E_UNIT = {24},
                        @PRET_PRICE = {25},
                        @PWHOLE_PRICE = {26},
                        @P_UNIT = {27},
                        @ROL = {28},
                        @RE_QTY = {29},
                        @COST_CODE = {30},
                        @LOCK_S = {31},
                        @LOCK_P = {32},
                        @TAX1 = {33},
                        @TAX2 = {34},
                        @TAX3 = {35},
                        @USER_ID = {36},
                        @STATUS = {37},
                        @COUNTABLE = {38},
                        @BINNO = {39},
                        @COMRATE = {40},
                        @ITEMTYPE = {41},
                        @CONFACT = {42},
                        @CONFACTUNIT = {43},
                        @NODISCOUNT = {44},
                        @USEEXP = {45},
                        @SP_QTY = {46},
                        @SPRICE = {47},
                        @TP_QTY = {48},
                        @TPRICE = {49},
                        @FP_QTY = {50},
                        @FPRICE = {51},
                        @CONS = {52},
                        @FIPQ = {53},
                        @FIPR = {54},
                        @SIPQ = {55},
                        @SIPR = {56},
                        @SEPQ = {57},
                        @SEPR = {58},
                        @EIPQ = {59},
                        @EIPR = {60},
                        @PRICETYPE = {61},
                        @MAXPRICE = {62},
                        @ISCOMBINED = {63},
                        @ISTAXAPPLY = {64},
                        @Commission = {65},
                        @ISNBTAPPLY = {66},
                        @QrCodeDescrip = {67},
                        @CreditCustomerPrice = {68}";

                await this.Database.ExecuteSqlRawAsync(sql2,
                    0, // ERR_SQL
                    item.locaCode,
                    item.ItemCode,
                    item.barCode,
                    item.refCode,
                    item.invDescription,
                    item.description,
                    item.sinhalaDescription ?? "",
                    item.supplierCode,
                    item.catCode,
                    item.subCatCode,
                    item.l1Code ?? "",
                    item.l2Code ?? "",
                    item.l3Code ?? "",
                    item.l4Code ?? "",
                    item.l5Code ?? "",
                    item.l6Code ?? "",
                    item.l7Code ?? "",
                    item.packSize,
                    item.costPrice,
                    item.marginRetail ?? "0.0000",
                    item.marginWholeSale ?? "0.0000",
                    item.eachRetail,
                    item.eachWholeSale,
                    item.unitOfEach ?? "NOS",
                    item.packRetail,
                    item.packWholeSale,
                    item.unitOfPack ?? "NOS",
                    item.reOrderLevel,                      // ROL
                   item.reOrderQty,                      // RE_QTY
                    item.costCode ?? "",
                    item.lockedForSale,
                    item.lockedForPurchase,
                    item.tax1,
                    item.tax2,
                    item.tax3,
                    item.userId ?? "EASYWAY",
                    1,                      // STATUS
                    item.countable,
                    item.binLocation ?? "",
                    item.comRate,
                    item.itemType,
                    item.convertFact,
                    item.convertFactUnit ?? "NOS",
                    item.noDiscount,
                    item.Use_Exp,                      // USEEXP
                    item.secondPriceQty,
                    item.secondPriceRate,
                    item.thirdPriceQty,
                    item.thirdPriceRate,
                    item.fourthPriceQty,
                    item.fourthPriceRate,
                    item.consign,
                    item.fifthPriceQty,
                    item.fifthPriceRate,
                    item.sixthPriceQty,
                    item.sixthPriceRate,
                    item.seventhPriceQty,
                    item.seventhPriceRate,
                    item.eightthPriceQty,
                    item.eightthPriceRate,
                    item.useOpenPrice,                      // PRICETYPE
                    item.maxPrice,
                    item.isCombine,
                    item.taxApply,
                    item.commission ?? "0.00",
                    item.nbtApply,
                    item.QrCodeDescrip ?? "",
                    item.ccPrice
                );



                // success
                return 1;
            }
            catch (Exception ex)
            {
                Log.Error($"UpdateItemRetPrice error: {ex.Message}");
                throw;
            }
        }
    }
}
