/* =============================================================================
   U006_BackOffice_StockTake.sql   (2026-10-14)
   Run on: back office db (easyway). SQL Server 2008 R2 and newer. Safe to run again.
   Needs: 01_BackOffice_Stock.sql (ledger, balance, z_sp_SaveStockAdjustment). Then the new ItemApi.
   The same file is DBScript/14_BackOffice_StockTake.sql (full scripts).

   Stock take: count sheets, enter counts, post the difference as ONE stock adjustment (StockSystem.md §6.18).
     z_tb_StockTake       ST00000001 - one count. FreezeAt = the moment it was started = "the shelf as at".
     z_tb_StockTakeSheet  the count sheets (one per category, split every @ItemsPerSheet items; more can be added)
     z_tb_StockTakeItem   one line per item per sheet. The same item may be on two sheets (shelf + store room):
                          its count is the SUM of its lines.
   Status 1 counting, 2 posted, 9 cancelled. Sheet status 1 open, 2 done.

   Posting: per item  AdjQty = counted - SUM(z_tb_StockLedger.Qty WHERE TxnDate <= FreezeAt)
   worked out at post time, so till bills for sales BEFORE the count that arrive late are allowed for, and sales
   AFTER the count are left alone. Posted through z_sp_SaveStockAdjustment (quantity mode, reason "Stock count",
   AdjDate = FreezeAt) - lines with no difference are not posted. Items nobody counted are left alone, unless
   @UncountedAsZero = 1 (then they are counted as 0).
   ============================================================================= */
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
IF OBJECT_ID(N'dbo.z_tb_StockLedger', 'U') IS NULL OR OBJECT_ID(N'dbo.z_sp_SaveStockAdjustment', 'P') IS NULL
BEGIN
    RAISERROR('This is not the back office database with the stock ledger (z_tb_StockLedger / z_sp_SaveStockAdjustment not found) - nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
GO

/* ---------------------------------------------------------------------------
   1. Tables
   --------------------------------------------------------------------------- */
IF OBJECT_ID('dbo.z_tb_StockTake', 'U') IS NULL
CREATE TABLE dbo.z_tb_StockTake (
    StockTakeId     INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_z_tb_StockTake PRIMARY KEY,
    StockTakeNo     VARCHAR(20)    NULL,       -- ST00000001 (from StockTakeId)
    LocationId      INT            NOT NULL,
    Title           NVARCHAR(100)  NULL,
    FreezeAt        DATETIME       NOT NULL,   -- the count is "as at" this moment
    CatId           INT            NULL,       -- the filter it was made with (NULL = all)
    SubCatId        INT            NULL,
    SupId           INT            NULL,
    IncludeZeroStock BIT           NOT NULL,
    Status          INT            NOT NULL,   -- 1 counting, 2 posted, 9 cancelled
    AdjNo           VARCHAR(20)    NULL,       -- the adjustment made by the post (NULL: nothing to adjust)
    UncountedAsZero BIT            NULL,       -- how the post treated items nobody counted
    PostedAt        DATETIME       NULL,
    PostedBy        VARCHAR(20)    NULL,
    UserId          VARCHAR(20)    NULL,
    CDate           DATETIME       NOT NULL CONSTRAINT DF_z_tb_StockTake_CDate DEFAULT (GETDATE()),
    UDate           DATETIME       NOT NULL CONSTRAINT DF_z_tb_StockTake_UDate DEFAULT (GETDATE())
);
GO
IF OBJECT_ID('dbo.z_tb_StockTakeSheet', 'U') IS NULL
CREATE TABLE dbo.z_tb_StockTakeSheet (
    SheetId      INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_z_tb_StockTakeSheet PRIMARY KEY,
    StockTakeId  INT            NOT NULL,
    SheetNo      INT            NOT NULL,   -- 1, 2, 3 ... inside the stock take
    SheetName    NVARCHAR(100)  NULL,       -- "Biscuits (1/3)", "Store room"
    CountedBy    NVARCHAR(50)   NULL,       -- who counts this sheet (typed by the user)
    Status       INT            NOT NULL,   -- 1 open, 2 done
    CDate        DATETIME       NOT NULL CONSTRAINT DF_z_tb_StockTakeSheet_CDate DEFAULT (GETDATE()),
    CONSTRAINT UQ_z_tb_StockTakeSheet_No UNIQUE (StockTakeId, SheetNo)
);
GO
IF OBJECT_ID('dbo.z_tb_StockTakeItem', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.z_tb_StockTakeItem (
        SheetId      INT            NOT NULL,
        ItemId       INT            NOT NULL,
        StockTakeId  INT            NOT NULL,
        LineNum      INT            NOT NULL,   -- order on the sheet
        FrozenQty    DECIMAL(18,3)  NOT NULL,   -- server balance when the line was made (for the screen only;
                                                -- the post uses the ledger as at FreezeAt)
        CostPrice    DECIMAL(18,2)  NULL,       -- AvgCost, else the item's cost, when the line was made
        CountedQty   DECIMAL(18,3)  NULL,       -- NULL = not counted yet
        Remark       NVARCHAR(100)  NULL,
        CountedBy    VARCHAR(20)    NULL,
        CountedAt    DATETIME       NULL,
        CONSTRAINT PK_z_tb_StockTakeItem PRIMARY KEY (SheetId, ItemId)
    );
    CREATE INDEX IX_z_tb_StockTakeItem_Take ON dbo.z_tb_StockTakeItem (StockTakeId, ItemId);
END
GO

/* ---------------------------------------------------------------------------
   2. Drop procs, then the type
   --------------------------------------------------------------------------- */
IF OBJECT_ID('dbo.z_sp_CreateStockTake', 'P')       IS NOT NULL DROP PROCEDURE dbo.z_sp_CreateStockTake;
IF OBJECT_ID('dbo.z_sp_AddStockTakeSheet', 'P')     IS NOT NULL DROP PROCEDURE dbo.z_sp_AddStockTakeSheet;
IF OBJECT_ID('dbo.z_sp_AddStockTakeItem', 'P')      IS NOT NULL DROP PROCEDURE dbo.z_sp_AddStockTakeItem;
IF OBJECT_ID('dbo.z_sp_SaveStockTakeCounts', 'P')   IS NOT NULL DROP PROCEDURE dbo.z_sp_SaveStockTakeCounts;
IF OBJECT_ID('dbo.z_sp_GetStockTakeVariance', 'P')  IS NOT NULL DROP PROCEDURE dbo.z_sp_GetStockTakeVariance;
IF OBJECT_ID('dbo.z_sp_PostStockTake', 'P')         IS NOT NULL DROP PROCEDURE dbo.z_sp_PostStockTake;
IF OBJECT_ID('dbo.z_sp_CancelStockTake', 'P')       IS NOT NULL DROP PROCEDURE dbo.z_sp_CancelStockTake;
GO
IF TYPE_ID('dbo.z_tt_StockTakeCount') IS NOT NULL DROP TYPE dbo.z_tt_StockTakeCount;
GO
-- column order must match the DataTable in Data/AppDbContext.StockTake.cs
CREATE TYPE dbo.z_tt_StockTakeCount AS TABLE (
    ItemId      INT            NOT NULL PRIMARY KEY,
    CountedQty  DECIMAL(18,3)  NULL,   -- NULL = clear the count
    Remark      NVARCHAR(100)  NULL
);
GO

/* ---------------------------------------------------------------------------
   3. Procs (SQL 2008 R2 error handling: RAISERROR inside TRY/CATCH, re-raised as 50000)
   --------------------------------------------------------------------------- */

-- Starts a stock take: FreezeAt = now, one sheet per category, split every @ItemsPerSheet items.
-- Items already in another stock take that is still counting are left out (Skipped in the answer).
CREATE PROCEDURE dbo.z_sp_CreateStockTake
    @LocationId       INT,
    @Title            NVARCHAR(100) = NULL,
    @CatId            INT = NULL,
    @SubCatId         INT = NULL,
    @SupId            INT = NULL,
    @IncludeZeroStock BIT = 0,      -- 0: only items with stock (+ or -) on the server; 1: every active item
    @ItemsPerSheet    INT = 50,
    @UserId           VARCHAR(20) = NULL,
    @StockTakeId      INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @z_tc INT; SET @z_tc = @@TRANCOUNT;
    BEGIN TRY
        DECLARE @Now DATETIME, @Skipped INT, @Lines INT;
        SET @Now = GETDATE();
        IF @ItemsPerSheet IS NULL OR @ItemsPerSheet < 5 SET @ItemsPerSheet = 50;
        IF @ItemsPerSheet > 500 SET @ItemsPerSheet = 500;

        CREATE TABLE #it (ItemId INT PRIMARY KEY, CatId INT, CatName VARCHAR(100), Descrip VARCHAR(200),
                          Qty DECIMAL(18,3), Cost DECIMAL(18,2), Busy BIT, Rn INT NULL, CatRn INT NULL, CatCnt INT NULL);

        INSERT #it (ItemId, CatId, CatName, Descrip, Qty, Cost, Busy)
        SELECT i.ItemId, i.CatId, ISNULL(c.CatName, '(no category)'), ISNULL(i.Descrip, ''),
               ISNULL(b.Qty, 0), ISNULL(NULLIF(b.AvgCost, 0), d.CostPrice),
               CASE WHEN EXISTS (SELECT 1 FROM dbo.z_tb_StockTakeItem x
                                 JOIN dbo.z_tb_StockTake t ON t.StockTakeId = x.StockTakeId
                                 WHERE x.ItemId = i.ItemId AND t.LocationId = @LocationId AND t.Status = 1)
                    THEN 1 ELSE 0 END
        FROM dbo.z_tb_Item i
        LEFT JOIN dbo.z_tb_Category c ON c.CatId = i.CatId
        LEFT JOIN dbo.z_tb_ItemDet d ON d.ItemId = i.ItemId AND d.LocationId = @LocationId
        LEFT JOIN dbo.z_tb_StockBalance b ON b.ItemId = i.ItemId AND b.LocationId = @LocationId
        WHERE i.Status = 1
          AND (@CatId IS NULL OR i.CatId = @CatId)
          AND (@SubCatId IS NULL OR i.SubCatId = @SubCatId)
          AND (@SupId IS NULL OR i.SupId = @SupId)
          AND (@IncludeZeroStock = 1 OR ISNULL(b.Qty, 0) <> 0);

        SELECT @Skipped = COUNT(*) FROM #it WHERE Busy = 1;
        DELETE #it WHERE Busy = 1;
        SELECT @Lines = COUNT(*) FROM #it;
        IF @Lines = 0
            RAISERROR(N'%s', 16, 1, N'No items to count with this filter (items already in an open stock take are left out).');

        -- sheet layout: by category, then name; a new sheet every @ItemsPerSheet items of a category
        UPDATE x SET Rn = r.Rn, CatRn = r.CatRn, CatCnt = r.CatCnt
        FROM #it x
        JOIN (SELECT ItemId,
                     ROW_NUMBER() OVER (ORDER BY CatName, CatId, Descrip, ItemId) AS Rn,
                     ROW_NUMBER() OVER (PARTITION BY CatName, CatId ORDER BY Descrip, ItemId) AS CatRn,
                     COUNT(*) OVER (PARTITION BY CatName, CatId) AS CatCnt
              FROM #it) r ON r.ItemId = x.ItemId;

        CREATE TABLE #sh (CatName VARCHAR(100), CatId INT, Part INT, Parts INT, SheetNo INT, SheetId INT NULL);
        INSERT #sh (CatName, CatId, Part, Parts)
        SELECT CatName, CatId, (CatRn - 1) / @ItemsPerSheet + 1, MAX((CatCnt - 1) / @ItemsPerSheet + 1)
        FROM #it GROUP BY CatName, CatId, (CatRn - 1) / @ItemsPerSheet + 1;
        UPDATE s SET SheetNo = r.n
        FROM #sh s JOIN (SELECT CatName, CatId, Part, ROW_NUMBER() OVER (ORDER BY CatName, CatId, Part) AS n FROM #sh) r
          ON r.CatName = s.CatName AND ISNULL(r.CatId, -1) = ISNULL(s.CatId, -1) AND r.Part = s.Part;

        BEGIN TRAN;
            INSERT dbo.z_tb_StockTake (LocationId, Title, FreezeAt, CatId, SubCatId, SupId, IncludeZeroStock, Status, UserId)
            VALUES (@LocationId, NULLIF(LTRIM(RTRIM(@Title)), N''), @Now, @CatId, @SubCatId, @SupId, ISNULL(@IncludeZeroStock, 0), 1, @UserId);
            SET @StockTakeId = SCOPE_IDENTITY();
            UPDATE dbo.z_tb_StockTake SET StockTakeNo = 'ST' + RIGHT('00000000' + CAST(@StockTakeId AS VARCHAR(10)), 8)
            WHERE StockTakeId = @StockTakeId;

            INSERT dbo.z_tb_StockTakeSheet (StockTakeId, SheetNo, SheetName, Status)
            SELECT @StockTakeId, SheetNo,
                   LEFT(CatName, 85) + CASE WHEN Parts > 1 THEN ' (' + CAST(Part AS VARCHAR(5)) + '/' + CAST(Parts AS VARCHAR(5)) + ')' ELSE '' END,
                   1
            FROM #sh;
            UPDATE s SET SheetId = t.SheetId
            FROM #sh s JOIN dbo.z_tb_StockTakeSheet t ON t.StockTakeId = @StockTakeId AND t.SheetNo = s.SheetNo;

            INSERT dbo.z_tb_StockTakeItem (SheetId, ItemId, StockTakeId, LineNum, FrozenQty, CostPrice)
            SELECT s.SheetId, x.ItemId, @StockTakeId, (x.CatRn - 1) % @ItemsPerSheet + 1, x.Qty, x.Cost
            FROM #it x
            JOIN #sh s ON s.CatName = x.CatName AND ISNULL(s.CatId, -1) = ISNULL(x.CatId, -1)
                      AND s.Part = (x.CatRn - 1) / @ItemsPerSheet + 1;
        COMMIT;

        SELECT @StockTakeId AS StockTakeId, @Lines AS ItemCount, (SELECT COUNT(*) FROM #sh) AS SheetCount, @Skipped AS Skipped;
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

-- An extra, empty sheet (e.g. "Store room") - items are added to it with z_sp_AddStockTakeItem.
CREATE PROCEDURE dbo.z_sp_AddStockTakeSheet
    @StockTakeId INT,
    @SheetName   NVARCHAR(100),
    @CountedBy   NVARCHAR(50) = NULL,
    @SheetId     INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @z_tc INT; SET @z_tc = @@TRANCOUNT;
    BEGIN TRY
        DECLARE @Status INT, @No INT;
        IF LTRIM(RTRIM(ISNULL(@SheetName, N''))) = N''
            RAISERROR(N'%s', 16, 1, N'Give the sheet a name.');
        BEGIN TRAN;
            SELECT @Status = Status FROM dbo.z_tb_StockTake WITH (UPDLOCK, HOLDLOCK) WHERE StockTakeId = @StockTakeId;
            IF @Status IS NULL RAISERROR(N'%s', 16, 1, N'Stock take not found.');
            IF @Status <> 1 RAISERROR(N'%s', 16, 1, N'This stock take is already posted or cancelled.');
            SELECT @No = ISNULL(MAX(SheetNo), 0) + 1 FROM dbo.z_tb_StockTakeSheet WHERE StockTakeId = @StockTakeId;
            INSERT dbo.z_tb_StockTakeSheet (StockTakeId, SheetNo, SheetName, CountedBy, Status)
            VALUES (@StockTakeId, @No, LTRIM(RTRIM(@SheetName)), NULLIF(LTRIM(RTRIM(@CountedBy)), N''), 1);
            SET @SheetId = SCOPE_IDENTITY();
            UPDATE dbo.z_tb_StockTake SET UDate = GETDATE() WHERE StockTakeId = @StockTakeId;
        COMMIT;
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

-- An item found on the shelf but not on the sheet. It may already be on another sheet of this stock take
-- (its counts are added up). Not allowed when the item is in ANOTHER stock take that is still counting.
CREATE PROCEDURE dbo.z_sp_AddStockTakeItem
    @StockTakeId INT,
    @SheetId     INT,
    @ItemId      INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @z_tc INT; SET @z_tc = @@TRANCOUNT;
    BEGIN TRY
        DECLARE @Status INT, @LocationId INT, @SheetStatus INT;
        BEGIN TRAN;
            SELECT @Status = Status, @LocationId = LocationId
            FROM dbo.z_tb_StockTake WITH (UPDLOCK, HOLDLOCK) WHERE StockTakeId = @StockTakeId;
            IF @Status IS NULL RAISERROR(N'%s', 16, 1, N'Stock take not found.');
            IF @Status <> 1 RAISERROR(N'%s', 16, 1, N'This stock take is already posted or cancelled.');
            SELECT @SheetStatus = Status FROM dbo.z_tb_StockTakeSheet WHERE SheetId = @SheetId AND StockTakeId = @StockTakeId;
            IF @SheetStatus IS NULL RAISERROR(N'%s', 16, 1, N'Sheet not found in this stock take.');
            IF NOT EXISTS (SELECT 1 FROM dbo.z_tb_Item WHERE ItemId = @ItemId)
                RAISERROR(N'%s', 16, 1, N'Item not found.');
            IF EXISTS (SELECT 1 FROM dbo.z_tb_StockTakeItem WHERE SheetId = @SheetId AND ItemId = @ItemId)
                RAISERROR(N'%s', 16, 1, N'This item is already on this sheet.');
            IF EXISTS (SELECT 1 FROM dbo.z_tb_StockTakeItem x JOIN dbo.z_tb_StockTake t ON t.StockTakeId = x.StockTakeId
                       WHERE x.ItemId = @ItemId AND t.LocationId = @LocationId AND t.Status = 1 AND t.StockTakeId <> @StockTakeId)
                RAISERROR(N'%s', 16, 1, N'This item is being counted in another open stock take.');

            INSERT dbo.z_tb_StockTakeItem (SheetId, ItemId, StockTakeId, LineNum, FrozenQty, CostPrice)
            SELECT @SheetId, @ItemId, @StockTakeId,
                   (SELECT ISNULL(MAX(LineNum), 0) + 1 FROM dbo.z_tb_StockTakeItem WHERE SheetId = @SheetId),
                   ISNULL(b.Qty, 0), ISNULL(NULLIF(b.AvgCost, 0), d.CostPrice)
            FROM (SELECT @ItemId AS ItemId) i
            LEFT JOIN dbo.z_tb_StockBalance b ON b.ItemId = i.ItemId AND b.LocationId = @LocationId
            LEFT JOIN dbo.z_tb_ItemDet d ON d.ItemId = i.ItemId AND d.LocationId = @LocationId;

            UPDATE dbo.z_tb_StockTakeSheet SET Status = 1 WHERE SheetId = @SheetId;   -- a done sheet opens again
            UPDATE dbo.z_tb_StockTake SET UDate = GETDATE() WHERE StockTakeId = @StockTakeId;
        COMMIT;
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

-- Saves counts typed for one sheet. Only the items sent are changed; CountedQty NULL clears a count.
-- @Done = 1 marks the sheet done, 0 opens it again, NULL leaves it.
CREATE PROCEDURE dbo.z_sp_SaveStockTakeCounts
    @StockTakeId INT,
    @SheetId     INT,
    @Counts      dbo.z_tt_StockTakeCount READONLY,
    @CountedBy   NVARCHAR(50) = NULL,
    @Done        BIT = NULL,
    @UserId      VARCHAR(20) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @z_tc INT; SET @z_tc = @@TRANCOUNT;
    BEGIN TRY
        DECLARE @Status INT, @Now DATETIME;
        SET @Now = GETDATE();
        IF EXISTS (SELECT 1 FROM @Counts WHERE CountedQty < 0)
            RAISERROR(N'%s', 16, 1, N'A count cannot be negative.');
        BEGIN TRAN;
            SELECT @Status = Status FROM dbo.z_tb_StockTake WITH (UPDLOCK, HOLDLOCK) WHERE StockTakeId = @StockTakeId;
            IF @Status IS NULL RAISERROR(N'%s', 16, 1, N'Stock take not found.');
            IF @Status <> 1 RAISERROR(N'%s', 16, 1, N'This stock take is already posted or cancelled - counts cannot change.');
            IF NOT EXISTS (SELECT 1 FROM dbo.z_tb_StockTakeSheet WHERE SheetId = @SheetId AND StockTakeId = @StockTakeId)
                RAISERROR(N'%s', 16, 1, N'Sheet not found in this stock take.');
            IF EXISTS (SELECT 1 FROM @Counts c WHERE NOT EXISTS
                         (SELECT 1 FROM dbo.z_tb_StockTakeItem x WHERE x.SheetId = @SheetId AND x.ItemId = c.ItemId))
                RAISERROR(N'%s', 16, 1, N'An item is not on this sheet - add it to the sheet first.');

            UPDATE x SET CountedQty = c.CountedQty,
                         Remark     = NULLIF(LTRIM(RTRIM(c.Remark)), N''),
                         CountedBy  = CASE WHEN c.CountedQty IS NULL THEN NULL ELSE @UserId END,
                         CountedAt  = CASE WHEN c.CountedQty IS NULL THEN NULL ELSE @Now END
            FROM dbo.z_tb_StockTakeItem x
            JOIN @Counts c ON c.ItemId = x.ItemId
            WHERE x.SheetId = @SheetId
              AND (ISNULL(x.CountedQty, -1) <> ISNULL(c.CountedQty, -1)
                   OR ISNULL(x.Remark, N'') <> ISNULL(LTRIM(RTRIM(c.Remark)), N''));

            UPDATE dbo.z_tb_StockTakeSheet
            SET CountedBy = ISNULL(NULLIF(LTRIM(RTRIM(@CountedBy)), N''), CountedBy),
                Status    = CASE WHEN @Done = 1 THEN 2 WHEN @Done = 0 THEN 1 ELSE Status END
            WHERE SheetId = @SheetId;
            UPDATE dbo.z_tb_StockTake SET UDate = @Now WHERE StockTakeId = @StockTakeId;
        COMMIT;
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

-- One row per item: counted (sum of its lines), system qty as at FreezeAt, difference and its value.
-- Counting: SystemQty from the ledger now (late till bills included). Posted: SystemQty = what the post used
-- (counted - the adjustment's AdjQty), so the report never moves afterwards.
CREATE PROCEDURE dbo.z_sp_GetStockTakeVariance
    @StockTakeId INT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @LocationId INT, @FreezeAt DATETIME, @Status INT, @AdjNo VARCHAR(20), @AdjId INT;
    SELECT @LocationId = LocationId, @FreezeAt = FreezeAt, @Status = Status, @AdjNo = AdjNo
    FROM dbo.z_tb_StockTake WHERE StockTakeId = @StockTakeId;
    SELECT @AdjId = AdjId FROM dbo.z_tb_StockAdjustment WHERE AdjNo = @AdjNo;

    SELECT v.ItemId, i.RefCode, i.Barcode, i.Descrip, c.CatName, u.UnitCode,
           v.Sheets, v.Lines, v.CountedLines, v.CountedQty, v.CostPrice,
           v.SystemQty,
           CASE WHEN v.CountedQty IS NULL THEN NULL ELSE v.CountedQty - v.SystemQty END AS DiffQty,
           CASE WHEN v.CountedQty IS NULL THEN NULL ELSE CAST(ROUND((v.CountedQty - v.SystemQty) * ISNULL(v.CostPrice, 0), 2) AS DECIMAL(18,2)) END AS DiffValue,
           ISNULL(d.RetailPrice, 0) AS RetailPrice,
           v.Remark
    FROM (
        SELECT x.ItemId,
               COUNT(*) AS Lines,
               SUM(CASE WHEN x.CountedQty IS NULL THEN 0 ELSE 1 END) AS CountedLines,
               SUM(x.CountedQty) AS CountedQty,          -- NULL when no line is counted
               MAX(x.CostPrice) AS CostPrice,
               MAX(x.Remark) AS Remark,
               CAST(MIN(s.SheetNo) AS VARCHAR(10)) + CASE WHEN COUNT(*) > 1 THEN ' +' + CAST(COUNT(*) - 1 AS VARCHAR(5)) ELSE '' END AS Sheets,
               CASE WHEN @Status = 2 AND SUM(x.CountedQty) IS NOT NULL
                    THEN SUM(x.CountedQty) - ISNULL((SELECT SUM(a.AdjQty) FROM dbo.z_tb_StockAdjustmentItem a
                                                     WHERE a.AdjId = @AdjId AND a.ItemId = x.ItemId), 0)
                    ELSE ISNULL((SELECT SUM(l.Qty) FROM dbo.z_tb_StockLedger l
                                 WHERE l.LocationId = @LocationId AND l.ItemId = x.ItemId AND l.TxnDate <= @FreezeAt), 0)
               END AS SystemQty
        FROM dbo.z_tb_StockTakeItem x
        JOIN dbo.z_tb_StockTakeSheet s ON s.SheetId = x.SheetId
        WHERE x.StockTakeId = @StockTakeId
        GROUP BY x.ItemId
    ) v
    LEFT JOIN dbo.z_tb_Item i ON i.ItemId = v.ItemId
    LEFT JOIN dbo.z_tb_Category c ON c.CatId = i.CatId
    LEFT JOIN dbo.z_tb_ItemDet d ON d.ItemId = v.ItemId AND d.LocationId = @LocationId
    LEFT JOIN dbo.z_tb_Unit u ON u.UnitId = d.UnitId
    ORDER BY c.CatName, i.Descrip, v.ItemId;
END
GO

-- Posts the differences as one stock adjustment (reason @ReasonId, default 1 "Stock count").
-- Items nobody counted: left alone, or counted as 0 when @UncountedAsZero = 1.
CREATE PROCEDURE dbo.z_sp_PostStockTake
    @StockTakeId     INT,
    @UncountedAsZero BIT = 0,
    @ReasonId        INT = 1,
    @UserId          VARCHAR(20) = NULL,
    @AdjNo           VARCHAR(20) = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @z_tc INT; SET @z_tc = @@TRANCOUNT;
    BEGIN TRY
        DECLARE @Status INT, @LocationId INT, @FreezeAt DATETIME, @No VARCHAR(20), @Remark VARCHAR(200),
                @Now DATETIME, @Items dbo.z_tt_AdjustmentItem;
        SET @Now = GETDATE();
        SET @AdjNo = NULL;

        BEGIN TRAN;
            SELECT @Status = Status, @LocationId = LocationId, @FreezeAt = FreezeAt, @No = StockTakeNo
            FROM dbo.z_tb_StockTake WITH (UPDLOCK, HOLDLOCK) WHERE StockTakeId = @StockTakeId;
            IF @Status IS NULL RAISERROR(N'%s', 16, 1, N'Stock take not found.');
            IF @Status <> 1 RAISERROR(N'%s', 16, 1, N'This stock take is already posted or cancelled.');
            IF ISNULL(@UncountedAsZero, 0) = 0
               AND NOT EXISTS (SELECT 1 FROM dbo.z_tb_StockTakeItem WHERE StockTakeId = @StockTakeId AND CountedQty IS NOT NULL)
                RAISERROR(N'%s', 16, 1, N'Nothing is counted yet.');

            IF @UncountedAsZero = 1
                UPDATE x SET CountedQty = 0, CountedBy = @UserId, CountedAt = @Now,
                             Remark = ISNULL(x.Remark, N'Not counted - posted as 0')
                FROM dbo.z_tb_StockTakeItem x
                WHERE x.StockTakeId = @StockTakeId AND x.CountedQty IS NULL
                  AND NOT EXISTS (SELECT 1 FROM dbo.z_tb_StockTakeItem y      -- counted on another sheet: that count stands
                                  WHERE y.StockTakeId = @StockTakeId AND y.ItemId = x.ItemId AND y.CountedQty IS NOT NULL);

            INSERT @Items (LineNum, ItemId, CountedQty, AdjQty, ReasonId, Remark)
            SELECT ROW_NUMBER() OVER (ORDER BY v.ItemId), v.ItemId, NULL, v.Counted - v.SystemQty, NULL, @No
            FROM (
                SELECT x.ItemId, SUM(x.CountedQty) AS Counted,
                       ISNULL((SELECT SUM(l.Qty) FROM dbo.z_tb_StockLedger l
                               WHERE l.LocationId = @LocationId AND l.ItemId = x.ItemId AND l.TxnDate <= @FreezeAt), 0) AS SystemQty
                FROM dbo.z_tb_StockTakeItem x
                WHERE x.StockTakeId = @StockTakeId
                GROUP BY x.ItemId
                HAVING SUM(x.CountedQty) IS NOT NULL
            ) v
            WHERE v.Counted <> v.SystemQty;

            IF EXISTS (SELECT 1 FROM @Items)
            BEGIN
                SET @Remark = 'Stock take ' + @No + ' counted ' + CONVERT(VARCHAR(16), @FreezeAt, 120);
                EXEC dbo.z_sp_SaveStockAdjustment @LocationId = @LocationId, @AdjDate = @FreezeAt, @ReasonId = @ReasonId,
                     @Remark = @Remark, @UserId = @UserId, @Items = @Items, @AdjNo = @AdjNo OUTPUT;
            END

            UPDATE dbo.z_tb_StockTake
            SET Status = 2, AdjNo = @AdjNo, UncountedAsZero = ISNULL(@UncountedAsZero, 0),
                PostedAt = @Now, PostedBy = @UserId, UDate = @Now
            WHERE StockTakeId = @StockTakeId;
        COMMIT;

        SELECT @AdjNo AS AdjNo, (SELECT COUNT(*) FROM @Items) AS AdjustedItems;
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

-- Cancels a stock take that is still counting. Nothing is posted; the rows stay (Status 9).
CREATE PROCEDURE dbo.z_sp_CancelStockTake
    @StockTakeId INT,
    @UserId      VARCHAR(20) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @z_tc INT; SET @z_tc = @@TRANCOUNT;
    BEGIN TRY
        DECLARE @Status INT;
        BEGIN TRAN;
            SELECT @Status = Status FROM dbo.z_tb_StockTake WITH (UPDLOCK, HOLDLOCK) WHERE StockTakeId = @StockTakeId;
            IF @Status IS NULL RAISERROR(N'%s', 16, 1, N'Stock take not found.');
            IF @Status <> 1 RAISERROR(N'%s', 16, 1, N'Only a stock take that is still counting can be cancelled.');
            UPDATE dbo.z_tb_StockTake SET Status = 9, PostedBy = @UserId, PostedAt = GETDATE(), UDate = GETDATE()
            WHERE StockTakeId = @StockTakeId;
        COMMIT;
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
PRINT 'U006 back office: stock take tables and procedures are ready.';
GO
SET NOEXEC OFF;
GO
