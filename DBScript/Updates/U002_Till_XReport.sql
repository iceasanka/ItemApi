/* =============================================================================
   U002_Till_XReport.sql   (2026-10-12)
   Update for a till db (z_pos_fnt_db) that is ALREADY deployed. SQL Server 2008 R2 and newer.
   Safe to run again. Tables, bills, Z reports and cash data are not touched.

   What changes (X report, Docs/StockSystem.md 6.8):
     - new procedure zf_sp_GetXReport: the totals of the open Z, read only (nothing is closed)
   Same change in the full script: 02_FrontCashier_zf.sql.

   No back office script. On each till (the running TillService can stay up - it does not use this procedure yet):
     1. sqlcmd -S .\SQLEXPRESS -d z_pos_fnt_db -E -I -b -i U002_Till_XReport.sql
     2. install the new TillService (GET /x, POST /x/print need this procedure)
   ============================================================================= */
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
IF OBJECT_ID(N'dbo.zf_tb_ZReport', 'U') IS NULL OR OBJECT_ID(N'dbo.zf_tb_Config', 'U') IS NULL
   OR OBJECT_ID(N'dbo.zf_tb_CashMovement', 'U') IS NULL
BEGIN
    RAISERROR('This is not a till database (zf_tb_ZReport / zf_tb_Config / zf_tb_CashMovement not found) - nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
GO
IF OBJECT_ID(N'dbo.zf_sp_GetXReport', 'P') IS NOT NULL DROP PROCEDURE dbo.zf_sp_GetXReport;
GO
-- X report: the totals of the OPEN Z as zf_sp_CloseZ would store them right now - read only, nothing is closed or
-- changed. Same columns as the zf_sp_CloseZ answer (ClosedAt NULL, Status 0); no rows when no Z is open.
-- The rules here must match zf_sp_CloseZ.
CREATE PROCEDURE dbo.zf_sp_GetXReport
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @ZNo INT = (SELECT MAX(ZNo) FROM dbo.zf_tb_ZReport WHERE Status = 0);

    SELECT z.ZNo, z.BusinessDate, z.CashierId, z.OpenedAt, CAST(NULL AS DATETIME) AS ClosedAt, z.FromSeq, z.ToSeq,
           b.InvoiceCount, l.LineCount, l.TotalQty, b.SalesAmount, b.RefundAmount,
           b.SalesAmount - b.RefundAmount AS NetSales,
           p.CashAmount, p.CardAmount, p.OtherAmount, m.OpeningCash, m.PaidIn, m.PaidOut,
           m.OpeningCash + p.CashAmount + m.PaidIn - m.PaidOut AS ExpectedCash, z.Status
    FROM dbo.zf_tb_ZReport z
    CROSS APPLY (SELECT COUNT(*) AS InvoiceCount,
                        ISNULL(SUM(CASE WHEN Status <> 9 AND InvType = 1 THEN NetAmount END), 0) AS SalesAmount,
                        ISNULL(SUM(CASE WHEN Status <> 9 AND InvType = 2 THEN NetAmount END), 0) AS RefundAmount
                 FROM dbo.zf_tb_Invoice WHERE ZNo = z.ZNo) b
    CROSS APPLY (SELECT COUNT(*) AS LineCount,
                        ISNULL(SUM(CASE WHEN i.InvType = 2 THEN -it.Qty ELSE it.Qty END), 0) AS TotalQty
                 FROM dbo.zf_tb_Invoice i JOIN dbo.zf_tb_InvoiceItem it ON it.InvoiceNo = i.InvoiceNo
                 WHERE i.ZNo = z.ZNo AND i.Status <> 9) l
    CROSS APPLY (SELECT ISNULL(SUM(CASE WHEN x.PayType = 1 THEN x.Amount END), 0) AS CashAmount,
                        ISNULL(SUM(CASE WHEN x.PayType = 2 THEN x.Amount END), 0) AS CardAmount,
                        ISNULL(SUM(CASE WHEN x.PayType NOT IN (1, 2) THEN x.Amount END), 0) AS OtherAmount
                 FROM (SELECT p.PayType, CASE WHEN i.InvType = 2 THEN -p.Amount ELSE p.Amount END AS Amount
                       FROM dbo.zf_tb_Invoice i JOIN dbo.zf_tb_InvoicePayment p ON p.InvoiceNo = i.InvoiceNo
                       WHERE i.ZNo = z.ZNo AND i.Status <> 9) x) p
    CROSS APPLY (SELECT ISNULL(SUM(CASE WHEN Kind = 1 THEN Amount END), 0) AS OpeningCash,
                        ISNULL(SUM(CASE WHEN Kind = 2 THEN Amount END), 0) AS PaidIn,
                        ISNULL(SUM(CASE WHEN Kind = 3 THEN Amount END), 0) AS PaidOut
                 FROM dbo.zf_tb_CashMovement WHERE ZNo = z.ZNo AND Status = 1) m
    WHERE z.ZNo = @ZNo;
END
GO
PRINT 'U002 till: zf_sp_GetXReport created (X report).';
GO
SET NOEXEC OFF;
GO
