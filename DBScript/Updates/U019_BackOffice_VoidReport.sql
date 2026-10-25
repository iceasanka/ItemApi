/* =============================================================================
   U019_BackOffice_VoidReport.sql   (2026-10-25)
   Update for a back office db (easyway) that is ALREADY deployed. SQL Server 2008 R2 and newer.
   Safe to run again. No data is changed (two new, empty tables).

   What changes (back office Day Reports > Voids & No Sale - for stopping cash loss, Docs/StockSystem.md 6.26):
     - table z_tb_TillVoidLog: lines taken off a bill before payment on every till (void line, void bill, qty made
       smaller), sent up by TillService (zf_tb_VoidLog, till db U019). Key = TerminalId + the till's VoidId.
     - table z_tb_TillDrawerLog: every cash drawer opening (bill, No Sale, opening cash, paid in, paid out)
       (zf_tb_DrawerLog). Key = TerminalId + the till's DrawerLogId.
     - types z_tt_TillVoidLog, z_tt_TillDrawerLog, procedure z_sp_SyncTillLog (POST api/Sync/TillLog)
     - read-only report procedures, one calendar day (@Date) of one location, optional till:
         z_sp_DayReportLossCashiers  per cashier: sales, void lines / void bills / qty cuts, No Sale, refunds,
                                     voided saved bills
         z_sp_DayReportVoids         every void line of the day
         z_sp_DayReportNoSales       every No Sale drawer opening of the day
       Lines voided on a refund bill (Refund = 1) are listed but not counted as voids (no cash goes missing).
   Same change in the full script: 22_BackOffice_VoidReport.sql.

   Run:  sqlcmd -S <server> -d easyway -E -I -b -i U019_BackOffice_VoidReport.sql
   Then: the new ItemApi, the back office UI, then U019_Till_VoidLog.sql, the new TillService and the new billing
         page on each till. Until a till has all three, the report shows its refunds but no voids / No Sale.
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
-- Lines taken off a till bill before it was paid (copy of the till's zf_tb_VoidLog). Kind 1 void line,
-- 2 void bill (every line, same GroupNo), 3 qty made smaller (Qty = what was taken off).
IF OBJECT_ID('dbo.z_tb_TillVoidLog', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.z_tb_TillVoidLog (
        TerminalId  INT           NOT NULL,
        VoidId      INT           NOT NULL,   -- zf_tb_VoidLog.VoidId on that till
        LocationId  INT           NOT NULL,
        GroupNo     INT           NOT NULL,
        LoggedAt    DATETIME      NOT NULL,   -- till time
        Kind        INT           NOT NULL,
        ZNo         INT           NULL,
        CashierId   VARCHAR(20)   NULL,
        Refund      BIT           NOT NULL,
        ItemId      INT           NOT NULL,   -- 0 = other item
        Descrip     NVARCHAR(100) NULL,
        Qty         DECIMAL(18,3) NOT NULL,
        UnitPrice   DECIMAL(18,2) NOT NULL,
        Amount      DECIMAL(18,2) NOT NULL,
        ReceivedAt  DATETIME      NOT NULL CONSTRAINT DF_z_tb_TillVoidLog_ReceivedAt DEFAULT (GETDATE()),
        CONSTRAINT PK_z_tb_TillVoidLog PRIMARY KEY (TerminalId, VoidId)
    );
    CREATE INDEX IX_z_tb_TillVoidLog_Date ON dbo.z_tb_TillVoidLog (LoggedAt);
    PRINT 'z_tb_TillVoidLog created.';
END
GO
-- Every cash drawer opening on a till (copy of zf_tb_DrawerLog). Kind 1 after a bill, 2 No Sale, 3 opening cash,
-- 4 paid in, 5 paid out. Opened 0 = the printer did not take the open command.
IF OBJECT_ID('dbo.z_tb_TillDrawerLog', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.z_tb_TillDrawerLog (
        TerminalId   INT           NOT NULL,
        DrawerLogId  INT           NOT NULL,   -- zf_tb_DrawerLog.DrawerLogId on that till
        LocationId   INT           NOT NULL,
        OpenedAt     DATETIME      NOT NULL,   -- till time
        Kind         INT           NOT NULL,
        InvoiceNo    VARCHAR(30)   NULL,
        CashierId    VARCHAR(20)   NULL,
        Reason       NVARCHAR(100) NULL,
        Opened       BIT           NOT NULL,
        ReceivedAt   DATETIME      NOT NULL CONSTRAINT DF_z_tb_TillDrawerLog_ReceivedAt DEFAULT (GETDATE()),
        CONSTRAINT PK_z_tb_TillDrawerLog PRIMARY KEY (TerminalId, DrawerLogId)
    );
    CREATE INDEX IX_z_tb_TillDrawerLog_Date ON dbo.z_tb_TillDrawerLog (OpenedAt, Kind);
    PRINT 'z_tb_TillDrawerLog created.';
END
GO

-- 2. procedures and types
IF OBJECT_ID(N'dbo.z_sp_SyncTillLog', 'P') IS NOT NULL DROP PROCEDURE dbo.z_sp_SyncTillLog;
IF OBJECT_ID(N'dbo.z_sp_DayReportLossCashiers', 'P') IS NOT NULL DROP PROCEDURE dbo.z_sp_DayReportLossCashiers;
IF OBJECT_ID(N'dbo.z_sp_DayReportVoids', 'P') IS NOT NULL DROP PROCEDURE dbo.z_sp_DayReportVoids;
IF OBJECT_ID(N'dbo.z_sp_DayReportNoSales', 'P') IS NOT NULL DROP PROCEDURE dbo.z_sp_DayReportNoSales;
GO
IF TYPE_ID('dbo.z_tt_TillVoidLog') IS NOT NULL DROP TYPE dbo.z_tt_TillVoidLog;
IF TYPE_ID('dbo.z_tt_TillDrawerLog') IS NOT NULL DROP TYPE dbo.z_tt_TillDrawerLog;
GO
-- column order must match the DataTables built in AppDbContext.DayReport.cs
CREATE TYPE dbo.z_tt_TillVoidLog AS TABLE (
    VoidId     INT           NOT NULL PRIMARY KEY,
    GroupNo    INT           NOT NULL,
    LoggedAt   DATETIME      NOT NULL,
    Kind       INT           NOT NULL,
    ZNo        INT           NULL,
    CashierId  VARCHAR(20)   NULL,
    Refund     BIT           NOT NULL,
    ItemId     INT           NOT NULL,
    Descrip    NVARCHAR(100) NULL,
    Qty        DECIMAL(18,3) NOT NULL,
    UnitPrice  DECIMAL(18,2) NOT NULL,
    Amount     DECIMAL(18,2) NOT NULL
);
GO
CREATE TYPE dbo.z_tt_TillDrawerLog AS TABLE (
    DrawerLogId  INT           NOT NULL PRIMARY KEY,
    OpenedAt     DATETIME      NOT NULL,
    Kind         INT           NOT NULL,
    InvoiceNo    VARCHAR(30)   NULL,
    CashierId    VARCHAR(20)   NULL,
    Reason       NVARCHAR(100) NULL,
    Opened       BIT           NOT NULL
);
GO
-- A till sends its void lines and drawer openings. Rows never change on the till, so a resend is skipped.
-- Returns one row: Voids, Drawer = how many rows were received.
CREATE PROCEDURE dbo.z_sp_SyncTillLog
    @TerminalId INT,
    @Voids      dbo.z_tt_TillVoidLog READONLY,
    @Drawer     dbo.z_tt_TillDrawerLog READONLY
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
    IF EXISTS (SELECT 1 FROM @Voids WHERE Kind NOT IN (1, 2, 3))
        RAISERROR(N'%s', 16, 1, N'Invalid void line (Kind 1-3).');
    IF EXISTS (SELECT 1 FROM @Drawer WHERE Kind NOT BETWEEN 1 AND 5)
        RAISERROR(N'%s', 16, 1, N'Invalid drawer opening (Kind 1-5).');

    BEGIN TRAN;
        INSERT dbo.z_tb_TillVoidLog (TerminalId, VoidId, LocationId, GroupNo, LoggedAt, Kind, ZNo, CashierId, Refund,
                                     ItemId, Descrip, Qty, UnitPrice, Amount)
        SELECT @TerminalId, r.VoidId, @LocationId, r.GroupNo, r.LoggedAt, r.Kind, r.ZNo, r.CashierId, r.Refund,
               r.ItemId, r.Descrip, r.Qty, r.UnitPrice, r.Amount
        FROM @Voids r
        WHERE NOT EXISTS (SELECT 1 FROM dbo.z_tb_TillVoidLog v WITH (UPDLOCK, HOLDLOCK)
                          WHERE v.TerminalId = @TerminalId AND v.VoidId = r.VoidId);

        INSERT dbo.z_tb_TillDrawerLog (TerminalId, DrawerLogId, LocationId, OpenedAt, Kind, InvoiceNo, CashierId, Reason, Opened)
        SELECT @TerminalId, r.DrawerLogId, @LocationId, r.OpenedAt, r.Kind, r.InvoiceNo, r.CashierId, r.Reason, r.Opened
        FROM @Drawer r
        WHERE NOT EXISTS (SELECT 1 FROM dbo.z_tb_TillDrawerLog d WITH (UPDLOCK, HOLDLOCK)
                          WHERE d.TerminalId = @TerminalId AND d.DrawerLogId = r.DrawerLogId);
    COMMIT;

    SELECT (SELECT COUNT(*) FROM @Voids) AS Voids, (SELECT COUNT(*) FROM @Drawer) AS Drawer;
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
-- One row per cashier who did anything that day: sales, voids (refund-bill lines left out), No Sale, refunds and
-- voided saved bills. VoidPercent = all voids / (sales + all voids) * 100.
CREATE PROCEDURE dbo.z_sp_DayReportLossCashiers
    @Date DATE, @LocationId INT = 1, @TerminalId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @From DATETIME, @To DATETIME;
    SET @From = @Date;
    SET @To = DATEADD(DAY, 1, @From);

    SELECT c.CashierId, u.UserName AS CashierName,
           ISNULL(b.Bills, 0) AS Bills, ISNULL(b.SalesAmount, 0) AS SalesAmount,
           ISNULL(v.VoidLines, 0) AS VoidLines, ISNULL(v.VoidLineAmount, 0) AS VoidLineAmount,
           ISNULL(v.VoidBills, 0) AS VoidBills, ISNULL(v.VoidBillAmount, 0) AS VoidBillAmount,
           ISNULL(v.QtyCuts, 0) AS QtyCuts, ISNULL(v.QtyCutAmount, 0) AS QtyCutAmount,
           ISNULL(v.VoidLineAmount, 0) + ISNULL(v.VoidBillAmount, 0) + ISNULL(v.QtyCutAmount, 0) AS VoidTotal,
           CAST(CASE WHEN ISNULL(b.SalesAmount, 0) + ISNULL(v.VoidLineAmount, 0) + ISNULL(v.VoidBillAmount, 0) + ISNULL(v.QtyCutAmount, 0) <= 0 THEN 0
                     ELSE (ISNULL(v.VoidLineAmount, 0) + ISNULL(v.VoidBillAmount, 0) + ISNULL(v.QtyCutAmount, 0)) * 100.0
                          / (ISNULL(b.SalesAmount, 0) + ISNULL(v.VoidLineAmount, 0) + ISNULL(v.VoidBillAmount, 0) + ISNULL(v.QtyCutAmount, 0))
                END AS DECIMAL(9,2)) AS VoidPercent,
           ISNULL(d.NoSales, 0) AS NoSales, ISNULL(d.DrawerFailed, 0) AS DrawerFailed,
           ISNULL(b.Refunds, 0) AS Refunds, ISNULL(b.RefundAmount, 0) AS RefundAmount,
           ISNULL(b.VoidedBills, 0) AS VoidedBills, ISNULL(b.VoidedAmount, 0) AS VoidedAmount
    FROM (SELECT CashierId FROM dbo.z_tb_SalesInvoice
          WHERE InvDate >= @From AND InvDate < @To AND LocationId = @LocationId AND (@TerminalId IS NULL OR TerminalId = @TerminalId)
          UNION
          SELECT CashierId FROM dbo.z_tb_TillVoidLog
          WHERE LoggedAt >= @From AND LoggedAt < @To AND LocationId = @LocationId AND (@TerminalId IS NULL OR TerminalId = @TerminalId)
          UNION
          SELECT CashierId FROM dbo.z_tb_TillDrawerLog
          WHERE OpenedAt >= @From AND OpenedAt < @To AND LocationId = @LocationId AND Kind = 2
            AND (@TerminalId IS NULL OR TerminalId = @TerminalId)) c
    LEFT JOIN dbo.z_tb_User u ON u.LoginName = c.CashierId
    LEFT JOIN (SELECT CashierId,
                      SUM(CASE WHEN Status <> 9 AND InvType = 1 THEN 1 ELSE 0 END) AS Bills,
                      SUM(CASE WHEN Status <> 9 AND InvType = 1 THEN NetAmount ELSE 0 END) AS SalesAmount,
                      SUM(CASE WHEN Status <> 9 AND InvType = 2 THEN 1 ELSE 0 END) AS Refunds,
                      SUM(CASE WHEN Status <> 9 AND InvType = 2 THEN NetAmount ELSE 0 END) AS RefundAmount,
                      SUM(CASE WHEN Status = 9 THEN 1 ELSE 0 END) AS VoidedBills,
                      SUM(CASE WHEN Status = 9 THEN NetAmount ELSE 0 END) AS VoidedAmount
               FROM dbo.z_tb_SalesInvoice
               WHERE InvDate >= @From AND InvDate < @To AND LocationId = @LocationId
                 AND (@TerminalId IS NULL OR TerminalId = @TerminalId)
               GROUP BY CashierId) b ON ISNULL(b.CashierId, '') = ISNULL(c.CashierId, '')
    LEFT JOIN (SELECT CashierId,
                      SUM(CASE WHEN Kind = 1 THEN 1 ELSE 0 END) AS VoidLines,
                      SUM(CASE WHEN Kind = 1 THEN Amount ELSE 0 END) AS VoidLineAmount,
                      COUNT(DISTINCT CASE WHEN Kind = 2 THEN CAST(TerminalId AS VARCHAR(10)) + '-' + CAST(GroupNo AS VARCHAR(10)) END) AS VoidBills,
                      SUM(CASE WHEN Kind = 2 THEN Amount ELSE 0 END) AS VoidBillAmount,
                      SUM(CASE WHEN Kind = 3 THEN 1 ELSE 0 END) AS QtyCuts,
                      SUM(CASE WHEN Kind = 3 THEN Amount ELSE 0 END) AS QtyCutAmount
               FROM dbo.z_tb_TillVoidLog
               WHERE LoggedAt >= @From AND LoggedAt < @To AND LocationId = @LocationId AND Refund = 0
                 AND (@TerminalId IS NULL OR TerminalId = @TerminalId)
               GROUP BY CashierId) v ON ISNULL(v.CashierId, '') = ISNULL(c.CashierId, '')
    LEFT JOIN (SELECT CashierId, COUNT(*) AS NoSales, SUM(CASE WHEN Opened = 0 THEN 1 ELSE 0 END) AS DrawerFailed
               FROM dbo.z_tb_TillDrawerLog
               WHERE OpenedAt >= @From AND OpenedAt < @To AND LocationId = @LocationId AND Kind = 2
                 AND (@TerminalId IS NULL OR TerminalId = @TerminalId)
               GROUP BY CashierId) d ON ISNULL(d.CashierId, '') = ISNULL(c.CashierId, '')
    ORDER BY ISNULL(v.VoidLineAmount, 0) + ISNULL(v.VoidBillAmount, 0) + ISNULL(v.QtyCutAmount, 0) DESC, c.CashierId;
END
GO
-- Every void line of the day (refund-bill lines too, Refund = 1), newest first.
CREATE PROCEDURE dbo.z_sp_DayReportVoids
    @Date DATE, @LocationId INT = 1, @TerminalId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @From DATETIME, @To DATETIME;
    SET @From = @Date;
    SET @To = DATEADD(DAY, 1, @From);

    SELECT v.TerminalId, t.TerminalCode, v.VoidId, v.GroupNo, v.LoggedAt, v.Kind, v.ZNo, v.CashierId,
           u.UserName AS CashierName, v.Refund, v.ItemId, i.RefCode, i.Barcode,
           CASE WHEN v.ItemId = 0 THEN ISNULL(v.Descrip, N'Other item') ELSE ISNULL(v.Descrip, ISNULL(i.Inv_Descrip, i.Descrip)) END AS Name,
           v.Qty, v.UnitPrice, v.Amount
    FROM dbo.z_tb_TillVoidLog v
    JOIN dbo.z_tb_Terminal t ON t.TerminalId = v.TerminalId
    LEFT JOIN dbo.z_tb_User u ON u.LoginName = v.CashierId
    LEFT JOIN dbo.z_tb_Item i ON i.ItemId = v.ItemId AND v.ItemId <> 0
    WHERE v.LoggedAt >= @From AND v.LoggedAt < @To AND v.LocationId = @LocationId
      AND (@TerminalId IS NULL OR v.TerminalId = @TerminalId)
    ORDER BY v.LoggedAt DESC, v.TerminalId, v.VoidId;
END
GO
-- Every No Sale drawer opening of the day (Opened 0 = the drawer did not open), newest first.
CREATE PROCEDURE dbo.z_sp_DayReportNoSales
    @Date DATE, @LocationId INT = 1, @TerminalId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @From DATETIME, @To DATETIME;
    SET @From = @Date;
    SET @To = DATEADD(DAY, 1, @From);

    SELECT d.TerminalId, t.TerminalCode, d.DrawerLogId, d.OpenedAt, d.CashierId, u.UserName AS CashierName,
           d.Reason, d.Opened
    FROM dbo.z_tb_TillDrawerLog d
    JOIN dbo.z_tb_Terminal t ON t.TerminalId = d.TerminalId
    LEFT JOIN dbo.z_tb_User u ON u.LoginName = d.CashierId
    WHERE d.OpenedAt >= @From AND d.OpenedAt < @To AND d.LocationId = @LocationId AND d.Kind = 2
      AND (@TerminalId IS NULL OR d.TerminalId = @TerminalId)
    ORDER BY d.OpenedAt DESC, d.TerminalId, d.DrawerLogId;
END
GO
SET NOEXEC OFF;
GO
PRINT 'U019 back office: voids & No Sale report (z_tb_TillVoidLog, z_tb_TillDrawerLog, z_sp_SyncTillLog, z_sp_DayReportLoss* ).';
GO
