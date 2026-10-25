/* =============================================================================
   U018_BackOffice_DayReports.sql   (2026-10-25)
   Update for a back office db (easyway) that is ALREADY deployed. SQL Server 2008 R2 and newer.
   Safe to run again. No data is changed (one new, empty table).

   What changes (back office Day Reports page - any day, any time, Docs/StockSystem.md 6.25):
     - table z_tb_CashMovement: opening cash / paid in / paid out of every till, sent up by TillService
       (zf_tb_CashMovement, till db U018). Key = TerminalId + the till's MoveId; a resend replaces the row.
     - type z_tt_CashMovement, procedure z_sp_SyncCashMovements (POST api/Sync/CashMovements)
     - read-only report procedures, all for one calendar day (@Date) of one location, optional till:
         z_sp_DayReportTills         per till: bills, discounts, sales, refunds, cash / card / bank / cheque / other,
                                     opening cash, paid in, paid out, expected cash in the drawer
         z_sp_DayReportZ             the Zs (day ends) of that business day, with their cash in / out
         z_sp_DayReportCash          every opening cash / paid in / paid out of the day
         z_sp_DayReportItems         every item sold / refunded that day
         z_sp_DayReportBills         every bill of the day
         z_sp_DayReportBill, z_sp_DayReportBillLines, z_sp_DayReportBillPayments   one bill (bill copy)
       Bills and cash movements count by their own date / time (the till's clock); the Zs by their business date.
       Rules as the sales dashboard and the till Z: voided bills (Status 9) are left out, refunds count negative.
   Same change in the full script: 21_BackOffice_DayReports.sql.

   Run:  sqlcmd -S <server> -d easyway -E -I -b -i U018_BackOffice_DayReports.sql
   Then: the new ItemApi, the back office UI (Reports > Day Reports), then U018_Till_CashMovementUpload.sql and the
         new TillService on each till. Until a till has both, the page shows its sales but no cash in / out.
   ============================================================================= */
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
IF OBJECT_ID(N'dbo.z_tb_SalesInvoice', 'U') IS NULL OR OBJECT_ID(N'dbo.z_tb_Terminal', 'U') IS NULL
   OR OBJECT_ID(N'dbo.z_tb_ZReport', 'U') IS NULL
BEGIN
    RAISERROR('This is not the back office database (z_tb_SalesInvoice / z_tb_Terminal / z_tb_ZReport not found) - nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
GO

-- 1. table
-- Cash put into / taken out of a till drawer without a sale (copy of the till's zf_tb_CashMovement).
--   Kind 1 opening cash, 2 paid in, 3 paid out. Status 1 active, 9 replaced (opening cash typed again).
IF OBJECT_ID('dbo.z_tb_CashMovement', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.z_tb_CashMovement (
        TerminalId  INT           NOT NULL,
        MoveId      INT           NOT NULL,   -- zf_tb_CashMovement.MoveId on that till
        LocationId  INT           NOT NULL,
        ZNo         INT           NOT NULL,
        Kind        INT           NOT NULL,
        Amount      DECIMAL(18,2) NOT NULL,   -- always > 0; Kind gives the direction
        Reason      NVARCHAR(100) NULL,
        CashierId   VARCHAR(20)   NULL,
        CreatedAt   DATETIME      NOT NULL,   -- till time
        Status      INT           NOT NULL,
        ReceivedAt  DATETIME      NOT NULL CONSTRAINT DF_z_tb_CashMovement_ReceivedAt DEFAULT (GETDATE()),
        CONSTRAINT PK_z_tb_CashMovement PRIMARY KEY (TerminalId, MoveId)
    );
    CREATE INDEX IX_z_tb_CashMovement_Date ON dbo.z_tb_CashMovement (CreatedAt);
    CREATE INDEX IX_z_tb_CashMovement_Z ON dbo.z_tb_CashMovement (TerminalId, ZNo);
    PRINT 'z_tb_CashMovement created.';
END
GO

-- 2. procedures and type
IF OBJECT_ID(N'dbo.z_sp_SyncCashMovements', 'P') IS NOT NULL DROP PROCEDURE dbo.z_sp_SyncCashMovements;
IF OBJECT_ID(N'dbo.z_sp_DayReportTills', 'P') IS NOT NULL DROP PROCEDURE dbo.z_sp_DayReportTills;
IF OBJECT_ID(N'dbo.z_sp_DayReportZ', 'P') IS NOT NULL DROP PROCEDURE dbo.z_sp_DayReportZ;
IF OBJECT_ID(N'dbo.z_sp_DayReportCash', 'P') IS NOT NULL DROP PROCEDURE dbo.z_sp_DayReportCash;
IF OBJECT_ID(N'dbo.z_sp_DayReportItems', 'P') IS NOT NULL DROP PROCEDURE dbo.z_sp_DayReportItems;
IF OBJECT_ID(N'dbo.z_sp_DayReportBills', 'P') IS NOT NULL DROP PROCEDURE dbo.z_sp_DayReportBills;
IF OBJECT_ID(N'dbo.z_sp_DayReportBill', 'P') IS NOT NULL DROP PROCEDURE dbo.z_sp_DayReportBill;
IF OBJECT_ID(N'dbo.z_sp_DayReportBillLines', 'P') IS NOT NULL DROP PROCEDURE dbo.z_sp_DayReportBillLines;
IF OBJECT_ID(N'dbo.z_sp_DayReportBillPayments', 'P') IS NOT NULL DROP PROCEDURE dbo.z_sp_DayReportBillPayments;
GO
IF TYPE_ID('dbo.z_tt_CashMovement') IS NOT NULL DROP TYPE dbo.z_tt_CashMovement;
GO
-- column order must match the DataTable built in AppDbContext.DayReport.cs
CREATE TYPE dbo.z_tt_CashMovement AS TABLE (
    MoveId     INT           NOT NULL PRIMARY KEY,
    ZNo        INT           NOT NULL,
    Kind       INT           NOT NULL,
    Amount     DECIMAL(18,2) NOT NULL,
    Reason     NVARCHAR(100) NULL,
    CashierId  VARCHAR(20)   NULL,
    CreatedAt  DATETIME      NOT NULL,
    Status     INT           NOT NULL
);
GO
-- A till sends its cash movements (new ones, and an opening cash that was replaced). Stored or replaced.
-- Returns one row: Received = how many rows were stored.
CREATE PROCEDURE dbo.z_sp_SyncCashMovements
    @TerminalId INT,
    @Rows       dbo.z_tt_CashMovement READONLY
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
    IF EXISTS (SELECT 1 FROM @Rows WHERE Kind NOT IN (1, 2, 3) OR Status NOT IN (1, 9) OR Amount <= 0)
        RAISERROR(N'%s', 16, 1, N'Invalid cash movement (Kind 1-3, Status 1 or 9, Amount above 0).');

    BEGIN TRAN;
        UPDATE m SET ZNo = r.ZNo, Kind = r.Kind, Amount = r.Amount, Reason = r.Reason, CashierId = r.CashierId,
                     CreatedAt = r.CreatedAt, Status = r.Status, ReceivedAt = GETDATE()
        FROM dbo.z_tb_CashMovement m WITH (UPDLOCK, HOLDLOCK)
        JOIN @Rows r ON r.MoveId = m.MoveId
        WHERE m.TerminalId = @TerminalId;

        INSERT dbo.z_tb_CashMovement (TerminalId, MoveId, LocationId, ZNo, Kind, Amount, Reason, CashierId, CreatedAt, Status)
        SELECT @TerminalId, r.MoveId, @LocationId, r.ZNo, r.Kind, r.Amount, r.Reason, r.CashierId, r.CreatedAt, r.Status
        FROM @Rows r
        WHERE NOT EXISTS (SELECT 1 FROM dbo.z_tb_CashMovement m WHERE m.TerminalId = @TerminalId AND m.MoveId = r.MoveId);
    COMMIT;

    SELECT COUNT(*) AS Received FROM @Rows;
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
-- One row per till of the location (also tills without bills that day): the day's bills, discounts, sales and
-- payments, and the cash in / out of the drawer. Refunds count negative in the payment totals, like the till Z.
-- ExpectedCash = opening cash + cash (sales - refunds) + paid in - paid out.
CREATE PROCEDURE dbo.z_sp_DayReportTills
    @Date DATE, @LocationId INT = 1, @TerminalId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @From DATETIME, @To DATETIME;
    SET @From = @Date;
    SET @To = DATEADD(DAY, 1, @From);

    SELECT t.TerminalId, t.TerminalCode, t.TerminalName, t.LastSyncAt,
           ISNULL(b.Bills, 0) AS Bills, ISNULL(b.Refunds, 0) AS Refunds, ISNULL(b.Voided, 0) AS Voided,
           ISNULL(b.SalesAmount, 0) + ISNULL(l.ItemDiscount, 0) + ISNULL(b.BillDiscount, 0) AS SalesBeforeDiscount,
           ISNULL(l.ItemDiscount, 0) AS ItemDiscount, ISNULL(b.BillDiscount, 0) AS BillDiscount,
           ISNULL(b.SalesAmount, 0) AS SalesAmount, ISNULL(b.RefundAmount, 0) AS RefundAmount,
           ISNULL(b.SalesAmount, 0) - ISNULL(b.RefundAmount, 0) AS NetSales,
           ISNULL(p.Cash, 0) AS Cash, ISNULL(p.Card, 0) AS Card, ISNULL(p.Bank, 0) AS Bank,
           ISNULL(p.Cheque, 0) AS Cheque, ISNULL(p.OtherPay, 0) AS OtherPay,
           ISNULL(m.OpeningCash, 0) AS OpeningCash, ISNULL(m.PaidIn, 0) AS PaidIn, ISNULL(m.PaidOut, 0) AS PaidOut,
           ISNULL(m.OpeningCash, 0) + ISNULL(p.Cash, 0) + ISNULL(m.PaidIn, 0) - ISNULL(m.PaidOut, 0) AS ExpectedCash,
           b.FirstBillAt, b.LastBillAt, m.LastMoveAt
    FROM dbo.z_tb_Terminal t
    LEFT JOIN (SELECT TerminalId,
                      SUM(CASE WHEN Status <> 9 AND InvType = 1 THEN 1 ELSE 0 END) AS Bills,
                      SUM(CASE WHEN Status <> 9 AND InvType = 2 THEN 1 ELSE 0 END) AS Refunds,
                      SUM(CASE WHEN Status = 9 THEN 1 ELSE 0 END) AS Voided,
                      SUM(CASE WHEN Status <> 9 AND InvType = 1 THEN NetAmount ELSE 0 END) AS SalesAmount,
                      SUM(CASE WHEN Status <> 9 AND InvType = 2 THEN NetAmount ELSE 0 END) AS RefundAmount,
                      SUM(CASE WHEN Status <> 9 AND InvType = 1 THEN Discount ELSE 0 END) AS BillDiscount,
                      MIN(InvDate) AS FirstBillAt, MAX(InvDate) AS LastBillAt
               FROM dbo.z_tb_SalesInvoice
               WHERE InvDate >= @From AND InvDate < @To AND LocationId = @LocationId
               GROUP BY TerminalId) b ON b.TerminalId = t.TerminalId
    LEFT JOIN (SELECT s.TerminalId, SUM(it.Discount) AS ItemDiscount
               FROM dbo.z_tb_SalesInvoice s JOIN dbo.z_tb_SalesInvoiceItem it ON it.InvoiceId = s.InvoiceId
               WHERE s.InvDate >= @From AND s.InvDate < @To AND s.LocationId = @LocationId
                 AND s.Status <> 9 AND s.InvType = 1
               GROUP BY s.TerminalId) l ON l.TerminalId = t.TerminalId
    LEFT JOIN (SELECT s.TerminalId,
                      SUM(CASE WHEN p.PayType = 1 THEN x.Amount ELSE 0 END) AS Cash,
                      SUM(CASE WHEN p.PayType = 2 THEN x.Amount ELSE 0 END) AS Card,
                      SUM(CASE WHEN p.PayType = 5 THEN x.Amount ELSE 0 END) AS Bank,
                      SUM(CASE WHEN p.PayType = 6 THEN x.Amount ELSE 0 END) AS Cheque,
                      SUM(CASE WHEN p.PayType NOT IN (1, 2, 5, 6) THEN x.Amount ELSE 0 END) AS OtherPay
               FROM dbo.z_tb_SalesInvoice s
               JOIN dbo.z_tb_SalesPayment p ON p.InvoiceId = s.InvoiceId
               CROSS APPLY (SELECT CASE WHEN s.InvType = 2 THEN -p.Amount ELSE p.Amount END AS Amount) x
               WHERE s.InvDate >= @From AND s.InvDate < @To AND s.LocationId = @LocationId AND s.Status <> 9
               GROUP BY s.TerminalId) p ON p.TerminalId = t.TerminalId
    LEFT JOIN (SELECT TerminalId,
                      SUM(CASE WHEN Kind = 1 THEN Amount ELSE 0 END) AS OpeningCash,
                      SUM(CASE WHEN Kind = 2 THEN Amount ELSE 0 END) AS PaidIn,
                      SUM(CASE WHEN Kind = 3 THEN Amount ELSE 0 END) AS PaidOut,
                      MAX(CreatedAt) AS LastMoveAt
               FROM dbo.z_tb_CashMovement
               WHERE CreatedAt >= @From AND CreatedAt < @To AND LocationId = @LocationId AND Status = 1
               GROUP BY TerminalId) m ON m.TerminalId = t.TerminalId
    WHERE t.LocationId = @LocationId
      AND (@TerminalId IS NULL OR t.TerminalId = @TerminalId)
    ORDER BY t.TerminalId;
END
GO
-- The Zs (cashier day ends) whose business date is @Date, with the drawer cash: opening cash, paid in, paid out
-- (from z_tb_CashMovement of that Z) and the expected cash. Discounts from the Z's bills on the server.
-- Status 2 received, 3 reconciled, 4 mismatch.
CREATE PROCEDURE dbo.z_sp_DayReportZ
    @Date DATE, @LocationId INT = 1, @TerminalId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT z.ZId, z.TerminalId, t.TerminalCode, z.ZNo, z.BusinessDate, z.CashierId, u.UserName AS CashierName,
           z.OpenedAt, z.ClosedAt, z.InvoiceCount, z.SalesAmount, z.RefundAmount, z.NetSales,
           z.CashAmount, z.CardAmount, z.OtherAmount, z.BankAmount, z.ChequeAmount,
           ISNULL(d.ItemDiscount, 0) AS ItemDiscount, ISNULL(d.BillDiscount, 0) AS BillDiscount,
           ISNULL(m.OpeningCash, 0) AS OpeningCash, ISNULL(m.PaidIn, 0) AS PaidIn, ISNULL(m.PaidOut, 0) AS PaidOut,
           ISNULL(m.OpeningCash, 0) + z.CashAmount + ISNULL(m.PaidIn, 0) - ISNULL(m.PaidOut, 0) AS ExpectedCash,
           CAST(CASE WHEN m.Moves IS NULL THEN 0 ELSE 1 END AS BIT) AS HasCashMovements,
           z.Status, z.MismatchNote
    FROM dbo.z_tb_ZReport z
    JOIN dbo.z_tb_Terminal t ON t.TerminalId = z.TerminalId
    LEFT JOIN dbo.z_tb_User u ON u.LoginName = z.CashierId
    LEFT JOIN (SELECT TerminalId, ZNo, COUNT(*) AS Moves,
                      SUM(CASE WHEN Kind = 1 THEN Amount ELSE 0 END) AS OpeningCash,
                      SUM(CASE WHEN Kind = 2 THEN Amount ELSE 0 END) AS PaidIn,
                      SUM(CASE WHEN Kind = 3 THEN Amount ELSE 0 END) AS PaidOut
               FROM dbo.z_tb_CashMovement WHERE Status = 1
               GROUP BY TerminalId, ZNo) m ON m.TerminalId = z.TerminalId AND m.ZNo = z.ZNo
    LEFT JOIN (SELECT s.TerminalId, s.ZNo, SUM(s.Discount) AS BillDiscount, SUM(ISNULL(li.Disc, 0)) AS ItemDiscount
               FROM dbo.z_tb_SalesInvoice s
               LEFT JOIN (SELECT InvoiceId, SUM(Discount) AS Disc FROM dbo.z_tb_SalesInvoiceItem GROUP BY InvoiceId) li
                      ON li.InvoiceId = s.InvoiceId
               WHERE s.Status <> 9 AND s.InvType = 1
                 AND EXISTS (SELECT 1 FROM dbo.z_tb_ZReport zz
                             WHERE zz.TerminalId = s.TerminalId AND zz.ZNo = s.ZNo AND zz.BusinessDate = @Date)
               GROUP BY s.TerminalId, s.ZNo) d ON d.TerminalId = z.TerminalId AND d.ZNo = z.ZNo
    WHERE z.BusinessDate = @Date AND z.LocationId = @LocationId
      AND (@TerminalId IS NULL OR z.TerminalId = @TerminalId)
    ORDER BY z.TerminalId, z.ZNo;
END
GO
-- Every opening cash / paid in / paid out of the day (till time), replaced opening cash too (Status 9).
CREATE PROCEDURE dbo.z_sp_DayReportCash
    @Date DATE, @LocationId INT = 1, @TerminalId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @From DATETIME, @To DATETIME;
    SET @From = @Date;
    SET @To = DATEADD(DAY, 1, @From);

    SELECT m.TerminalId, t.TerminalCode, m.ZNo, m.MoveId, m.Kind, m.Amount, m.Reason, m.CashierId,
           u.UserName AS CashierName, m.CreatedAt, m.Status
    FROM dbo.z_tb_CashMovement m
    JOIN dbo.z_tb_Terminal t ON t.TerminalId = m.TerminalId
    LEFT JOIN dbo.z_tb_User u ON u.LoginName = m.CashierId
    WHERE m.CreatedAt >= @From AND m.CreatedAt < @To AND m.LocationId = @LocationId
      AND (@TerminalId IS NULL OR m.TerminalId = @TerminalId)
    ORDER BY m.CreatedAt, m.TerminalId, m.MoveId;
END
GO
-- Every item sold / refunded that day, voided bills left out. Refunds count negative in Net*.
-- Amount = the line amounts (after the item discount, before the bill discount - that is on the bill only).
-- Other items (ItemId 0, not in the item list) are one row per name the cashier typed.
CREATE PROCEDURE dbo.z_sp_DayReportItems
    @Date DATE, @LocationId INT = 1, @TerminalId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @From DATETIME, @To DATETIME;
    SET @From = @Date;
    SET @To = DATEADD(DAY, 1, @From);

    SELECT x.ItemId, i.RefCode, i.Barcode,
           CASE WHEN x.ItemId = 0 THEN ISNULL(x.LineDescrip, N'Other item') ELSE ISNULL(i.Inv_Descrip, i.Descrip) END AS Name,
           CAST(CASE WHEN x.ItemId = 0 THEN 1 ELSE 0 END AS BIT) AS IsOther,
           x.SoldQty, x.RefundQty, x.SoldQty - x.RefundQty AS NetQty,
           x.SoldAmount, x.RefundAmount, x.SoldAmount - x.RefundAmount AS NetAmount,
           x.Discount, x.Bills, x.MinPrice, x.MaxPrice
    FROM (SELECT it.ItemId, CASE WHEN it.ItemId = 0 THEN it.LineDescrip END AS LineDescrip,
                 CAST(SUM(CASE WHEN s.InvType = 1 THEN it.Qty ELSE 0 END) AS DECIMAL(18,3)) AS SoldQty,
                 CAST(SUM(CASE WHEN s.InvType = 2 THEN it.Qty ELSE 0 END) AS DECIMAL(18,3)) AS RefundQty,
                 CAST(SUM(CASE WHEN s.InvType = 1 THEN it.Amount ELSE 0 END) AS DECIMAL(18,2)) AS SoldAmount,
                 CAST(SUM(CASE WHEN s.InvType = 2 THEN it.Amount ELSE 0 END) AS DECIMAL(18,2)) AS RefundAmount,
                 CAST(SUM(CASE WHEN s.InvType = 1 THEN it.Discount ELSE -it.Discount END) AS DECIMAL(18,2)) AS Discount,
                 COUNT(DISTINCT s.InvoiceId) AS Bills,
                 MIN(it.UnitPrice) AS MinPrice, MAX(it.UnitPrice) AS MaxPrice
          FROM dbo.z_tb_SalesInvoice s
          JOIN dbo.z_tb_SalesInvoiceItem it ON it.InvoiceId = s.InvoiceId
          WHERE s.InvDate >= @From AND s.InvDate < @To AND s.LocationId = @LocationId AND s.Status <> 9
            AND (@TerminalId IS NULL OR s.TerminalId = @TerminalId)
          GROUP BY it.ItemId, CASE WHEN it.ItemId = 0 THEN it.LineDescrip END) x
    LEFT JOIN dbo.z_tb_Item i ON i.ItemId = x.ItemId AND x.ItemId <> 0
    ORDER BY x.SoldAmount - x.RefundAmount DESC, Name;
END
GO
-- Every bill of the day (voided ones too, Status 9), newest first, with how it was paid.
CREATE PROCEDURE dbo.z_sp_DayReportBills
    @Date DATE, @LocationId INT = 1, @TerminalId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @From DATETIME, @To DATETIME;
    SET @From = @Date;
    SET @To = DATEADD(DAY, 1, @From);

    SELECT s.InvoiceId, s.InvoiceNo, s.TerminalId, t.TerminalCode, s.ZNo, s.InvType, s.InvDate, s.CashierId,
           u.UserName AS CashierName, s.GrossAmount, s.Discount, s.NetAmount, s.Status, s.PriceType,
           (SELECT COUNT(*) FROM dbo.z_tb_SalesInvoiceItem it WHERE it.InvoiceId = s.InvoiceId) AS Lines,
           ISNULL((SELECT SUM(it.Discount) FROM dbo.z_tb_SalesInvoiceItem it WHERE it.InvoiceId = s.InvoiceId), 0) AS ItemDiscount,
           ISNULL((SELECT SUM(p.Amount) FROM dbo.z_tb_SalesPayment p WHERE p.InvoiceId = s.InvoiceId AND p.PayType = 1), 0) AS Cash,
           ISNULL((SELECT SUM(p.Amount) FROM dbo.z_tb_SalesPayment p WHERE p.InvoiceId = s.InvoiceId AND p.PayType = 2), 0) AS Card,
           ISNULL((SELECT SUM(p.Amount) FROM dbo.z_tb_SalesPayment p WHERE p.InvoiceId = s.InvoiceId AND p.PayType NOT IN (1, 2)), 0) AS OtherPay
    FROM dbo.z_tb_SalesInvoice s
    JOIN dbo.z_tb_Terminal t ON t.TerminalId = s.TerminalId
    LEFT JOIN dbo.z_tb_User u ON u.LoginName = s.CashierId
    WHERE s.InvDate >= @From AND s.InvDate < @To AND s.LocationId = @LocationId
      AND (@TerminalId IS NULL OR s.TerminalId = @TerminalId)
    ORDER BY s.InvDate DESC, s.InvoiceId DESC;
END
GO
-- One bill for the bill copy: header (no rows = not found) ...
CREATE PROCEDURE dbo.z_sp_DayReportBill
    @InvoiceNo VARCHAR(30)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT s.InvoiceId, s.InvoiceNo, s.TerminalId, t.TerminalCode, t.TerminalName, s.ZNo, s.InvType, s.InvDate,
           s.CashierId, u.UserName AS CashierName, s.GrossAmount, s.Discount, s.NetAmount, s.Status, s.PriceType,
           ISNULL((SELECT SUM(it.Discount) FROM dbo.z_tb_SalesInvoiceItem it WHERE it.InvoiceId = s.InvoiceId), 0) AS ItemDiscount,
           ISNULL((SELECT SUM(it.Qty) FROM dbo.z_tb_SalesInvoiceItem it WHERE it.InvoiceId = s.InvoiceId), 0) AS TotalQty
    FROM dbo.z_tb_SalesInvoice s
    JOIN dbo.z_tb_Terminal t ON t.TerminalId = s.TerminalId
    LEFT JOIN dbo.z_tb_User u ON u.LoginName = s.CashierId
    WHERE s.InvoiceNo = @InvoiceNo;
END
GO
-- ... its lines ...
CREATE PROCEDURE dbo.z_sp_DayReportBillLines
    @InvoiceNo VARCHAR(30)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT it.LineNum, it.ItemId, i.RefCode, i.Barcode,
           CASE WHEN it.ItemId = 0 THEN ISNULL(it.LineDescrip, N'Other item') ELSE ISNULL(i.Inv_Descrip, i.Descrip) END AS Name,
           it.Qty, it.UnitPrice, it.Discount, it.Amount, it.PriceType
    FROM dbo.z_tb_SalesInvoice s
    JOIN dbo.z_tb_SalesInvoiceItem it ON it.InvoiceId = s.InvoiceId
    LEFT JOIN dbo.z_tb_Item i ON i.ItemId = it.ItemId AND it.ItemId <> 0
    WHERE s.InvoiceNo = @InvoiceNo
    ORDER BY it.LineNum;
END
GO
-- ... and how it was paid (PayType 1 cash, 2 card, 3 credit, 4 voucher, 5 bank transfer, 6 cheque).
CREATE PROCEDURE dbo.z_sp_DayReportBillPayments
    @InvoiceNo VARCHAR(30)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT p.LineNum, p.PayType, p.Amount, p.RefNo
    FROM dbo.z_tb_SalesInvoice s
    JOIN dbo.z_tb_SalesPayment p ON p.InvoiceId = s.InvoiceId
    WHERE s.InvoiceNo = @InvoiceNo
    ORDER BY p.LineNum;
END
GO
SET NOEXEC OFF;
GO
PRINT 'U018 back office: day reports (z_tb_CashMovement, z_sp_SyncCashMovements, z_sp_DayReport*).';
GO
