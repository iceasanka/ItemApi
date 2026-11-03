/* =============================================================================
   U047_BackOffice_ZReportDetails.sql   (2026-11-03)
   Update for a back office db (easyway) that is ALREADY deployed (the void log of the Voids report on it).
   SQL Server 2008 R2 and newer. Safe to run again. No table or data change.

   What changes (Tills > Z report page): the details of one Z - item / sub total discounts, refund bills, exchanges
   (items brought back on sale bills) and voids (void lines, void bills, qty cuts).
     - new z_sp_ZReportDetails @TerminalId, @ZNo (from the Z's bills and void log on the server).
   Same change in the full script: 22_BackOffice_VoidReport.sql.

   Run:  sqlcmd -S <server> -d easyway -E -I -b -i U047_BackOffice_ZReportDetails.sql
   Then: the new ItemApi and the back office UI (the new ItemApi without this script: the page just shows no details).
   ============================================================================= */
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
IF OBJECT_ID(N'dbo.z_tb_TillVoidLog', 'U') IS NULL OR OBJECT_ID(N'dbo.z_tb_SalesInvoiceItem', 'U') IS NULL
BEGIN
    RAISERROR('z_tb_TillVoidLog / z_tb_SalesInvoiceItem not found - run the earlier updates first. Nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
GO
IF OBJECT_ID(N'dbo.z_sp_ZReportDetails', 'P') IS NOT NULL DROP PROCEDURE dbo.z_sp_ZReportDetails;
GO
-- Detail lines of one Z (Tills > Z report page, U047), from the Z's bills and void log on the server - bills the till
-- has not sent yet are not in it. One row. Amounts plus; voided bills (Status 9) left out of the bill figures.
-- ItemDiscount / BillDiscount: line and sub total discounts of the sale bills (as the till Z).
-- Exchange: sale bills with items brought back (minus lines); ExchangeAmount = those lines, already inside the sales.
-- Voids (z_tb_TillVoidLog, lines of refund bills left out as the Voids report): Kind 1 void line, 2 void bill
-- (bills = groups), 3 qty made smaller.
CREATE PROCEDURE dbo.z_sp_ZReportDetails
    @TerminalId INT, @ZNo INT, @LocationId INT = 1
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        ISNULL((SELECT SUM(it.Discount) FROM dbo.z_tb_SalesInvoice s JOIN dbo.z_tb_SalesInvoiceItem it ON it.InvoiceId = s.InvoiceId
                WHERE s.TerminalId = @TerminalId AND s.ZNo = @ZNo AND s.LocationId = @LocationId AND s.Status <> 9 AND s.InvType = 1), 0) AS ItemDiscount,
        ISNULL((SELECT SUM(s.Discount) FROM dbo.z_tb_SalesInvoice s
                WHERE s.TerminalId = @TerminalId AND s.ZNo = @ZNo AND s.LocationId = @LocationId AND s.Status <> 9 AND s.InvType = 1), 0) AS BillDiscount,
        (SELECT COUNT(*) FROM dbo.z_tb_SalesInvoice s
         WHERE s.TerminalId = @TerminalId AND s.ZNo = @ZNo AND s.LocationId = @LocationId AND s.Status <> 9 AND s.InvType = 2) AS RefundBills,
        ISNULL((SELECT SUM(s.NetAmount) FROM dbo.z_tb_SalesInvoice s
                WHERE s.TerminalId = @TerminalId AND s.ZNo = @ZNo AND s.LocationId = @LocationId AND s.Status <> 9 AND s.InvType = 2), 0) AS RefundAmount,
        (SELECT COUNT(DISTINCT s.InvoiceId) FROM dbo.z_tb_SalesInvoice s JOIN dbo.z_tb_SalesInvoiceItem it ON it.InvoiceId = s.InvoiceId
         WHERE s.TerminalId = @TerminalId AND s.ZNo = @ZNo AND s.LocationId = @LocationId AND s.Status <> 9 AND s.InvType = 1 AND it.Amount < 0) AS ExchangeBills,
        ISNULL((SELECT SUM(-it.Amount) FROM dbo.z_tb_SalesInvoice s JOIN dbo.z_tb_SalesInvoiceItem it ON it.InvoiceId = s.InvoiceId
                WHERE s.TerminalId = @TerminalId AND s.ZNo = @ZNo AND s.LocationId = @LocationId AND s.Status <> 9 AND s.InvType = 1 AND it.Amount < 0), 0) AS ExchangeAmount,
        ISNULL(v.VoidLines, 0) AS VoidLines, ISNULL(v.VoidLineAmount, 0) AS VoidLineAmount,
        ISNULL(v.VoidBills, 0) AS VoidBills, ISNULL(v.VoidBillAmount, 0) AS VoidBillAmount,
        ISNULL(v.QtyCuts, 0) AS QtyCuts, ISNULL(v.QtyCutAmount, 0) AS QtyCutAmount
    FROM (SELECT SUM(CASE WHEN Kind = 1 THEN 1 ELSE 0 END) AS VoidLines,
                 SUM(CASE WHEN Kind = 1 THEN Amount ELSE 0 END) AS VoidLineAmount,
                 COUNT(DISTINCT CASE WHEN Kind = 2 THEN GroupNo END) AS VoidBills,
                 SUM(CASE WHEN Kind = 2 THEN Amount ELSE 0 END) AS VoidBillAmount,
                 SUM(CASE WHEN Kind = 3 THEN 1 ELSE 0 END) AS QtyCuts,
                 SUM(CASE WHEN Kind = 3 THEN Amount ELSE 0 END) AS QtyCutAmount
          FROM dbo.z_tb_TillVoidLog
          WHERE TerminalId = @TerminalId AND ZNo = @ZNo AND LocationId = @LocationId AND Refund = 0) v;
END
GO
SET NOEXEC OFF;
GO
PRINT 'U047 back office: z_sp_ZReportDetails.';
GO
