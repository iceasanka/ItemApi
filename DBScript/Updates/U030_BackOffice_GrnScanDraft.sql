/* =============================================================================
   U030_BackOffice_GrnScanDraft.sql   (2026-10-29)
   Update for the back office db (easyway) that is ALREADY deployed. SQL Server 2008 R2 and newer.
   Safe to run again. No data is changed (one new procedure and type). Needs U029_BackOffice_GrnScan.sql.

   What changes (GRN scan step 3 - a GRN draft from a scanned invoice, Docs/StockSystem.md 6.31):
     - type z_tt_GrnScanDraftLine, procedure z_sp_GrnScanMakeDraft: the confirmed lines become a NEW suspended GRN
       (Status 0, UserId 'scan', next GRN number), opened, checked and committed on GRN Entry as usual. Cost a piece =
       (gross - line discount) / (qty + free qty). The same supplier invoice no on another GRN is refused unless the
       page confirms it.
   Same objects in the full script: 25_BackOffice_GrnScan.sql (section 4).

   Order: this script, then the new ItemApi (the old ItemApi keeps working after it), then the back office UI.
   ============================================================================= */
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
IF OBJECT_ID(N'dbo.z_tb_TempPurchaseSummary', 'U') IS NULL OR OBJECT_ID(N'dbo.z_tb_Supplier', 'U') IS NULL
BEGIN
    RAISERROR('This is not the back office database (z_tb_TempPurchaseSummary / z_tb_Supplier not found) - nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
GO
IF OBJECT_ID(N'dbo.z_tb_SupplierItemMap', 'U') IS NULL
BEGIN
    RAISERROR('Run U029_BackOffice_GrnScan.sql first - nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
GO

-- 4. GRN draft from a scan (U030)
-- The confirmed lines of a scanned invoice become a NEW suspended GRN (z_tb_TempPurchaseSummary Status 0, Type 1,
-- UserId 'scan', number GRN + z_tb_System.PNO like GRN Entry / the mobile GRN). The back office opens it on GRN Entry,
-- checks it and commits it to stock as usual. No stock or price moves here.
--   CostPrice = what one piece really costs: (gross - line discount) / (qty + free qty), as the GRN commit takes the
--   line CostPrice for the stock cost (free goods and the scheme discount lower the cost of every piece).
--   GAmount = the invoice line amount after its discount. SellPrice NULL = the item's selling price now.
--   The same supplier invoice no on another GRN is refused (state 2) unless @AllowSameRef = 1.
IF OBJECT_ID(N'dbo.z_sp_GrnScanMakeDraft', 'P') IS NOT NULL DROP PROCEDURE dbo.z_sp_GrnScanMakeDraft;
GO
IF TYPE_ID(N'dbo.z_tt_GrnScanDraftLine') IS NOT NULL DROP TYPE dbo.z_tt_GrnScanDraftLine;
GO
CREATE TYPE dbo.z_tt_GrnScanDraftLine AS TABLE (
    LineKey   INT           NOT NULL PRIMARY KEY,   -- order on the invoice
    ItemId    INT           NOT NULL,
    Qty       DECIMAL(18,2) NOT NULL,               -- pieces bought + free
    CostPrice DECIMAL(18,2) NOT NULL,               -- a piece
    SellPrice DECIMAL(18,2) NULL,                   -- NULL = the item's selling price now
    GAmount   DECIMAL(18,2) NOT NULL                -- the invoice line amount after its discount
);
GO
CREATE PROCEDURE dbo.z_sp_GrnScanMakeDraft
    @SuppId       INT,
    @RefNo        VARCHAR(30) = NULL,              -- the supplier's invoice no
    @Remark       VARCHAR(200) = NULL,
    @Lines        dbo.z_tt_GrnScanDraftLine READONLY,
    @AllowSameRef BIT = 0,
    @LocationId   INT = 1
AS
BEGIN
    DECLARE @z_tc INT; SET @z_tc = @@TRANCOUNT;   -- SQL 2008 R2 error handling (RAISERROR in TRY/CATCH)
    BEGIN TRY
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @GrnNo VARCHAR(20), @No INT, @Now DATETIME, @Today DATETIME, @Other VARCHAR(20), @Msg NVARCHAR(400);
    SET @Now = GETDATE();
    SET @Today = CAST(CONVERT(VARCHAR(10), @Now, 120) AS DATETIME);
    SET @LocationId = ISNULL(@LocationId, 1);
    SET @RefNo = NULLIF(LTRIM(RTRIM(@RefNo)), '');

    IF NOT EXISTS (SELECT 1 FROM dbo.z_tb_Supplier WHERE SuppId = @SuppId)
        RAISERROR(N'%s', 16, 1, N'Supplier not found.');
    IF NOT EXISTS (SELECT 1 FROM @Lines)
        RAISERROR(N'%s', 16, 1, N'No lines to put on the GRN.');
    IF EXISTS (SELECT 1 FROM @Lines WHERE Qty <= 0 OR CostPrice < 0 OR SellPrice < 0 OR GAmount < 0)
        RAISERROR(N'%s', 16, 1, N'A line has no qty, or a cost / price / amount below 0.');
    IF EXISTS (SELECT 1 FROM @Lines l WHERE NOT EXISTS (SELECT 1 FROM dbo.z_tb_Item i WHERE i.ItemId = l.ItemId AND i.Status = 1))
        RAISERROR(N'%s', 16, 1, N'An item of these lines is not found or not active.');
    IF @RefNo IS NOT NULL AND ISNULL(@AllowSameRef, 0) = 0
    BEGIN
        SELECT TOP 1 @Other = GrnNo FROM dbo.z_tb_TempPurchaseSummary
        WHERE SuppId = @SuppId AND RefNo = @RefNo AND Type = 1 ORDER BY Idx DESC;
        IF @Other IS NOT NULL
        BEGIN
            SET @Msg = N'Invoice ' + @RefNo + N' of this supplier is already on ' + @Other + N'.';
            RAISERROR(N'%s', 16, 2, @Msg);   -- state 2 = the page may ask "make it anyway?"
        END
    END

    BEGIN TRAN;
        -- the next GRN number, taken and moved on in one statement (GRN Entry and the mobile GRN use the same counter)
        UPDATE dbo.z_tb_System SET @No = PNO, PNO = PNO + 1 WHERE LocaId = '01';
        IF @No IS NULL RAISERROR(N'%s', 16, 1, N'GRN counter (z_tb_System.PNO) not found.');
        SET @GrnNo = 'GRN' + RIGHT('00000000' + CAST(@No AS VARCHAR(10)), 8);
        IF EXISTS (SELECT 1 FROM dbo.z_tb_TempPurchaseSummary WHERE GrnNo = @GrnNo)
            RAISERROR(N'%s', 16, 1, N'The next GRN number is already used - try again.');

        INSERT dbo.z_tb_TempPurchase (GrnNo, LocationId, ItemId, PDate, CostPrice, SellPrice, Qty, Discount, GAmount, Status, UDate, UserId)
        SELECT @GrnNo, @LocationId, l.ItemId, @Today, l.CostPrice, ISNULL(l.SellPrice, ISNULL(d.RetailPrice, 0)), l.Qty, 0, l.GAmount,
               1, @Now, 'scan'
        FROM @Lines l
        LEFT JOIN dbo.z_tb_ItemDet d ON d.ItemId = l.ItemId AND d.LocationId = @LocationId
        ORDER BY l.LineKey;

        INSERT dbo.z_tb_TempPurchaseSummary (GrnNo, LocationId, RefNo, PDate, SuppId, PMode, GAmount, SubTotDisc, NetAmount,
                                             Advance, Returns, Qty, Status, Remark, UDate, UserId, POderNo, Type)
        SELECT @GrnNo, @LocationId, @RefNo, @Today, @SuppId, 1, SUM(GAmount), 0, SUM(GAmount), 0, 0, SUM(Qty), 0,
               ISNULL(NULLIF(LTRIM(RTRIM(@Remark)), ''), 'GRN scan'), @Now, 'scan', NULL, 1
        FROM @Lines;
    COMMIT;
    SELECT @GrnNo AS GrnNo, COUNT(*) AS Lines, SUM(Qty) AS Qty, SUM(GAmount) AS Amount FROM @Lines;
    END TRY
    BEGIN CATCH
        DECLARE @z_msg NVARCHAR(2048), @z_state INT; SET @z_msg = ERROR_MESSAGE(); SET @z_state = ERROR_STATE();
        IF @z_tc = 0
        BEGIN
            IF XACT_STATE() <> 0 ROLLBACK;
        END
        ELSE
        BEGIN
            -- called inside the caller's transaction: give its level back, the caller's CATCH rolls back
            WHILE @@TRANCOUNT > @z_tc AND XACT_STATE() = 1 COMMIT;
        END
        RAISERROR(N'%s', 16, @z_state, @z_msg);
        RETURN 1;
    END CATCH
END
GO

PRINT 'U030_BackOffice_GrnScanDraft done.';
GO
