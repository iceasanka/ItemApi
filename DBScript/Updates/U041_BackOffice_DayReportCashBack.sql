/* =============================================================================
   U041_BackOffice_DayReportCashBack.sql   (2026-11-02)
   Update for a back office db (easyway) that is ALREADY deployed (U018 run). SQL Server 2008 R2 and newer.
   Safe to run again. No table or data change.

   What changes (back office Day Reports page, Docs/StockSystem.md 6.25): cash back on bills on its own line.
     - z_sp_DayReportTills: new columns CashBack, CashBackBills (per till, by the bill date)
     - z_sp_DayReportZ: new columns CashBack, CashBackBills (per Z)
   Cash back (till db U039) = a sale bill under 0 - the items back worth more than the items sold, the difference paid
   out in cash (a minus CASH payment). CashBack is that cash, plus. It is already inside Cash / CashAmount, so the
   expected cash is not changed; it is NOT a paid out (z_tb_CashMovement is not touched).
   Same change in the full script: 21_BackOffice_DayReports.sql.

   Run:  sqlcmd -S <server> -d easyway -E -I -b -i U041_BackOffice_DayReportCashBack.sql
   Then: the new ItemApi and the back office UI (the new ItemApi needs this script - it reads the new columns).
         The old ItemApi keeps working after it (extra columns not read).
   ============================================================================= */
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
IF OBJECT_ID(N'dbo.z_tb_SalesInvoice', 'U') IS NULL OR OBJECT_ID(N'dbo.z_tb_SalesPayment', 'U') IS NULL
   OR OBJECT_ID(N'dbo.z_tb_CashMovement', 'U') IS NULL
BEGIN
    RAISERROR('This is not the back office database or U018 was not run (z_tb_SalesInvoice / z_tb_SalesPayment / z_tb_CashMovement not found) - nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
GO
IF OBJECT_ID(N'dbo.z_sp_DayReportTills', 'P') IS NOT NULL DROP PROCEDURE dbo.z_sp_DayReportTills;
IF OBJECT_ID(N'dbo.z_sp_DayReportZ', 'P') IS NOT NULL DROP PROCEDURE dbo.z_sp_DayReportZ;
GO
-- One row per till of the location (also tills without bills that day): the day's bills, discounts, sales and
-- payments, and the cash in / out of the drawer. Refunds count negative in the payment totals, like the till Z.
-- ExpectedCash = opening cash + cash (sales - refunds) + paid in - paid out.
-- CashBack (U041): cash paid back on sale bills under 0 (till U039 - the items back worth more than the items sold),
-- plus, with CashBackBills; already inside Cash (not a paid out) - shown on its own line.
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
           b.FirstBillAt, b.LastBillAt, m.LastMoveAt,
           ISNULL(cb.CashBack, 0) AS CashBack, ISNULL(cb.CashBackBills, 0) AS CashBackBills
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
    LEFT JOIN (SELECT s.TerminalId, SUM(-p.Amount) AS CashBack, COUNT(DISTINCT s.InvoiceId) AS CashBackBills
               FROM dbo.z_tb_SalesInvoice s JOIN dbo.z_tb_SalesPayment p ON p.InvoiceId = s.InvoiceId
               WHERE s.InvDate >= @From AND s.InvDate < @To AND s.LocationId = @LocationId AND s.Status <> 9
                 AND s.InvType = 1 AND p.PayType = 1 AND p.Amount < 0
               GROUP BY s.TerminalId) cb ON cb.TerminalId = t.TerminalId
    WHERE t.LocationId = @LocationId
      AND (@TerminalId IS NULL OR t.TerminalId = @TerminalId)
    ORDER BY t.TerminalId;
END
GO
-- The Zs (cashier day ends) whose business date is @Date, with the drawer cash: opening cash, paid in, paid out
-- (from z_tb_CashMovement of that Z) and the expected cash. Discounts from the Z's bills on the server.
-- Status 2 received, 3 reconciled, 4 mismatch.
-- CashBack / CashBackBills (U041): cash paid back on the Z's sale bills under 0 - already inside CashAmount.
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
           z.Status, z.MismatchNote,
           ISNULL(cb.CashBack, 0) AS CashBack, ISNULL(cb.CashBackBills, 0) AS CashBackBills
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
    LEFT JOIN (SELECT s.TerminalId, s.ZNo, SUM(-p.Amount) AS CashBack, COUNT(DISTINCT s.InvoiceId) AS CashBackBills
               FROM dbo.z_tb_SalesInvoice s JOIN dbo.z_tb_SalesPayment p ON p.InvoiceId = s.InvoiceId
               WHERE s.Status <> 9 AND s.InvType = 1 AND p.PayType = 1 AND p.Amount < 0
                 AND EXISTS (SELECT 1 FROM dbo.z_tb_ZReport zz
                             WHERE zz.TerminalId = s.TerminalId AND zz.ZNo = s.ZNo AND zz.BusinessDate = @Date)
               GROUP BY s.TerminalId, s.ZNo) cb ON cb.TerminalId = z.TerminalId AND cb.ZNo = z.ZNo
    WHERE z.BusinessDate = @Date AND z.LocationId = @LocationId
      AND (@TerminalId IS NULL OR z.TerminalId = @TerminalId)
    ORDER BY z.TerminalId, z.ZNo;
END
GO
SET NOEXEC OFF;
GO
PRINT 'U041 back office: day report cash back (z_sp_DayReportTills, z_sp_DayReportZ).';
GO
