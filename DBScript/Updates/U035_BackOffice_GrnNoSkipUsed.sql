/* =============================================================================
   U035_BackOffice_GrnNoSkipUsed.sql   (2026-10-30)
   Update for the back office db (easyway) that is ALREADY deployed. SQL Server 2008 R2 and newer.
   Safe to run again. No data is changed (one procedure made again). Needs U033_BackOffice_GrnScanFreeQty.sql.

   What changes (GRN numbers, Docs/StockSystem.md 6.31):
     - z_sp_GrnScanMakeDraft: a GRN number already used (on z_tb_TempPurchaseSummary or z_tb_TempPurchase) is skipped
       and the next one taken, instead of "The next GRN number is already used - try again." (GRN Entry used to save
       with the number its page showed, so with two tabs / browsers open, or a scan made meanwhile, the counter could
       point at a used number). The new ItemApi takes the GRN Entry number from the counter on save the same way.
   Same procedure in the full script: 25_BackOffice_GrnScan.sql (section 4).

   Order: any (the old and the new ItemApi both work with it).
   ============================================================================= */
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
IF OBJECT_ID(N'dbo.z_tb_TempPurchase', 'U') IS NULL OR OBJECT_ID(N'dbo.z_tb_Supplier', 'U') IS NULL
BEGIN
    RAISERROR('This is not the back office database (z_tb_TempPurchase / z_tb_Supplier not found) - nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
GO
IF TYPE_ID(N'dbo.z_tt_GrnScanDraftLine') IS NULL OR COL_LENGTH(N'dbo.z_tb_TempPurchase', N'FreeQty') IS NULL
BEGIN
    RAISERROR('Run U033_BackOffice_GrnScanFreeQty.sql first - nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
GO
IF OBJECT_ID(N'dbo.z_sp_GrnScanMakeDraft', 'P') IS NOT NULL DROP PROCEDURE dbo.z_sp_GrnScanMakeDraft;
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
    DECLARE @GrnNo VARCHAR(20), @No INT, @Tries INT, @Now DATETIME, @Today DATETIME, @Other VARCHAR(20), @Msg NVARCHAR(400);
    SET @Now = GETDATE();
    SET @Today = CAST(CONVERT(VARCHAR(10), @Now, 120) AS DATETIME);
    SET @LocationId = ISNULL(@LocationId, 1);
    SET @RefNo = NULLIF(LTRIM(RTRIM(@RefNo)), '');

    IF NOT EXISTS (SELECT 1 FROM dbo.z_tb_Supplier WHERE SuppId = @SuppId)
        RAISERROR(N'%s', 16, 1, N'Supplier not found.');
    IF NOT EXISTS (SELECT 1 FROM @Lines)
        RAISERROR(N'%s', 16, 1, N'No lines to put on the GRN.');
    IF EXISTS (SELECT 1 FROM @Lines WHERE Qty <= 0 OR CostPrice < 0 OR SellPrice < 0 OR GAmount < 0
                                       OR FreeQty < 0 OR FreeQty > Qty)
        RAISERROR(N'%s', 16, 1, N'A line has no qty, free qty above its qty, or a cost / price / amount below 0.');
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
        -- the next GRN number, taken and moved on in one statement (GRN Entry and the mobile GRN use the same counter);
        -- a number already on a GRN (e.g. saved from a GRN Entry tab with the number it showed) is skipped (U035)
        SET @Tries = 0;
        WHILE 1 = 1
        BEGIN
            SET @No = NULL;
            UPDATE dbo.z_tb_System SET @No = PNO, PNO = PNO + 1 WHERE LocaId = '01';
            IF @No IS NULL RAISERROR(N'%s', 16, 1, N'GRN counter (z_tb_System.PNO) not found.');
            SET @GrnNo = 'GRN' + RIGHT('00000000' + CAST(@No AS VARCHAR(10)), 8);
            IF NOT EXISTS (SELECT 1 FROM dbo.z_tb_TempPurchaseSummary WHERE GrnNo = @GrnNo)
               AND NOT EXISTS (SELECT 1 FROM dbo.z_tb_TempPurchase WHERE GrnNo = @GrnNo) BREAK;
            SET @Tries = @Tries + 1;
            IF @Tries >= 1000 RAISERROR(N'%s', 16, 1, N'No free GRN number found - check z_tb_System.PNO.');
        END

        INSERT dbo.z_tb_TempPurchase (GrnNo, LocationId, ItemId, PDate, CostPrice, SellPrice, Qty, FreeQty, Discount, GAmount,
                                      Status, UDate, UserId)
        SELECT @GrnNo, @LocationId, l.ItemId, @Today, ISNULL(l.CostPrice, ISNULL(d.CostPrice, 0)),
               ISNULL(l.SellPrice, ISNULL(d.RetailPrice, 0)), l.Qty, NULLIF(l.FreeQty, 0), 0, l.GAmount, 1, @Now, 'scan'
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

PRINT 'U035_BackOffice_GrnNoSkipUsed done.';
GO
SET NOEXEC OFF;
GO
