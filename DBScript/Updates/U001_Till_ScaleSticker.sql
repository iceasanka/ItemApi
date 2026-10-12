/* =============================================================================
   U001_Till_ScaleSticker.sql   (2026-10-12)
   Update for a till db (z_pos_fnt_db) that is ALREADY deployed. SQL Server 2008 R2 and newer.
   Safe to run again. Bills, Z reports and cash data are not touched.

   What changes (scale sticker barcodes, Docs/StockSystem.md 6.14):
     - zf_tb_Item gets the column UnitCode; the till then downloads every item again on its next sync
     - zf_tt_Item / zf_sp_UpsertItems take UnitCode
     - zf_sp_FindItem reads a scale sticker: 1000801410 = scale code 10008, 1.410 kg (scale items = unit KGS only)
   Same change in the full script: 02_FrontCashier_zf.sql.

   Order: back office first (U001_BackOffice_ScaleSticker.sql + new ItemApi), then on each till:
     1. stop TillService
     2. sqlcmd -S .\SQLEXPRESS -d z_pos_fnt_db -E -I -b -i U001_Till_ScaleSticker.sql
     3. install the new TillService and start it (the old one can't download items after this script)
     4. press Reload on the billing page
   ============================================================================= */
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
IF OBJECT_ID(N'dbo.zf_tb_Item', 'U') IS NULL OR OBJECT_ID(N'dbo.zf_tb_Config', 'U') IS NULL
BEGIN
    RAISERROR('This is not a till database (zf_tb_Item / zf_tb_Config not found) - nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
GO

-- 1. column. Items already on the till have no unit yet -> download them all again.
IF COL_LENGTH('dbo.zf_tb_Item', 'UnitCode') IS NULL
BEGIN
    ALTER TABLE dbo.zf_tb_Item ADD UnitCode VARCHAR(5) NULL;               -- z_tb_Unit.UnitCode; KGS = scale item
    UPDATE dbo.zf_tb_Config SET LastItemSyncAt = NULL;
    PRINT 'zf_tb_Item.UnitCode added - all items will be downloaded again.';
END
GO

-- 2. the table type can only be replaced after the procedure that uses it is dropped
IF OBJECT_ID(N'dbo.zf_sp_UpsertItems', 'P') IS NOT NULL DROP PROCEDURE dbo.zf_sp_UpsertItems;
IF OBJECT_ID(N'dbo.zf_sp_FindItem', 'P')    IS NOT NULL DROP PROCEDURE dbo.zf_sp_FindItem;
GO
IF TYPE_ID(N'dbo.zf_tt_Item') IS NOT NULL DROP TYPE dbo.zf_tt_Item;
GO
-- same columns/order as the back-office z_sp_GetItemsForSync result (API: GET api/Sync/Items)
CREATE TYPE dbo.zf_tt_Item AS TABLE (
    ItemId          INT            NOT NULL PRIMARY KEY,
    RefCode         NVARCHAR(50)   NULL,
    Barcode         NVARCHAR(50)   NULL,
    Descrip         NVARCHAR(200)  NULL,
    Inv_Descrip     NVARCHAR(50)   NULL,
    SinhalaDescrip  NVARCHAR(200)  NULL,
    OpenPrice       BIT            NOT NULL,
    MaxPrice        DECIMAL(18,2)  NULL,
    RetailPrice     DECIMAL(18,2)  NULL,
    WholesalePrice  DECIMAL(18,2)  NULL,
    SpecialPrice    DECIMAL(18,2)  NULL,
    IsSaleLocked    BIT            NOT NULL,
    NoDiscount      BIT            NOT NULL,
    DiscountAmount  DECIMAL(18,2)  NULL,
    DiscountPercent DECIMAL(18,2)  NULL,
    QtyLevel2       DECIMAL(18,3)  NULL,
    PriceLevel2     DECIMAL(18,2)  NULL,
    QtyLevel3       DECIMAL(18,3)  NULL,
    PriceLevel3     DECIMAL(18,2)  NULL,
    QtyLevel4       DECIMAL(18,3)  NULL,
    PriceLevel4     DECIMAL(18,2)  NULL,
    Status          INT            NOT NULL,
    UDate           DATETIME2      NULL,
    CostPrice       DECIMAL(18,2)  NULL,
    UnitCode        VARCHAR(5)     NULL
);
GO

-- 3. procedures
-- Applies an item/price download. @ServerTime = serverTime from GET api/Sync/Items (next "since").
CREATE PROCEDURE dbo.zf_sp_UpsertItems
    @Items       dbo.zf_tt_Item READONLY,
    @ServerTime  DATETIME
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRAN;
        UPDATE t SET
            RefCode = s.RefCode, Barcode = s.Barcode, Descrip = s.Descrip, Inv_Descrip = s.Inv_Descrip,
            SinhalaDescrip = s.SinhalaDescrip, OpenPrice = s.OpenPrice, MaxPrice = s.MaxPrice,
            RetailPrice = s.RetailPrice, WholesalePrice = s.WholesalePrice, SpecialPrice = s.SpecialPrice,
            IsSaleLocked = s.IsSaleLocked, NoDiscount = s.NoDiscount,
            DiscountAmount = s.DiscountAmount, DiscountPercent = s.DiscountPercent,
            QtyLevel2 = s.QtyLevel2, PriceLevel2 = s.PriceLevel2, QtyLevel3 = s.QtyLevel3, PriceLevel3 = s.PriceLevel3,
            QtyLevel4 = s.QtyLevel4, PriceLevel4 = s.PriceLevel4, Status = s.Status, UDate = s.UDate,
            CostPrice = s.CostPrice, UnitCode = s.UnitCode
        FROM dbo.zf_tb_Item t JOIN @Items s ON s.ItemId = t.ItemId;

        INSERT dbo.zf_tb_Item (ItemId, RefCode, Barcode, Descrip, Inv_Descrip, SinhalaDescrip, OpenPrice, MaxPrice,
                               RetailPrice, WholesalePrice, SpecialPrice, IsSaleLocked, NoDiscount, DiscountAmount, DiscountPercent,
                               QtyLevel2, PriceLevel2, QtyLevel3, PriceLevel3, QtyLevel4, PriceLevel4, Status, UDate, CostPrice,
                               UnitCode)
        SELECT s.ItemId, s.RefCode, s.Barcode, s.Descrip, s.Inv_Descrip, s.SinhalaDescrip, s.OpenPrice, s.MaxPrice,
               s.RetailPrice, s.WholesalePrice, s.SpecialPrice, s.IsSaleLocked, s.NoDiscount, s.DiscountAmount, s.DiscountPercent,
               s.QtyLevel2, s.PriceLevel2, s.QtyLevel3, s.PriceLevel3, s.QtyLevel4, s.PriceLevel4, s.Status, s.UDate, s.CostPrice,
               s.UnitCode
        FROM @Items s WHERE NOT EXISTS (SELECT 1 FROM dbo.zf_tb_Item t WHERE t.ItemId = s.ItemId);

        UPDATE dbo.zf_tb_Config SET LastItemSyncAt = @ServerTime WHERE Id = 1;
    COMMIT;
END
GO

-- Barcode, then RefCode - or one item by @ItemId (picked from zf_sp_SearchItems). Active items only.
-- Scale sticker: when nothing matches and @Code is 10 digits, it is read as 5 digits scale code + 5 digits weight in
-- grams (1000801410 = RefCode 10008, 1.410 kg). Scale items (UnitCode KGS) only; the scale code is the RefCode padded
-- to 5 digits, same rule as the PLU in the scale export (05_BackOffice_Export.sql). Weight 00000 = not found.
-- 2 result sets: the item (with the last known stock, for display; ScaleQty = the sticker weight in kg, else NULL),
-- then its active price links (empty = sell at the normal / quantity price, no price choice).
CREATE PROCEDURE dbo.zf_sp_FindItem
    @Code   NVARCHAR(50) = NULL,
    @ItemId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ScaleQty DECIMAL(18,3);

    IF @ItemId IS NOT NULL
        SET @ItemId = (SELECT ItemId FROM dbo.zf_tb_Item WHERE ItemId = @ItemId AND Status = 1);   -- NULL if inactive / missing
    ELSE
    BEGIN
        SELECT TOP 1 @ItemId = i.ItemId
        FROM dbo.zf_tb_Item i
        WHERE (i.Barcode = @Code OR i.RefCode = @Code) AND i.Status = 1
        ORDER BY CASE WHEN i.Barcode = @Code THEN 0 ELSE 1 END;

        IF @ItemId IS NULL AND LEN(@Code) = 10 AND @Code NOT LIKE N'%[^0-9]%' AND RIGHT(@Code, 5) <> N'00000'
        BEGIN
            SELECT TOP 1 @ItemId = i.ItemId
            FROM dbo.zf_tb_Item i
            WHERE i.UnitCode = 'KGS' AND i.Status = 1
              AND i.RefCode NOT LIKE N'%[^0-9]%' AND LEN(i.RefCode) BETWEEN 1 AND 5
              AND RIGHT(N'00000' + i.RefCode, 5) = LEFT(@Code, 5)
            ORDER BY i.ItemId;

            IF @ItemId IS NOT NULL
                SET @ScaleQty = CAST(RIGHT(@Code, 5) AS INT) / 1000.0;
        END
    END

    SELECT i.*, s.Qty AS StockQty, @ScaleQty AS ScaleQty
    FROM dbo.zf_tb_Item i
    LEFT JOIN dbo.zf_tb_StockBalance s ON s.ItemId = i.ItemId
    WHERE i.ItemId = @ItemId;

    SELECT PriceLinkId, RetailPrice, WholesalePrice, Remark
    FROM dbo.zf_tb_ItemPriceLink
    WHERE ItemId = @ItemId AND Status = 1
    ORDER BY RetailPrice;
END
GO
PRINT 'U001 till: zf_tb_Item.UnitCode, zf_tt_Item, zf_sp_UpsertItems, zf_sp_FindItem updated (scale sticker barcodes).';
GO
SET NOEXEC OFF;
GO
