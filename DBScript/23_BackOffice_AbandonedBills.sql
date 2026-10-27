/* =============================================================================
   23_BackOffice_AbandonedBills.sql
   Run on: back office db (easyway), AFTER 21_BackOffice_DayReports.sql. Prefix z_. Re-runnable.
   Back office Day Reports > Abandoned bills: bills a till found still open after a restart (power cut, crash,
   browser closed) - z_tb_TillAbandonedBill (+ lines), sent up by the tills - POST api/Sync/AbandonedBills; the day's
   list with the lines. API: api/DayReport/Abandoned. Docs/StockSystem.md 6.27.
   Deployed databases: Updates/U022_BackOffice_AbandonedBills.sql (same objects).
   ============================================================================= */
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
IF OBJECT_ID(N'dbo.z_tb_SalesInvoice', 'U') IS NULL OR OBJECT_ID(N'dbo.z_tb_Terminal', 'U') IS NULL
BEGIN
    RAISERROR('This is not the back office database (z_tb_SalesInvoice / z_tb_Terminal not found) - nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
GO

-- 1. tables
-- A bill a till found still open after a restart (copy of the till's zf_tb_AbandonedBill). Outcome 1 taken back,
-- 2 thrown away (supervisor PIN, Reason). FinalStatus 1 paid, 2 suspended, 3 cleared, 8 thrown away, NULL = still open.
IF OBJECT_ID('dbo.z_tb_TillAbandonedBill', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.z_tb_TillAbandonedBill (
        TerminalId   INT              NOT NULL,
        AbandonId    INT              NOT NULL,   -- zf_tb_AbandonedBill.AbandonId on that till
        LocationId   INT              NOT NULL,
        DraftKey     UNIQUEIDENTIFIER NOT NULL,
        ZNo          INT              NULL,
        CashierId    VARCHAR(20)      NULL,       -- who was billing
        InvType      INT              NOT NULL,   -- 1 sale, 2 refund
        LineCount    INT              NOT NULL,
        NetAmount    DECIMAL(18,2)    NOT NULL,
        StartedAt    DATETIME         NOT NULL,   -- till time
        LastSavedAt  DATETIME         NOT NULL,   -- last change before it stopped
        FoundAt      DATETIME         NOT NULL,   -- when the till was back
        FoundBy      VARCHAR(20)      NULL,
        Outcome      INT              NOT NULL,
        Reason       NVARCHAR(100)    NULL,
        FinalStatus  INT              NULL,
        FinalAt      DATETIME         NULL,
        InvoiceNo    VARCHAR(30)      NULL,
        SuspendId    INT              NULL,
        ReceivedAt   DATETIME         NOT NULL CONSTRAINT DF_z_tb_TillAbandonedBill_ReceivedAt DEFAULT (GETDATE()),
        UpdatedAt    DATETIME         NULL,
        CONSTRAINT PK_z_tb_TillAbandonedBill PRIMARY KEY (TerminalId, AbandonId)
    );
    CREATE INDEX IX_z_tb_TillAbandonedBill_Date ON dbo.z_tb_TillAbandonedBill (LastSavedAt);
    PRINT 'z_tb_TillAbandonedBill created.';
END
GO
IF OBJECT_ID('dbo.z_tb_TillAbandonedBillItem', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.z_tb_TillAbandonedBillItem (
        TerminalId  INT           NOT NULL,
        AbandonId   INT           NOT NULL,
        LineNum     INT           NOT NULL,
        ItemId      INT           NOT NULL,   -- 0 = other item
        Descrip     NVARCHAR(100) NULL,
        Qty         DECIMAL(18,3) NOT NULL,
        UnitPrice   DECIMAL(18,2) NOT NULL,
        Discount    DECIMAL(18,2) NOT NULL,
        Amount      DECIMAL(18,2) NOT NULL,
        CONSTRAINT PK_z_tb_TillAbandonedBillItem PRIMARY KEY (TerminalId, AbandonId, LineNum)
    );
    PRINT 'z_tb_TillAbandonedBillItem created.';
END
GO

-- 2. procedures and types
IF OBJECT_ID(N'dbo.z_sp_SyncAbandonedBills', 'P') IS NOT NULL DROP PROCEDURE dbo.z_sp_SyncAbandonedBills;
IF OBJECT_ID(N'dbo.z_sp_DayReportAbandoned', 'P') IS NOT NULL DROP PROCEDURE dbo.z_sp_DayReportAbandoned;
IF OBJECT_ID(N'dbo.z_sp_DayReportAbandonedLines', 'P') IS NOT NULL DROP PROCEDURE dbo.z_sp_DayReportAbandonedLines;
GO
IF TYPE_ID('dbo.z_tt_TillAbandonedBill') IS NOT NULL DROP TYPE dbo.z_tt_TillAbandonedBill;
IF TYPE_ID('dbo.z_tt_TillAbandonedLine') IS NOT NULL DROP TYPE dbo.z_tt_TillAbandonedLine;
GO
-- column order must match the DataTables built in AppDbContext.DayReport.cs
CREATE TYPE dbo.z_tt_TillAbandonedBill AS TABLE (
    AbandonId    INT              NOT NULL PRIMARY KEY,
    DraftKey     UNIQUEIDENTIFIER NOT NULL,
    ZNo          INT              NULL,
    CashierId    VARCHAR(20)      NULL,
    InvType      INT              NOT NULL,
    LineCount    INT              NOT NULL,
    NetAmount    DECIMAL(18,2)    NOT NULL,
    StartedAt    DATETIME         NOT NULL,
    LastSavedAt  DATETIME         NOT NULL,
    FoundAt      DATETIME         NOT NULL,
    FoundBy      VARCHAR(20)      NULL,
    Outcome      INT              NOT NULL,
    Reason       NVARCHAR(100)    NULL,
    FinalStatus  INT              NULL,
    FinalAt      DATETIME         NULL,
    InvoiceNo    VARCHAR(30)      NULL,
    SuspendId    INT              NULL
);
GO
CREATE TYPE dbo.z_tt_TillAbandonedLine AS TABLE (
    AbandonId   INT           NOT NULL,
    LineNum     INT           NOT NULL,
    ItemId      INT           NOT NULL,
    Descrip     NVARCHAR(100) NULL,
    Qty         DECIMAL(18,3) NOT NULL,
    UnitPrice   DECIMAL(18,2) NOT NULL,
    Discount    DECIMAL(18,2) NOT NULL,
    Amount      DECIMAL(18,2) NOT NULL,
    PRIMARY KEY (AbandonId, LineNum)
);
GO
-- A till sends its abandoned bills. A bill already here gets how it ended (FinalStatus ...); its lines never change.
-- Returns one row: Bills = how many bills were received.
CREATE PROCEDURE dbo.z_sp_SyncAbandonedBills
    @TerminalId INT,
    @Bills      dbo.z_tt_TillAbandonedBill READONLY,
    @Lines      dbo.z_tt_TillAbandonedLine READONLY
AS
BEGIN
    DECLARE @z_tc INT; SET @z_tc = @@TRANCOUNT;   -- SQL 2008 R2 error handling (RAISERROR in TRY/CATCH)
    BEGIN TRY
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @LocationId INT;
    SELECT @LocationId = LocationId FROM dbo.z_tb_Terminal WHERE TerminalId = @TerminalId AND Status = 1;
    IF @LocationId IS NULL
        RAISERROR(N'%s', 16, 1, N'Terminal is not registered or is disabled.');
    IF EXISTS (SELECT 1 FROM @Bills WHERE Outcome NOT IN (1, 2))
        RAISERROR(N'%s', 16, 1, N'Invalid abandoned bill (Outcome 1-2).');

    BEGIN TRAN;
        UPDATE a
        SET FinalStatus = r.FinalStatus, FinalAt = r.FinalAt, InvoiceNo = r.InvoiceNo, SuspendId = r.SuspendId,
            UpdatedAt = GETDATE()
        FROM dbo.z_tb_TillAbandonedBill a WITH (UPDLOCK, HOLDLOCK)
        JOIN @Bills r ON r.AbandonId = a.AbandonId
        WHERE a.TerminalId = @TerminalId;

        INSERT dbo.z_tb_TillAbandonedBill (TerminalId, AbandonId, LocationId, DraftKey, ZNo, CashierId, InvType, LineCount,
                                           NetAmount, StartedAt, LastSavedAt, FoundAt, FoundBy, Outcome, Reason,
                                           FinalStatus, FinalAt, InvoiceNo, SuspendId)
        SELECT @TerminalId, r.AbandonId, @LocationId, r.DraftKey, r.ZNo, r.CashierId, r.InvType, r.LineCount,
               r.NetAmount, r.StartedAt, r.LastSavedAt, r.FoundAt, r.FoundBy, r.Outcome, r.Reason,
               r.FinalStatus, r.FinalAt, r.InvoiceNo, r.SuspendId
        FROM @Bills r
        WHERE NOT EXISTS (SELECT 1 FROM dbo.z_tb_TillAbandonedBill a WITH (UPDLOCK, HOLDLOCK)
                          WHERE a.TerminalId = @TerminalId AND a.AbandonId = r.AbandonId);

        INSERT dbo.z_tb_TillAbandonedBillItem (TerminalId, AbandonId, LineNum, ItemId, Descrip, Qty, UnitPrice, Discount, Amount)
        SELECT @TerminalId, l.AbandonId, l.LineNum, l.ItemId, l.Descrip, l.Qty, l.UnitPrice, l.Discount, l.Amount
        FROM @Lines l
        WHERE EXISTS (SELECT 1 FROM @Bills r WHERE r.AbandonId = l.AbandonId)
          AND NOT EXISTS (SELECT 1 FROM dbo.z_tb_TillAbandonedBillItem i WITH (UPDLOCK, HOLDLOCK)
                          WHERE i.TerminalId = @TerminalId AND i.AbandonId = l.AbandonId AND i.LineNum = l.LineNum);
    COMMIT;

    SELECT (SELECT COUNT(*) FROM @Bills) AS Bills;
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
-- Abandoned bills of the day (by the last change before the till stopped), newest first.
-- DownMinutes = minutes from that last change until the till was back (how long it was off / stuck).
CREATE PROCEDURE dbo.z_sp_DayReportAbandoned
    @Date DATE, @LocationId INT = 1, @TerminalId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @From DATETIME, @To DATETIME;
    SET @From = @Date;
    SET @To = DATEADD(DAY, 1, @From);

    SELECT a.TerminalId, t.TerminalCode, a.AbandonId, a.ZNo, a.CashierId, u.UserName AS CashierName, a.InvType,
           a.LineCount, a.NetAmount, a.StartedAt, a.LastSavedAt, a.FoundAt, a.FoundBy, f.UserName AS FoundByName,
           DATEDIFF(MINUTE, a.LastSavedAt, a.FoundAt) AS DownMinutes,
           a.Outcome, a.Reason, a.FinalStatus, a.FinalAt, a.InvoiceNo, a.SuspendId
    FROM dbo.z_tb_TillAbandonedBill a
    JOIN dbo.z_tb_Terminal t ON t.TerminalId = a.TerminalId
    LEFT JOIN dbo.z_tb_User u ON u.LoginName = a.CashierId
    LEFT JOIN dbo.z_tb_User f ON f.LoginName = a.FoundBy
    WHERE a.LastSavedAt >= @From AND a.LastSavedAt < @To AND a.LocationId = @LocationId
      AND (@TerminalId IS NULL OR a.TerminalId = @TerminalId)
    ORDER BY a.LastSavedAt DESC, a.TerminalId, a.AbandonId;
END
GO
-- The lines of those bills, as they were when the till stopped.
CREATE PROCEDURE dbo.z_sp_DayReportAbandonedLines
    @Date DATE, @LocationId INT = 1, @TerminalId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @From DATETIME, @To DATETIME;
    SET @From = @Date;
    SET @To = DATEADD(DAY, 1, @From);

    SELECT l.TerminalId, l.AbandonId, l.LineNum, l.ItemId, i.RefCode,
           CASE WHEN l.ItemId = 0 THEN ISNULL(l.Descrip, N'Other item') ELSE ISNULL(l.Descrip, ISNULL(i.Inv_Descrip, i.Descrip)) END AS Name,
           l.Qty, l.UnitPrice, l.Discount, l.Amount
    FROM dbo.z_tb_TillAbandonedBillItem l
    JOIN dbo.z_tb_TillAbandonedBill a ON a.TerminalId = l.TerminalId AND a.AbandonId = l.AbandonId
    LEFT JOIN dbo.z_tb_Item i ON i.ItemId = l.ItemId AND l.ItemId <> 0
    WHERE a.LastSavedAt >= @From AND a.LastSavedAt < @To AND a.LocationId = @LocationId
      AND (@TerminalId IS NULL OR a.TerminalId = @TerminalId)
    ORDER BY l.TerminalId, l.AbandonId, l.LineNum;
END
GO
SET NOEXEC OFF;
GO
PRINT '23_BackOffice_AbandonedBills: abandoned bills (z_tb_TillAbandonedBill, z_sp_SyncAbandonedBills, z_sp_DayReportAbandoned*).';
GO
