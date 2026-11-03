/* =============================================================================
   U042_BackOffice_BankChequeReport.sql   (2026-11-03)
   Update for a back office db (easyway) that is ALREADY deployed (U018 run). SQL Server 2008 R2 and newer.
   Safe to run again. No table or data change.

   What changes (back office Sales > Bank & cheque report, Docs/StockSystem.md 6.15):
     - new read-only z_sp_DayReportBankCheque: every bank transfer (PayType 5) and cheque (PayType 6) payment of the
       bills dated @From..@To (both days included), voided bills left out, refund bills negative - with the bill,
       till, Z, cashier and the reference / cheque number (RefNo). This is the list to match with the bank statement.
   Same change in the full script: 21_BackOffice_DayReports.sql.

   Run:  sqlcmd -S <server> -d easyway -E -I -b -i U042_BackOffice_BankChequeReport.sql
   Then: the new ItemApi (api/DayReport/BankCheque) and the back office UI. The old ItemApi keeps working after it.
   ============================================================================= */
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
IF OBJECT_ID(N'dbo.z_tb_SalesInvoice', 'U') IS NULL OR OBJECT_ID(N'dbo.z_tb_SalesPayment', 'U') IS NULL
   OR OBJECT_ID(N'dbo.z_tb_Terminal', 'U') IS NULL
BEGIN
    RAISERROR('This is not the back office database (z_tb_SalesInvoice / z_tb_SalesPayment / z_tb_Terminal not found) - nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
GO
IF OBJECT_ID(N'dbo.z_sp_DayReportBankCheque', 'P') IS NOT NULL DROP PROCEDURE dbo.z_sp_DayReportBankCheque;
GO
-- Bank transfer (5) and cheque (6) payments of the bills dated @From..@To (both included), oldest first.
-- Voided bills (Status 9) left out; refund bills (InvType 2) negative, like the till Z. @PayType NULL = both.
CREATE PROCEDURE dbo.z_sp_DayReportBankCheque
    @From DATE, @To DATE, @LocationId INT = 1, @TerminalId INT = NULL, @PayType INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @F DATETIME, @T DATETIME;
    SET @F = @From;
    SET @T = DATEADD(DAY, 1, CAST(@To AS DATETIME));

    SELECT s.InvoiceId, s.InvoiceNo, s.TerminalId, t.TerminalCode, s.ZNo, s.InvType, s.InvDate, s.CashierId,
           u.UserName AS CashierName, s.NetAmount, p.LineNum, p.PayType,
           CASE WHEN s.InvType = 2 THEN -p.Amount ELSE p.Amount END AS Amount,
           p.RefNo
    FROM dbo.z_tb_SalesInvoice s
    JOIN dbo.z_tb_SalesPayment p ON p.InvoiceId = s.InvoiceId
    JOIN dbo.z_tb_Terminal t ON t.TerminalId = s.TerminalId
    LEFT JOIN dbo.z_tb_User u ON u.LoginName = s.CashierId
    WHERE s.InvDate >= @F AND s.InvDate < @T AND s.LocationId = @LocationId AND s.Status <> 9
      AND p.PayType IN (5, 6)
      AND (@PayType IS NULL OR p.PayType = @PayType)
      AND (@TerminalId IS NULL OR s.TerminalId = @TerminalId)
    ORDER BY s.InvDate, s.InvoiceId, p.LineNum;
END
GO
SET NOEXEC OFF;
GO
PRINT 'U042 back office: bank transfer & cheque report (z_sp_DayReportBankCheque).';
GO
