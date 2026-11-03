/* =============================================================================
   U046_BackOffice_DayReportCardSettlement.sql   (2026-11-03)
   Update for a back office db (easyway) that is ALREADY deployed (U041 + U045 run). SQL Server 2008 R2 and newer.
   Safe to run again. No table or data change.

   What changes (Sales > Day reports): the card machine settlement typed at day end (U045) on the Day Reports page.
     - z_sp_DayReportZ gets CardSettlement (z_tb_ZReport.CardSettlement, NULL = not entered).
   Page: Day end (Z) tab - a "Card machine" column (the settlement, the difference from the card sales in red);
   Summary > Payments - card machine settlement of the day's Zs and the card difference.
   Same change in the full script: 21_BackOffice_DayReports.sql (this script = that proc, with U041's cash back).

   Run:  sqlcmd -S <server> -d easyway -E -I -b -i U046_BackOffice_DayReportCardSettlement.sql
   Then: the new ItemApi and the back office UI (the old ItemApi keeps working after it - extra column not read).
   ============================================================================= */
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
IF OBJECT_ID(N'dbo.z_tb_ZReport', 'U') IS NULL OR COL_LENGTH('dbo.z_tb_ZReport', 'CardSettlement') IS NULL
BEGIN
    RAISERROR('Run U045_BackOffice_CardSettlement.sql first (z_tb_ZReport.CardSettlement not found) - nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
GO
IF OBJECT_ID(N'dbo.z_sp_DayReportZ', 'P') IS NOT NULL DROP PROCEDURE dbo.z_sp_DayReportZ;
GO
-- The Zs (cashier day ends) whose business date is @Date, with the drawer cash: opening cash, paid in, paid out
-- (from z_tb_CashMovement of that Z) and the expected cash. Discounts from the Z's bills on the server.
-- Status 2 received, 3 reconciled, 4 mismatch.
-- CashBack / CashBackBills (U041): cash paid back on the Z's sale bills under 0 - already inside CashAmount.
-- CardSettlement (U046): card machine settlement typed at day end (U045), NULL = not entered.
CREATE PROCEDURE dbo.z_sp_DayReportZ
    @Date DATE, @LocationId INT = 1, @TerminalId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT z.ZId, z.TerminalId, t.TerminalCode, z.ZNo, z.BusinessDate, z.CashierId, u.UserName AS CashierName,
           z.OpenedAt, z.ClosedAt, z.InvoiceCount, z.SalesAmount, z.RefundAmount, z.NetSales,
           z.CashAmount, z.CardAmount, z.OtherAmount, z.BankAmount, z.ChequeAmount, z.CardSettlement,
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
PRINT 'U046 back office: card machine settlement on the Day Reports Z list (z_sp_DayReportZ).';
GO
