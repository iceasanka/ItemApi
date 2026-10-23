/* =============================================================================
   20_BackOffice_MobileGrn.sql   (2026-10-23)
   Run on: back office db (easyway). SQL Server 2008 R2 and newer. Safe to run again.
   Needs: z_tb_Item / z_tb_ItemDet / z_tb_Supplier / z_tb_StockBalance / z_tb_TempPurchase(Summary) / z_tb_System.
          Then the new ItemApi (api/MobileGrn) and the mobile app (GRN page).
   Same content as Updates/U017_BackOffice_MobileGrn.sql - change both together.

   Mobile GRN on the NEW system (StockSystem.md section 6.23). Replaces the old GrnTemp list (old item / supplier codes,
   read by the old GRN page): that table is not changed or read any more.
   The phone scans the items of a delivery into a SUSPENDED GRN (z_tb_TempPurchaseSummary Status 0, Type 1,
   UserId 'mobile') - one open draft per supplier, number GRN + z_tb_System.PNO. The back office opens it on the
   GRN Entry page (search / load), checks it, adds the supplier's invoice no, saves and commits it to stock.
   No stock moves here.
     z_sp_MobileGrnGet         the open draft of a supplier with its lines (empty = no draft)
     z_sp_MobileGrnAddLine     adds a line (the draft is made on the first one). Same item + cost + sell price -> qty added
     z_sp_MobileGrnUpdateLine  qty / cost / sell price of a line
     z_sp_MobileGrnDeleteLine  deletes a line (the last line -> the empty draft is deleted too)
   A draft stops being the phone's when the back office saves it (Status 1) or changes its user.

   sqlcmd -S <server> -d easyway -E -I -b -i 20_BackOffice_MobileGrn.sql
   ============================================================================= */
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
IF OBJECT_ID(N'dbo.z_tb_Item', 'U') IS NULL OR OBJECT_ID(N'dbo.z_tb_TempPurchaseSummary', 'U') IS NULL
   OR OBJECT_ID(N'dbo.z_tb_TempPurchase', 'U') IS NULL OR OBJECT_ID(N'dbo.z_tb_Supplier', 'U') IS NULL
BEGIN
    RAISERROR('This is not the back office database (z_tb_Item / z_tb_TempPurchaseSummary / z_tb_Supplier not found) - nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
GO

IF OBJECT_ID('dbo.z_sp_MobileGrnGet', 'P')        IS NOT NULL DROP PROCEDURE dbo.z_sp_MobileGrnGet;
IF OBJECT_ID('dbo.z_sp_MobileGrnAddLine', 'P')    IS NOT NULL DROP PROCEDURE dbo.z_sp_MobileGrnAddLine;
IF OBJECT_ID('dbo.z_sp_MobileGrnUpdateLine', 'P') IS NOT NULL DROP PROCEDURE dbo.z_sp_MobileGrnUpdateLine;
IF OBJECT_ID('dbo.z_sp_MobileGrnDeleteLine', 'P') IS NOT NULL DROP PROCEDURE dbo.z_sp_MobileGrnDeleteLine;
IF OBJECT_ID('dbo.z_sp_MobileGrnTotals', 'P')     IS NOT NULL DROP PROCEDURE dbo.z_sp_MobileGrnTotals;
GO

-- ---- (inside the others) the draft's totals from its lines
CREATE PROCEDURE dbo.z_sp_MobileGrnTotals
    @GrnNo VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Qty DECIMAL(18,3), @Amount DECIMAL(18,2);
    SELECT @Qty = ISNULL(SUM(Qty), 0), @Amount = ISNULL(SUM(GAmount), 0) FROM dbo.z_tb_TempPurchase WHERE GrnNo = @GrnNo;
    UPDATE dbo.z_tb_TempPurchaseSummary
    SET Qty = @Qty, GAmount = @Amount,
        NetAmount = @Amount - ISNULL(SubTotDisc, 0) - ISNULL(Advance, 0) - ISNULL(Returns, 0), UDate = GETDATE()
    WHERE GrnNo = @GrnNo;
END
GO

-- ---- the open draft of one supplier: one row per line (no rows = no draft yet)
CREATE PROCEDURE dbo.z_sp_MobileGrnGet
    @SuppId     INT,
    @LocationId INT = 1
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @GrnNo VARCHAR(20);
    SELECT TOP 1 @GrnNo = GrnNo FROM dbo.z_tb_TempPurchaseSummary
    WHERE SuppId = @SuppId AND Type = 1 AND Status = 0 AND UserId = 'mobile' AND ISNULL(LocationId, 1) = ISNULL(@LocationId, 1)
    ORDER BY Idx DESC;

    SELECT l.GrnNo, l.Idx, l.ItemId, i.Barcode, i.RefCode, i.Descrip,
           CAST(ISNULL(l.Qty, 0) AS DECIMAL(18,3)) AS Qty,
           CAST(ISNULL(l.CostPrice, 0) AS DECIMAL(18,2)) AS CostPrice,
           CAST(ISNULL(l.SellPrice, 0) AS DECIMAL(18,2)) AS SellPrice,
           CAST(ISNULL(l.GAmount, 0) AS DECIMAL(18,2)) AS GAmount,
           d.CostPrice AS ItemCostPrice, d.RetailPrice AS ItemRetailPrice,
           CAST(ISNULL(b.Qty, 0) AS DECIMAL(18,3)) AS StockQty,
           l.UDate
    FROM dbo.z_tb_TempPurchase l
    JOIN dbo.z_tb_Item i ON i.ItemId = l.ItemId
    LEFT JOIN dbo.z_tb_ItemDet d ON d.ItemId = l.ItemId AND d.LocationId = ISNULL(@LocationId, 1)
    LEFT JOIN dbo.z_tb_StockBalance b ON b.ItemId = l.ItemId AND b.LocationId = ISNULL(@LocationId, 1)
    WHERE l.GrnNo = @GrnNo
    ORDER BY l.Idx DESC;
END
GO

-- ---- adds a line to the supplier's open draft (makes the draft on the first line). Returns GrnNo, Idx.
CREATE PROCEDURE dbo.z_sp_MobileGrnAddLine
    @SuppId     INT,
    @ItemId     INT,
    @Qty        DECIMAL(18,3),
    @CostPrice  DECIMAL(18,2),
    @SellPrice  DECIMAL(18,2),
    @LocationId INT = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @z_tc INT; SET @z_tc = @@TRANCOUNT;
    BEGIN TRY
        DECLARE @GrnNo VARCHAR(20), @No INT, @Idx INT, @Now DATETIME, @Today DATETIME;
        SET @Now = GETDATE();
        SET @Today = CAST(CONVERT(VARCHAR(10), @Now, 120) AS DATETIME);
        SET @LocationId = ISNULL(@LocationId, 1);
        IF @Qty IS NULL OR @Qty <= 0 RAISERROR(N'%s', 16, 1, N'Enter a qty more than 0.');
        IF @CostPrice IS NULL OR @CostPrice < 0 RAISERROR(N'%s', 16, 1, N'Enter the cost price.');
        IF @SellPrice IS NULL OR @SellPrice < 0 RAISERROR(N'%s', 16, 1, N'Enter the selling price.');
        IF NOT EXISTS (SELECT 1 FROM dbo.z_tb_Item WHERE ItemId = @ItemId) RAISERROR(N'%s', 16, 1, N'Item not found.');
        IF NOT EXISTS (SELECT 1 FROM dbo.z_tb_Supplier WHERE SuppId = @SuppId) RAISERROR(N'%s', 16, 1, N'Select the supplier.');

        BEGIN TRAN;
            SELECT TOP 1 @GrnNo = GrnNo FROM dbo.z_tb_TempPurchaseSummary WITH (UPDLOCK, HOLDLOCK)
            WHERE SuppId = @SuppId AND Type = 1 AND Status = 0 AND UserId = 'mobile' AND ISNULL(LocationId, 1) = @LocationId
            ORDER BY Idx DESC;

            IF @GrnNo IS NULL
            BEGIN
                -- the next GRN number, taken and moved on in one statement (the GRN Entry page uses the same counter)
                UPDATE dbo.z_tb_System SET @No = PNO, PNO = PNO + 1 WHERE LocaId = '01';
                IF @No IS NULL RAISERROR(N'%s', 16, 1, N'GRN counter (z_tb_System.PNO) not found.');
                SET @GrnNo = 'GRN' + RIGHT('00000000' + CAST(@No AS VARCHAR(10)), 8);
                IF EXISTS (SELECT 1 FROM dbo.z_tb_TempPurchaseSummary WHERE GrnNo = @GrnNo)
                    RAISERROR(N'%s', 16, 1, N'The next GRN number is already used - try again.');
                INSERT dbo.z_tb_TempPurchaseSummary (GrnNo, LocationId, RefNo, PDate, SuppId, PMode, GAmount, SubTotDisc, NetAmount,
                                                     Advance, Returns, Qty, Status, Remark, UDate, UserId, POderNo, Type)
                VALUES (@GrnNo, @LocationId, NULL, @Today, @SuppId, 1, 0, 0, 0, 0, 0, 0, 0, 'Mobile GRN', @Now, 'mobile', NULL, 1);
            END

            SELECT TOP 1 @Idx = Idx FROM dbo.z_tb_TempPurchase WITH (UPDLOCK, HOLDLOCK)
            WHERE GrnNo = @GrnNo AND ItemId = @ItemId AND ISNULL(CostPrice, 0) = @CostPrice AND ISNULL(SellPrice, 0) = @SellPrice
            ORDER BY Idx DESC;

            IF @Idx IS NOT NULL
                UPDATE dbo.z_tb_TempPurchase
                SET Qty = Qty + @Qty, GAmount = (Qty + @Qty) * @CostPrice - ISNULL(Discount, 0), UDate = @Now
                WHERE Idx = @Idx;
            ELSE
            BEGIN
                INSERT dbo.z_tb_TempPurchase (GrnNo, LocationId, ItemId, PDate, CostPrice, SellPrice, Qty, Discount, GAmount, Status, UDate, UserId)
                VALUES (@GrnNo, @LocationId, @ItemId, @Today, @CostPrice, @SellPrice, @Qty, 0, @Qty * @CostPrice, 1, @Now, 'mobile');
                SET @Idx = SCOPE_IDENTITY();
            END

            EXEC dbo.z_sp_MobileGrnTotals @GrnNo = @GrnNo;
        COMMIT;
        SELECT @GrnNo AS GrnNo, @Idx AS Idx;
    END TRY
    BEGIN CATCH
        DECLARE @z_msg NVARCHAR(2048); SET @z_msg = ERROR_MESSAGE();
        IF @z_tc = 0 BEGIN IF XACT_STATE() <> 0 ROLLBACK; END
        ELSE BEGIN WHILE @@TRANCOUNT > @z_tc AND XACT_STATE() = 1 COMMIT; END
        RAISERROR(N'%s', 16, 1, @z_msg);
        RETURN 1;
    END CATCH
END
GO

-- ---- qty / cost / sell price of a line of a draft that is still the phone's
CREATE PROCEDURE dbo.z_sp_MobileGrnUpdateLine
    @Idx        INT,
    @Qty        DECIMAL(18,3),
    @CostPrice  DECIMAL(18,2),
    @SellPrice  DECIMAL(18,2)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @z_tc INT; SET @z_tc = @@TRANCOUNT;
    BEGIN TRY
        DECLARE @GrnNo VARCHAR(20);
        IF @Qty IS NULL OR @Qty <= 0 RAISERROR(N'%s', 16, 1, N'Enter a qty more than 0.');
        IF @CostPrice IS NULL OR @CostPrice < 0 RAISERROR(N'%s', 16, 1, N'Enter the cost price.');
        IF @SellPrice IS NULL OR @SellPrice < 0 RAISERROR(N'%s', 16, 1, N'Enter the selling price.');
        SELECT @GrnNo = l.GrnNo FROM dbo.z_tb_TempPurchase l
        JOIN dbo.z_tb_TempPurchaseSummary s ON s.GrnNo = l.GrnNo AND s.Status = 0 AND s.Type = 1 AND s.UserId = 'mobile'
        WHERE l.Idx = @Idx;
        IF @GrnNo IS NULL RAISERROR(N'%s', 16, 1, N'Line not found, or the GRN was already taken over by the back office.');

        BEGIN TRAN;
            UPDATE dbo.z_tb_TempPurchase
            SET Qty = @Qty, CostPrice = @CostPrice, SellPrice = @SellPrice, GAmount = @Qty * @CostPrice - ISNULL(Discount, 0),
                UDate = GETDATE()
            WHERE Idx = @Idx;
            EXEC dbo.z_sp_MobileGrnTotals @GrnNo = @GrnNo;
        COMMIT;
        SELECT @GrnNo AS GrnNo, @Idx AS Idx;
    END TRY
    BEGIN CATCH
        DECLARE @z_msg NVARCHAR(2048); SET @z_msg = ERROR_MESSAGE();
        IF @z_tc = 0 BEGIN IF XACT_STATE() <> 0 ROLLBACK; END
        ELSE BEGIN WHILE @@TRANCOUNT > @z_tc AND XACT_STATE() = 1 COMMIT; END
        RAISERROR(N'%s', 16, 1, @z_msg);
        RETURN 1;
    END CATCH
END
GO

-- ---- deletes a line; the draft goes too when it has no lines left
CREATE PROCEDURE dbo.z_sp_MobileGrnDeleteLine
    @Idx INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @z_tc INT; SET @z_tc = @@TRANCOUNT;
    BEGIN TRY
        DECLARE @GrnNo VARCHAR(20), @Left INT;
        SELECT @GrnNo = l.GrnNo FROM dbo.z_tb_TempPurchase l
        JOIN dbo.z_tb_TempPurchaseSummary s ON s.GrnNo = l.GrnNo AND s.Status = 0 AND s.Type = 1 AND s.UserId = 'mobile'
        WHERE l.Idx = @Idx;
        IF @GrnNo IS NULL RAISERROR(N'%s', 16, 1, N'Line not found, or the GRN was already taken over by the back office.');

        BEGIN TRAN;
            DELETE dbo.z_tb_TempPurchase WHERE Idx = @Idx;
            SELECT @Left = COUNT(*) FROM dbo.z_tb_TempPurchase WHERE GrnNo = @GrnNo;
            IF @Left = 0
                DELETE dbo.z_tb_TempPurchaseSummary WHERE GrnNo = @GrnNo AND Status = 0;
            ELSE
                EXEC dbo.z_sp_MobileGrnTotals @GrnNo = @GrnNo;
        COMMIT;
        SELECT @GrnNo AS GrnNo, @Left AS LinesLeft;
    END TRY
    BEGIN CATCH
        DECLARE @z_msg NVARCHAR(2048); SET @z_msg = ERROR_MESSAGE();
        IF @z_tc = 0 BEGIN IF XACT_STATE() <> 0 ROLLBACK; END
        ELSE BEGIN WHILE @@TRANCOUNT > @z_tc AND XACT_STATE() = 1 COMMIT; END
        RAISERROR(N'%s', 16, 1, @z_msg);
        RETURN 1;
    END CATCH
END
GO
PRINT 'U017 back office: mobile GRN drafts are ready.';
GO
SET NOEXEC OFF;
GO
