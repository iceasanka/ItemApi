/* =============================================================================
   U040_Till_CashBackReport.sql   (2026-11-02)
   Update for a till db (z_pos_fnt_db) that is ALREADY deployed. SQL Server 2008 R2 and newer.
   Safe to run again. One new read-only procedure; no table or data change.

   What changes (cash back on bills shown on its own line):
     - zf_sp_GetCashBack @ZNo: the cash paid back on sale bills under 0 (U039 cash back - the items back worth more
       than the items sold) of one Z: CashBack (the amount, plus) and CashBackBills (how many bills).
       TillService shows it on the drawer summary, the X report and the Z slip as "- Cash back on bills"; "+ Cash
       sales" is then before it. CASH IN DRAWER is not changed (the cash back was always in the cash sales).
       It is NOT a paid out: zf_tb_CashMovement is not touched.
   Same change in the full script: 02_FrontCashier_zf.sql.

   Order, on each till (after U039):
     1. sqlcmd -S .\SQLEXPRESS -d z_pos_fnt_db -E -I -b -i U040_Till_CashBackReport.sql
     2. install the new TillService and billing page (the old ones keep working after the script; the new
        TillService works without it too - no cash back line then)
   ============================================================================= */
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
IF OBJECT_ID(N'dbo.zf_tb_Invoice', 'U') IS NULL OR OBJECT_ID(N'dbo.zf_tb_InvoicePayment', 'U') IS NULL
BEGIN
    RAISERROR('This is not a till database (zf_tb_Invoice / zf_tb_InvoicePayment not found) - nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
GO

IF OBJECT_ID(N'dbo.zf_sp_GetCashBack', 'P') IS NOT NULL DROP PROCEDURE dbo.zf_sp_GetCashBack;
GO
-- Cash back (U039) of one Z: the cash paid out on sale bills that came to less than 0 (their CASH payment is minus).
-- CashBack is plus (the money that went out); it is part of the cash sales (CashAmount / CashSales) already.
CREATE PROCEDURE dbo.zf_sp_GetCashBack
    @ZNo INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT ISNULL(SUM(-p.Amount), 0) AS CashBack, COUNT(DISTINCT i.InvoiceNo) AS CashBackBills
    FROM dbo.zf_tb_Invoice i JOIN dbo.zf_tb_InvoicePayment p ON p.InvoiceNo = i.InvoiceNo
    WHERE i.ZNo = @ZNo AND i.Status <> 9 AND i.InvType = 1 AND p.PayType = 1 AND p.Amount < 0;
END
GO

SET NOEXEC OFF;
GO
PRINT 'U040_Till_CashBackReport done.';
GO
