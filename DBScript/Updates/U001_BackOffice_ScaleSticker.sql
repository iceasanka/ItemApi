/* =============================================================================
   U001_BackOffice_ScaleSticker.sql   (2026-10-12)
   Update for a back office db (easyway) that is ALREADY deployed. SQL Server 2008 R2 and newer.
   Safe to run again (drops and creates the procedure). No table or data is changed.

   What changes: z_sp_GetItemsForSync also sends the item's UnitCode to the tills
                 (KGS = scale item; the till reads the weight from the scale sticker barcode).
   Same change in the full script: 01_BackOffice_Stock.sql. See Docs/StockSystem.md 6.14.

   Run:  sqlcmd -S <server> -d easyway -E -I -b -i U001_BackOffice_ScaleSticker.sql
   Then: deploy the new ItemApi, then run U001_Till_ScaleSticker.sql on each till.
   ============================================================================= */
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
IF OBJECT_ID(N'dbo.z_tb_Item', 'U') IS NULL OR OBJECT_ID(N'dbo.z_tb_Unit', 'U') IS NULL
BEGIN
    RAISERROR('This is not the back office database (z_tb_Item / z_tb_Unit not found) - nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
GO
IF OBJECT_ID(N'dbo.z_sp_GetItemsForSync') IS NOT NULL DROP PROCEDURE dbo.z_sp_GetItemsForSync;
GO
-- Items + prices for a till, changed since @Since (NULL = everything).
-- Caller should take the server time BEFORE calling and use it as the next @Since.
CREATE PROCEDURE dbo.z_sp_GetItemsForSync
    @TerminalId INT,
    @Since      DATETIME = NULL
AS
BEGIN
    DECLARE @z_tc INT; SET @z_tc = @@TRANCOUNT;   -- SQL 2008 R2 error handling (RAISERROR in TRY/CATCH)
    BEGIN TRY
    SET NOCOUNT ON;

    DECLARE @LocationId INT;
    SELECT @LocationId = LocationId FROM dbo.z_tb_Terminal WHERE TerminalId = @TerminalId AND Status = 1;
    IF @LocationId IS NULL
        RAISERROR(N'%s', 16, 1, N'Terminal is not registered or is disabled.');

    SELECT i.ItemId, i.RefCode, i.Barcode, i.Descrip, i.Inv_Descrip, i.SinhalaDescrip,
           CAST(ISNULL(i.OpenPrice, 0) AS BIT) AS OpenPrice, i.MaxPrice,
           d.RetailPrice, d.WholesalePrice, d.SpecialPrice,
           CAST(ISNULL(d.IsSaleLocked, 0) AS BIT) AS IsSaleLocked,
           CAST(ISNULL(d.NoDiscount, 0) AS BIT)   AS NoDiscount,
           d.DiscountAmount, d.DiscountPercent,
           d.QtyLevel2, d.PriceLevel2, d.QtyLevel3, d.PriceLevel3, d.QtyLevel4, d.PriceLevel4,
           i.Status,
           CASE WHEN d.UDate > i.UDate THEN d.UDate ELSE i.UDate END AS UDate,  -- datetime2: some items have 0001-01-01
           d.CostPrice,  -- till profit view + bill discount cap (shown on the till only with the supervisor PIN)
           u.UnitCode    -- KGS = scale item: the till reads the weight from the scale sticker barcode (zf_sp_FindItem)
    FROM dbo.z_tb_Item i
    LEFT JOIN dbo.z_tb_ItemDet d ON d.ItemId = i.ItemId AND d.LocationId = @LocationId
    LEFT JOIN dbo.z_tb_Unit u ON u.UnitId = d.UnitId
    WHERE @Since IS NULL OR i.UDate > @Since OR d.UDate > @Since;

    UPDATE dbo.z_tb_Terminal SET LastItemSyncAt = GETDATE() WHERE TerminalId = @TerminalId;
    END TRY
    BEGIN CATCH
        DECLARE @z_msg NVARCHAR(2048); SET @z_msg = ERROR_MESSAGE();
        IF @z_tc = 0
        BEGIN
            IF XACT_STATE() <> 0 ROLLBACK;
        END
        ELSE
        BEGIN
            -- called inside the caller's transaction: give its level back, the caller's CATCH rolls back
            WHILE @@TRANCOUNT > @z_tc AND XACT_STATE() = 1 COMMIT;
        END
        RAISERROR(N'%s', 16, 1, @z_msg);
        RETURN 1;
    END CATCH
END
GO
PRINT 'U001 back office: z_sp_GetItemsForSync updated (sends UnitCode).';
GO
SET NOEXEC OFF;
GO
