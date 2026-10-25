/* =============================================================================
   U019_Till_VoidLog.sql   (2026-10-25)
   Update for a till db (z_pos_fnt_db) that is ALREADY deployed. SQL Server 2008 R2 and newer.
   Safe to run again. Bills, Z reports and cash movements are not changed.

   What changes (back office Day Reports > Voids & No Sale, Docs/StockSystem.md 6.26):
     - table zf_tb_VoidLog: every line taken off a bill BEFORE it is paid - Void line (Kind 1), Void bill (Kind 2,
       one row per line, same GroupNo) and a qty made smaller (Kind 3, the qty taken off). Rows are never changed.
     - zf_tb_DrawerLog gets Synced / SyncedAt: drawer openings (No Sale ...) go to the back office too. Rows already
       there are Synced = 0, so the till sends its drawer history once.
     - types zf_tt_VoidLine (the lines of one void), zf_tt_LogId (ids the back office has)
     - zf_sp_LogVoid                                        POST /void-log of TillService
     - zf_sp_GetUnsyncedVoidLog / zf_sp_MarkVoidLogSynced   \ the body of POST api/Sync/TillLog
     - zf_sp_GetUnsyncedDrawerLog / zf_sp_MarkDrawerLogSynced /
   Same change in the full script: 02_FrontCashier_zf.sql.

   Order: U019_BackOffice_VoidReport.sql + the new ItemApi first, then on each till:
     1. sqlcmd -S .\SQLEXPRESS -d z_pos_fnt_db -E -I -b -i U019_Till_VoidLog.sql
     2. install the new TillService and the new billing page (the old ones keep working after the script)
   ============================================================================= */
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
IF OBJECT_ID(N'dbo.zf_tb_DrawerLog', 'U') IS NULL OR OBJECT_ID(N'dbo.zf_tb_ZReport', 'U') IS NULL
   OR OBJECT_ID(N'dbo.zf_tb_Config', 'U') IS NULL
BEGIN
    RAISERROR('This is not a till database (zf_tb_DrawerLog / zf_tb_ZReport / zf_tb_Config not found) - nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
GO
-- Lines taken off a bill before it was paid. Kind 1 void line, 2 void bill (every line, same GroupNo),
-- 3 qty made smaller (Qty = what was taken off). ZNo = the open Z at that time (NULL = none open yet).
IF OBJECT_ID(N'dbo.zf_tb_VoidLog', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.zf_tb_VoidLog (
        VoidId     INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_zf_tb_VoidLog PRIMARY KEY,
        GroupNo    INT           NOT NULL,   -- VoidId of the first line of the same void
        LoggedAt   DATETIME      NOT NULL CONSTRAINT DF_zf_tb_VoidLog_LoggedAt DEFAULT (GETDATE()),
        Kind       INT           NOT NULL,
        ZNo        INT           NULL,
        CashierId  VARCHAR(20)   NULL,
        Refund     BIT           NOT NULL CONSTRAINT DF_zf_tb_VoidLog_Refund DEFAULT (0),   -- a line of a refund bill
        ItemId     INT           NOT NULL,   -- 0 = other item
        Descrip    NVARCHAR(100) NULL,
        Qty        DECIMAL(18,3) NOT NULL,
        UnitPrice  DECIMAL(18,2) NOT NULL,
        Amount     DECIMAL(18,2) NOT NULL,
        Synced     BIT           NOT NULL CONSTRAINT DF_zf_tb_VoidLog_Synced DEFAULT (0),
        SyncedAt   DATETIME      NULL
    );
    CREATE INDEX IX_zf_tb_VoidLog_Synced ON dbo.zf_tb_VoidLog (Synced, VoidId);
    PRINT 'zf_tb_VoidLog created.';
END
GO
IF COL_LENGTH('dbo.zf_tb_DrawerLog', 'Synced') IS NULL
BEGIN
    ALTER TABLE dbo.zf_tb_DrawerLog ADD Synced   BIT      NOT NULL CONSTRAINT DF_zf_tb_DrawerLog_Synced DEFAULT (0),
                                        SyncedAt DATETIME NULL;
    PRINT 'zf_tb_DrawerLog.Synced / SyncedAt added.';
END
GO
IF OBJECT_ID(N'dbo.zf_sp_LogVoid', 'P') IS NOT NULL DROP PROCEDURE dbo.zf_sp_LogVoid;
IF OBJECT_ID(N'dbo.zf_sp_GetUnsyncedVoidLog', 'P') IS NOT NULL DROP PROCEDURE dbo.zf_sp_GetUnsyncedVoidLog;
IF OBJECT_ID(N'dbo.zf_sp_MarkVoidLogSynced', 'P') IS NOT NULL DROP PROCEDURE dbo.zf_sp_MarkVoidLogSynced;
IF OBJECT_ID(N'dbo.zf_sp_GetUnsyncedDrawerLog', 'P') IS NOT NULL DROP PROCEDURE dbo.zf_sp_GetUnsyncedDrawerLog;
IF OBJECT_ID(N'dbo.zf_sp_MarkDrawerLogSynced', 'P') IS NOT NULL DROP PROCEDURE dbo.zf_sp_MarkDrawerLogSynced;
GO
IF TYPE_ID('dbo.zf_tt_VoidLine') IS NOT NULL DROP TYPE dbo.zf_tt_VoidLine;
IF TYPE_ID('dbo.zf_tt_LogId') IS NOT NULL DROP TYPE dbo.zf_tt_LogId;
GO
-- the lines of one void (zf_sp_LogVoid)
CREATE TYPE dbo.zf_tt_VoidLine AS TABLE (
    LineNum    INT           NOT NULL PRIMARY KEY,
    ItemId     INT           NOT NULL,
    Descrip    NVARCHAR(100) NULL,
    Qty        DECIMAL(18,3) NOT NULL,
    UnitPrice  DECIMAL(18,2) NOT NULL,
    Amount     DECIMAL(18,2) NOT NULL
);
GO
-- log rows the back office has (zf_sp_MarkVoidLogSynced / zf_sp_MarkDrawerLogSynced)
CREATE TYPE dbo.zf_tt_LogId AS TABLE (
    Id INT NOT NULL PRIMARY KEY
);
GO
-- Records lines taken off a bill before payment. Returns one row: GroupNo, Lines.
CREATE PROCEDURE dbo.zf_sp_LogVoid
    @Kind      INT,
    @CashierId VARCHAR(20) = NULL,
    @Refund    BIT = 0,
    @Lines     dbo.zf_tt_VoidLine READONLY
AS
BEGIN
    DECLARE @z_tc INT; SET @z_tc = @@TRANCOUNT;   -- SQL 2008 R2 error handling (RAISERROR in TRY/CATCH)
    BEGIN TRY
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @ZNo INT, @GroupNo INT, @Now DATETIME;
    DECLARE @Ids TABLE (VoidId INT NOT NULL);
    IF @Kind NOT IN (1, 2, 3)
        RAISERROR(N'%s', 16, 1, N'Void Kind must be 1 (line), 2 (bill) or 3 (qty made smaller).');
    IF NOT EXISTS (SELECT 1 FROM @Lines)
        RAISERROR(N'%s', 16, 1, N'No lines to log.');
    IF EXISTS (SELECT 1 FROM @Lines WHERE Qty <= 0)
        RAISERROR(N'%s', 16, 1, N'Void qty must be above 0.');

    SET @Now = GETDATE();
    SELECT @ZNo = ZNo FROM dbo.zf_tb_ZReport WHERE Status = 0;

    BEGIN TRAN;
        INSERT dbo.zf_tb_VoidLog (GroupNo, LoggedAt, Kind, ZNo, CashierId, Refund, ItemId, Descrip, Qty, UnitPrice, Amount)
        OUTPUT inserted.VoidId INTO @Ids (VoidId)
        SELECT 0, @Now, @Kind, @ZNo, @CashierId, ISNULL(@Refund, 0), ItemId, LEFT(Descrip, 100), Qty, UnitPrice, Amount
        FROM @Lines ORDER BY LineNum;

        SELECT @GroupNo = MIN(VoidId) FROM @Ids;
        UPDATE v SET GroupNo = @GroupNo FROM dbo.zf_tb_VoidLog v JOIN @Ids i ON i.VoidId = v.VoidId;
    COMMIT;

    SELECT @GroupNo AS GroupNo, (SELECT COUNT(*) FROM @Ids) AS Lines;
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
-- Oldest void lines not sent yet (POST api/Sync/TillLog).
CREATE PROCEDURE dbo.zf_sp_GetUnsyncedVoidLog
    @Top INT = 100
AS
BEGIN
    SET NOCOUNT ON;
    SELECT TOP (@Top) VoidId, GroupNo, LoggedAt, Kind, ZNo, CashierId, Refund, ItemId, Descrip, Qty, UnitPrice, Amount
    FROM dbo.zf_tb_VoidLog WHERE Synced = 0 ORDER BY VoidId;
END
GO
CREATE PROCEDURE dbo.zf_sp_MarkVoidLogSynced
    @Ids dbo.zf_tt_LogId READONLY
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE v SET Synced = 1, SyncedAt = GETDATE()
    FROM dbo.zf_tb_VoidLog v JOIN @Ids i ON i.Id = v.VoidId;
END
GO
-- Oldest drawer openings not sent yet (POST api/Sync/TillLog). Kind 1 bill, 2 No Sale, 3 opening cash, 4 paid in, 5 paid out.
CREATE PROCEDURE dbo.zf_sp_GetUnsyncedDrawerLog
    @Top INT = 100
AS
BEGIN
    SET NOCOUNT ON;
    SELECT TOP (@Top) DrawerLogId, OpenedAt, Kind, InvoiceNo, CashierId, Reason, Opened
    FROM dbo.zf_tb_DrawerLog WHERE Synced = 0 ORDER BY DrawerLogId;
END
GO
CREATE PROCEDURE dbo.zf_sp_MarkDrawerLogSynced
    @Ids dbo.zf_tt_LogId READONLY
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE d SET Synced = 1, SyncedAt = GETDATE()
    FROM dbo.zf_tb_DrawerLog d JOIN @Ids i ON i.Id = d.DrawerLogId;
END
GO
SET NOEXEC OFF;
GO
PRINT 'U019_Till_VoidLog done.';
GO
