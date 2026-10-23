/* =============================================================================
   19_BackOffice_ReturnList.sql   (2026-10-23) - full script for a new install.
   Run on: back office db (easyway). SQL Server 2008 R2 and newer. Safe to run again.
   Needs: z_tb_Item / z_tb_ItemDet / z_tb_Supplier / z_tb_StockBalance / z_tb_TempPurchase(Summary) / z_tb_System,
          z_sp_PostPrn. Then the new ItemApi, the back office UI (Return Items page) and the mobile app (Return page).
   Deployed databases get the same file as DBScript/Updates/U016_BackOffice_ReturnList.sql - change both together.

   Return Items list on the NEW system (StockSystem.md section 6.22). Replaces the old z_tb_ReturnItem list (old
   item / supplier codes, processed into the old tb_Purchase): that table is not changed or read any more.
     z_tb_ReturnList   items waiting to go back to a supplier. Added by scanning on the mobile app or on the
                       Return Items page. Status 1 Added, 2 Ready (checked / packed for the supplier),
                       3 PRN made (PrnNo set - the row stays as history). Same item + supplier still "Added" -> the qty
                       is added to that row.
     z_tt_IdList       a list of ids
     z_sp_GetReturnList / z_sp_AddReturnListItem / z_sp_UpdateReturnListItem / z_sp_SetReturnListStatus /
     z_sp_DeleteReturnListItems
     z_sp_ReturnListToPrn  "Process": the Ready rows of ONE supplier -> a new PRN (z_tb_TempPurchaseSummary Type 2 +
                       z_tb_TempPurchase lines, number PRN + z_tb_System.PRNO) and, with @Post = 1, posted to stock
                       at once (z_sp_PostPrn: stock -qty). The PRN can be opened on the Goods Return page.

   sqlcmd -S <server> -d easyway -E -I -b -i 19_BackOffice_ReturnList.sql
   ============================================================================= */
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
IF OBJECT_ID(N'dbo.z_tb_Item', 'U') IS NULL OR OBJECT_ID(N'dbo.z_tb_TempPurchaseSummary', 'U') IS NULL
   OR OBJECT_ID(N'dbo.z_sp_PostPrn', 'P') IS NULL OR OBJECT_ID(N'dbo.z_tb_Supplier', 'U') IS NULL
BEGIN
    RAISERROR('This is not the back office database (z_tb_Item / z_tb_TempPurchaseSummary / z_sp_PostPrn not found) - nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
GO

IF OBJECT_ID('dbo.z_tb_ReturnList', 'U') IS NULL
CREATE TABLE dbo.z_tb_ReturnList (
    ReturnId    INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_z_tb_ReturnList PRIMARY KEY,
    LocationId  INT            NOT NULL CONSTRAINT DF_z_tb_ReturnList_Loc DEFAULT (1),
    ItemId      INT            NOT NULL,
    SuppId      INT            NOT NULL,
    Qty         DECIMAL(18,3)  NOT NULL,
    CostPrice   DECIMAL(18,2)  NULL,
    SellPrice   DECIMAL(18,2)  NULL,
    Reason      NVARCHAR(50)   NULL,     -- Damaged / Expired / Not selling / Other
    Remark      NVARCHAR(200)  NULL,
    Status      TINYINT        NOT NULL CONSTRAINT DF_z_tb_ReturnList_Status DEFAULT (1),  -- 1 Added, 2 Ready, 3 PRN made
    PrnNo       VARCHAR(20)    NULL,
    Source      TINYINT        NOT NULL CONSTRAINT DF_z_tb_ReturnList_Source DEFAULT (2),  -- 1 mobile app, 2 back office
    UserId      NVARCHAR(50)   NULL,
    CDate       DATETIME       NOT NULL CONSTRAINT DF_z_tb_ReturnList_CDate DEFAULT (GETDATE()),
    UDate       DATETIME       NULL
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_z_tb_ReturnList_Status' AND object_id = OBJECT_ID('dbo.z_tb_ReturnList'))
    CREATE INDEX IX_z_tb_ReturnList_Status ON dbo.z_tb_ReturnList (Status, SuppId) INCLUDE (ItemId, Qty);
GO

IF OBJECT_ID('dbo.z_sp_GetReturnList', 'P') IS NOT NULL DROP PROCEDURE dbo.z_sp_GetReturnList;
IF OBJECT_ID('dbo.z_sp_AddReturnListItem', 'P') IS NOT NULL DROP PROCEDURE dbo.z_sp_AddReturnListItem;
IF OBJECT_ID('dbo.z_sp_UpdateReturnListItem', 'P') IS NOT NULL DROP PROCEDURE dbo.z_sp_UpdateReturnListItem;
IF OBJECT_ID('dbo.z_sp_SetReturnListStatus', 'P') IS NOT NULL DROP PROCEDURE dbo.z_sp_SetReturnListStatus;
IF OBJECT_ID('dbo.z_sp_DeleteReturnListItems', 'P') IS NOT NULL DROP PROCEDURE dbo.z_sp_DeleteReturnListItems;
IF OBJECT_ID('dbo.z_sp_ReturnListToPrn', 'P') IS NOT NULL DROP PROCEDURE dbo.z_sp_ReturnListToPrn;
GO
IF TYPE_ID('dbo.z_tt_IdList') IS NULL
    CREATE TYPE dbo.z_tt_IdList AS TABLE (Id INT NOT NULL PRIMARY KEY);
GO

-- ---- the list: open rows (Added + Ready) by default, @Status 3 = PRN made (history, newest first, last @Days days).
--      With the item, supplier, stock now and the value at cost.
CREATE PROCEDURE dbo.z_sp_GetReturnList
    @SuppId INT = NULL,
    @Status INT = NULL,
    @Days   INT = 90
AS
BEGIN
    SET NOCOUNT ON;
    SELECT r.ReturnId, r.LocationId, r.ItemId, i.Barcode, i.RefCode, i.Descrip,
           r.SuppId, s.SuppCode, s.SuppName,
           r.Qty, r.CostPrice, r.SellPrice,
           CAST(r.Qty * ISNULL(r.CostPrice, 0) AS DECIMAL(18,2)) AS Amount,
           CAST(ISNULL(b.Qty, 0) AS DECIMAL(18,3)) AS StockQty,
           r.Reason, r.Remark, r.Status,
           CASE r.Status WHEN 1 THEN 'Added' WHEN 2 THEN 'Ready' WHEN 3 THEN 'PRN made' ELSE 'Unknown' END AS StatusText,
           r.PrnNo, r.Source, r.UserId, r.CDate, r.UDate
    FROM dbo.z_tb_ReturnList r
    JOIN dbo.z_tb_Item i ON i.ItemId = r.ItemId
    LEFT JOIN dbo.z_tb_Supplier s ON s.SuppId = r.SuppId
    LEFT JOIN dbo.z_tb_StockBalance b ON b.ItemId = r.ItemId AND b.LocationId = r.LocationId
    WHERE (@SuppId IS NULL OR r.SuppId = @SuppId)
      AND ((@Status IS NULL AND r.Status IN (1, 2))
           OR (@Status = 3 AND r.Status = 3 AND r.UDate >= DATEADD(DAY, -ISNULL(@Days, 90), GETDATE()))
           OR (@Status IN (1, 2) AND r.Status = @Status))
    ORDER BY CASE WHEN @Status = 3 THEN 0 ELSE 1 END, s.SuppName, r.CDate DESC, r.ReturnId DESC;
END
GO

-- ---- add a scanned item. Cost / sell price from the item. The same item for the same supplier that is still
--      "Added" gets the qty added (scanning it again = one more). Returns the row's id.
CREATE PROCEDURE dbo.z_sp_AddReturnListItem
    @ItemId     INT,
    @SuppId     INT,
    @Qty        DECIMAL(18,3),
    @Reason     NVARCHAR(50)  = NULL,
    @Remark     NVARCHAR(200) = NULL,
    @Source     TINYINT       = 2,
    @UserId     NVARCHAR(50)  = NULL,
    @LocationId INT           = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @z_tc INT; SET @z_tc = @@TRANCOUNT;
    BEGIN TRY
        DECLARE @Id INT, @Cost DECIMAL(18,2), @Sell DECIMAL(18,2);
        IF @Qty IS NULL OR @Qty <= 0 RAISERROR(N'%s', 16, 1, N'Enter a return qty more than 0.');
        IF NOT EXISTS (SELECT 1 FROM dbo.z_tb_Item WHERE ItemId = @ItemId) RAISERROR(N'%s', 16, 1, N'Item not found.');
        IF NOT EXISTS (SELECT 1 FROM dbo.z_tb_Supplier WHERE SuppId = @SuppId) RAISERROR(N'%s', 16, 1, N'Select the supplier.');
        SET @LocationId = ISNULL(@LocationId, 1);
        SELECT TOP 1 @Cost = d.CostPrice, @Sell = d.RetailPrice
        FROM dbo.z_tb_ItemDet d WHERE d.ItemId = @ItemId ORDER BY CASE WHEN d.LocationId = @LocationId THEN 0 ELSE 1 END;

        BEGIN TRAN;
            SELECT TOP 1 @Id = ReturnId FROM dbo.z_tb_ReturnList WITH (UPDLOCK, HOLDLOCK)
            WHERE ItemId = @ItemId AND SuppId = @SuppId AND LocationId = @LocationId AND Status = 1
              AND ISNULL(Reason, N'') = ISNULL(NULLIF(LTRIM(RTRIM(@Reason)), N''), N'')
            ORDER BY ReturnId DESC;
            IF @Id IS NOT NULL
                UPDATE dbo.z_tb_ReturnList
                SET Qty = Qty + @Qty, UDate = GETDATE(),
                    Remark = CASE WHEN NULLIF(LTRIM(RTRIM(@Remark)), N'') IS NULL THEN Remark ELSE LEFT(LTRIM(RTRIM(@Remark)), 200) END
                WHERE ReturnId = @Id;
            ELSE
            BEGIN
                INSERT dbo.z_tb_ReturnList (LocationId, ItemId, SuppId, Qty, CostPrice, SellPrice, Reason, Remark, Status, Source, UserId)
                VALUES (@LocationId, @ItemId, @SuppId, @Qty, @Cost, @Sell, NULLIF(LTRIM(RTRIM(@Reason)), N''),
                        NULLIF(LEFT(LTRIM(RTRIM(@Remark)), 200), N''), 1, ISNULL(@Source, 2), @UserId);
                SET @Id = SCOPE_IDENTITY();
            END
        COMMIT;
        SELECT @Id AS ReturnId;
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

-- ---- change qty / supplier / reason / remark of a row that has no PRN yet
CREATE PROCEDURE dbo.z_sp_UpdateReturnListItem
    @ReturnId INT,
    @Qty      DECIMAL(18,3),
    @SuppId   INT,
    @Reason   NVARCHAR(50)  = NULL,
    @Remark   NVARCHAR(200) = NULL,
    @UserId   NVARCHAR(50)  = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @z_tc INT; SET @z_tc = @@TRANCOUNT;
    BEGIN TRY
        DECLARE @Status TINYINT;
        SELECT @Status = Status FROM dbo.z_tb_ReturnList WHERE ReturnId = @ReturnId;
        IF @Status IS NULL RAISERROR(N'%s', 16, 1, N'Return row not found.');
        IF @Status = 3 RAISERROR(N'%s', 16, 1, N'A PRN was already made for this row - change the PRN on the Goods Return page.');
        IF @Qty IS NULL OR @Qty <= 0 RAISERROR(N'%s', 16, 1, N'Enter a return qty more than 0.');
        IF NOT EXISTS (SELECT 1 FROM dbo.z_tb_Supplier WHERE SuppId = @SuppId) RAISERROR(N'%s', 16, 1, N'Select the supplier.');
        UPDATE dbo.z_tb_ReturnList
        SET Qty = @Qty, SuppId = @SuppId, Reason = NULLIF(LTRIM(RTRIM(@Reason)), N''),
            Remark = NULLIF(LEFT(LTRIM(RTRIM(@Remark)), 200), N''), UserId = ISNULL(@UserId, UserId), UDate = GETDATE()
        WHERE ReturnId = @ReturnId;
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

-- ---- mark rows Ready (2, checked / packed for the supplier) or back to Added (1). Rows with a PRN are left alone.
CREATE PROCEDURE dbo.z_sp_SetReturnListStatus
    @Ids    dbo.z_tt_IdList READONLY,
    @Status INT,
    @UserId NVARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @z_tc INT; SET @z_tc = @@TRANCOUNT;
    BEGIN TRY
        IF @Status NOT IN (1, 2) RAISERROR(N'%s', 16, 1, N'Status must be 1 (Added) or 2 (Ready).');
        UPDATE r SET Status = @Status, UserId = ISNULL(@UserId, r.UserId), UDate = GETDATE()
        FROM dbo.z_tb_ReturnList r JOIN @Ids x ON x.Id = r.ReturnId
        WHERE r.Status IN (1, 2);
        SELECT @@ROWCOUNT AS Changed;
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

-- ---- delete rows that have no PRN yet (a row with a PRN is history and stays)
CREATE PROCEDURE dbo.z_sp_DeleteReturnListItems
    @Ids dbo.z_tt_IdList READONLY
AS
BEGIN
    SET NOCOUNT ON;
    DELETE r FROM dbo.z_tb_ReturnList r JOIN @Ids x ON x.Id = r.ReturnId WHERE r.Status IN (1, 2);
    SELECT @@ROWCOUNT AS Deleted;
END
GO

-- ---- "Process": Ready rows of ONE supplier -> one new PRN (summary Type 2 + lines, Status 1). @Post = 1 also
--      posts it to stock (z_sp_PostPrn, stock -qty) in the same transaction. Same item twice -> one line.
--      Returns PrnNo, Lines, Qty, Amount, Posted.
CREATE PROCEDURE dbo.z_sp_ReturnListToPrn
    @Ids    dbo.z_tt_IdList READONLY,
    @UserId VARCHAR(20)   = NULL,
    @Post   BIT           = 1,
    @RefNo  VARCHAR(30)   = NULL,
    @Remark VARCHAR(200)  = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @z_tc INT; SET @z_tc = @@TRANCOUNT;
    BEGIN TRY
        DECLARE @SuppId INT, @LocationId INT, @No INT, @PrnNo VARCHAR(20), @Lines INT, @Qty DECIMAL(18,3),
                @Amount DECIMAL(18,2), @Now DATETIME, @Posted INT;
        SET @Now = GETDATE();
        IF NOT EXISTS (SELECT 1 FROM @Ids) RAISERROR(N'%s', 16, 1, N'Select the items to process.');

        BEGIN TRAN;
            IF EXISTS (SELECT 1 FROM @Ids x LEFT JOIN dbo.z_tb_ReturnList r WITH (UPDLOCK, HOLDLOCK) ON r.ReturnId = x.Id
                       WHERE r.ReturnId IS NULL OR r.Status <> 2)
                RAISERROR(N'%s', 16, 1, N'Only Ready rows can be processed - mark them Ready first (a row may already have a PRN).');
            IF (SELECT COUNT(DISTINCT r.SuppId) FROM dbo.z_tb_ReturnList r JOIN @Ids x ON x.Id = r.ReturnId) > 1
                RAISERROR(N'%s', 16, 1, N'The selected rows are for more than one supplier - process one supplier at a time.');
            IF (SELECT COUNT(DISTINCT r.LocationId) FROM dbo.z_tb_ReturnList r JOIN @Ids x ON x.Id = r.ReturnId) > 1
                RAISERROR(N'%s', 16, 1, N'The selected rows are for more than one location.');
            SELECT TOP 1 @SuppId = r.SuppId, @LocationId = r.LocationId FROM dbo.z_tb_ReturnList r JOIN @Ids x ON x.Id = r.ReturnId;

            -- next PRN number (the Goods Return page uses the same counter: PRNO = the next number to use)
            UPDATE dbo.z_tb_System SET @No = PRNO, PRNO = PRNO + 1 WHERE LocaId = '01';
            IF @No IS NULL RAISERROR(N'%s', 16, 1, N'z_tb_System has no row for location 01 (PRN counter).');
            SET @PrnNo = 'PRN' + RIGHT('00000000' + CAST(@No AS VARCHAR(10)), 8);
            WHILE EXISTS (SELECT 1 FROM dbo.z_tb_TempPurchaseSummary WHERE GrnNo = @PrnNo)
            BEGIN
                UPDATE dbo.z_tb_System SET @No = PRNO, PRNO = PRNO + 1 WHERE LocaId = '01';
                SET @PrnNo = 'PRN' + RIGHT('00000000' + CAST(@No AS VARCHAR(10)), 8);
            END

            INSERT dbo.z_tb_TempPurchase (GrnNo, LocationId, ItemId, PDate, CostPrice, SellPrice, Qty, Discount, GAmount, Status, UDate, UserId)
            SELECT @PrnNo, @LocationId, r.ItemId, CAST(CONVERT(VARCHAR(10), @Now, 120) AS DATETIME),
                   MAX(r.CostPrice), MAX(r.SellPrice), SUM(r.Qty), 0,
                   CAST(SUM(r.Qty * ISNULL(r.CostPrice, 0)) AS DECIMAL(18,2)), 1, @Now, @UserId
            FROM dbo.z_tb_ReturnList r JOIN @Ids x ON x.Id = r.ReturnId
            GROUP BY r.ItemId
            ORDER BY MIN(r.ReturnId);
            SET @Lines = @@ROWCOUNT;

            SELECT @Qty = SUM(Qty), @Amount = SUM(GAmount) FROM dbo.z_tb_TempPurchase WHERE GrnNo = @PrnNo;

            INSERT dbo.z_tb_TempPurchaseSummary (GrnNo, LocationId, RefNo, PDate, SuppId, PMode, GAmount, SubTotDisc, NetAmount,
                                                 Advance, Returns, Qty, Status, Remark, UDate, UserId, POderNo, Type)
            VALUES (@PrnNo, @LocationId, NULLIF(@RefNo, ''), CAST(CONVERT(VARCHAR(10), @Now, 120) AS DATETIME), @SuppId, 1,
                    @Amount, 0, @Amount, 0, 0, @Qty, 1,
                    LEFT(ISNULL(NULLIF(@Remark, ''), 'Return Items list'), 200), @Now, @UserId, NULL, 2);

            UPDATE r SET Status = 3, PrnNo = @PrnNo, UDate = @Now, UserId = ISNULL(@UserId, r.UserId)
            FROM dbo.z_tb_ReturnList r JOIN @Ids x ON x.Id = r.ReturnId;

            IF @Post = 1
                EXEC dbo.z_sp_PostPrn @PrnNo = @PrnNo, @UserId = @UserId, @PostedLines = @Posted OUTPUT;
        COMMIT;

        SELECT @PrnNo AS PrnNo, @Lines AS Lines, @Qty AS Qty, @Amount AS Amount, CAST(@Post AS BIT) AS Posted;
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
PRINT 'U016 back office: return items list (z_tb_ReturnList) is ready.';
GO
SET NOEXEC OFF;
GO
