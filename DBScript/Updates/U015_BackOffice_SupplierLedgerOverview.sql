/* =============================================================================
   U015_BackOffice_SupplierLedgerOverview.sql   (2026-10-23)
   Run on: back office db (easyway) that has U007. SQL Server 2008 R2 and newer. Safe to run again.
   Read-only procedures - no table or data is changed. Then the new ItemApi.
   Same procedures in the full script DBScript/15_BackOffice_SupplierPayments.sql - change both together.

   Supplier Ledger page overview (StockSystem.md section 6.19):
     z_sp_GetSupplierLedgerOverview  one row per supplier with ledger entries: purchases, payments, returns,
                                     balance, open bills, aging of what is still open (by days past the due date),
                                     due in the next 7 days, payments not set against a bill, average days to pay,
                                     last purchase / payment
     z_sp_GetSupplierLedgerMonthly   purchases / payments / returns per month (all suppliers or one)

   sqlcmd -S <server> -d easyway -E -I -b -i U015_BackOffice_SupplierLedgerOverview.sql
   ============================================================================= */
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
IF OBJECT_ID(N'dbo.z_tb_SupplierLedger', 'U') IS NULL OR OBJECT_ID(N'dbo.z_tb_SupplierPaymentAlloc', 'U') IS NULL
BEGIN
    RAISERROR('This is not the back office database with U007 (z_tb_SupplierLedger / z_tb_SupplierPaymentAlloc not found) - nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
GO
IF OBJECT_ID('dbo.z_sp_GetSupplierLedgerOverview', 'P') IS NOT NULL DROP PROCEDURE dbo.z_sp_GetSupplierLedgerOverview;
IF OBJECT_ID('dbo.z_sp_GetSupplierLedgerMonthly', 'P') IS NOT NULL DROP PROCEDURE dbo.z_sp_GetSupplierLedgerMonthly;
GO
-- ---- every supplier with ledger entries: totals, balance and the aging of the open bills.
--      Days past due = today - DueDate (a bill with no due date is "not due"). Unallocated = payments + returns
--      not set against a bill (Balance = OpenAmount - Unallocated).
CREATE PROCEDURE dbo.z_sp_GetSupplierLedgerOverview
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Today DATE; SET @Today = GETDATE();

    WITH t AS (
        SELECT l.SuppId,
               SUM(CASE WHEN l.Type = 1 THEN ISNULL(l.DebitAmount, 0) ELSE 0 END) AS Purchases,
               SUM(CASE WHEN l.Type = 2 THEN ISNULL(l.CreditAmount, 0) ELSE 0 END) AS Payments,
               SUM(CASE WHEN l.Type = 3 THEN ISNULL(l.CreditAmount, 0) ELSE 0 END) AS Returns,
               SUM(ISNULL(l.DebitAmount, 0) - ISNULL(l.CreditAmount, 0)) AS Balance,
               SUM(ISNULL(l.CreditAmount, 0)) AS Credits,
               COUNT(*) AS Entries,
               MAX(CASE WHEN l.Type = 1 THEN l.TxnDate END) AS LastPurchaseDate,
               MAX(CASE WHEN l.Type = 2 THEN l.TxnDate END) AS LastPaymentDate
        FROM dbo.z_tb_SupplierLedger l
        WHERE l.SuppId IS NOT NULL
        GROUP BY l.SuppId
    ), b AS (
        SELECT l.SuppId, l.DueDate,
               ISNULL(l.DebitAmount, 0) - ISNULL(p.Amount, 0) AS OpenAmt,
               CASE WHEN l.DueDate IS NULL THEN 0 ELSE DATEDIFF(DAY, l.DueDate, @Today) END AS PastDue
        FROM dbo.z_tb_SupplierLedger l
        OUTER APPLY (SELECT SUM(a.Amount) AS Amount FROM dbo.z_tb_SupplierPaymentAlloc a WHERE a.InvoiceLedgerId = l.LedgerId) p
        WHERE l.Type = 1 AND l.SuppId IS NOT NULL
    ), o AS (
        SELECT SuppId,
               COUNT(*) AS OpenBills,
               SUM(OpenAmt) AS OpenAmount,
               SUM(CASE WHEN PastDue <= 0 THEN OpenAmt ELSE 0 END) AS NotDue,
               SUM(CASE WHEN PastDue > 0 THEN OpenAmt ELSE 0 END) AS Overdue,
               SUM(CASE WHEN PastDue BETWEEN -7 AND 0 AND DueDate IS NOT NULL THEN OpenAmt ELSE 0 END) AS DueIn7,
               SUM(CASE WHEN PastDue BETWEEN 1 AND 30 THEN OpenAmt ELSE 0 END) AS Over1To30,
               SUM(CASE WHEN PastDue BETWEEN 31 AND 60 THEN OpenAmt ELSE 0 END) AS Over31To60,
               SUM(CASE WHEN PastDue BETWEEN 61 AND 90 THEN OpenAmt ELSE 0 END) AS Over61To90,
               SUM(CASE WHEN PastDue > 90 THEN OpenAmt ELSE 0 END) AS Over90,
               MIN(DueDate) AS OldestDueDate
        FROM b
        WHERE OpenAmt > 0
        GROUP BY SuppId
    ), a AS (
        -- what the payments / returns of a supplier pay, and after how many days (weighted by the amount)
        SELECT pl.SuppId,
               SUM(x.Amount) AS Allocated,
               SUM(CASE WHEN pl.Type = 2 THEN x.Amount ELSE 0 END) AS PaidAlloc,
               SUM(CASE WHEN pl.Type = 2 THEN x.Amount * DATEDIFF(DAY, il.TxnDate, pl.TxnDate) ELSE 0 END) AS PaidDays
        FROM dbo.z_tb_SupplierPaymentAlloc x
        JOIN dbo.z_tb_SupplierLedger pl ON pl.LedgerId = x.PaymentLedgerId
        JOIN dbo.z_tb_SupplierLedger il ON il.LedgerId = x.InvoiceLedgerId
        GROUP BY pl.SuppId
    )
    SELECT t.SuppId, s.SuppCode, s.SuppName, s.CreditDays,
           CAST(t.Purchases AS DECIMAL(18,2)) AS Purchases,
           CAST(t.Payments AS DECIMAL(18,2)) AS Payments,
           CAST(t.Returns AS DECIMAL(18,2)) AS Returns,
           CAST(t.Balance AS DECIMAL(18,2)) AS Balance,
           ISNULL(o.OpenBills, 0) AS OpenBills,
           CAST(ISNULL(o.OpenAmount, 0) AS DECIMAL(18,2)) AS OpenAmount,
           CAST(ISNULL(o.NotDue, 0) AS DECIMAL(18,2)) AS NotDue,
           CAST(ISNULL(o.Overdue, 0) AS DECIMAL(18,2)) AS Overdue,
           CAST(ISNULL(o.DueIn7, 0) AS DECIMAL(18,2)) AS DueIn7,
           CAST(ISNULL(o.Over1To30, 0) AS DECIMAL(18,2)) AS Over1To30,
           CAST(ISNULL(o.Over31To60, 0) AS DECIMAL(18,2)) AS Over31To60,
           CAST(ISNULL(o.Over61To90, 0) AS DECIMAL(18,2)) AS Over61To90,
           CAST(ISNULL(o.Over90, 0) AS DECIMAL(18,2)) AS Over90,
           o.OldestDueDate,
           CAST(t.Credits - ISNULL(a.Allocated, 0) AS DECIMAL(18,2)) AS Unallocated,
           CAST(CASE WHEN ISNULL(a.PaidAlloc, 0) > 0 THEN a.PaidDays / a.PaidAlloc END AS DECIMAL(18,1)) AS AvgDaysToPay,
           t.Entries, t.LastPurchaseDate, t.LastPaymentDate
    FROM t
    JOIN dbo.z_tb_Supplier s ON s.SuppId = t.SuppId
    LEFT JOIN o ON o.SuppId = t.SuppId
    LEFT JOIN a ON a.SuppId = t.SuppId
    ORDER BY t.Balance DESC, s.SuppName;
END
GO
-- ---- purchases / payments / returns per month for the last @Months months (this month included),
--      all suppliers (@SuppId NULL) or one. Months with no entries are not returned.
CREATE PROCEDURE dbo.z_sp_GetSupplierLedgerMonthly
    @SuppId INT = NULL,
    @Months INT = 12
AS
BEGIN
    SET NOCOUNT ON;
    IF @Months IS NULL OR @Months < 1 SET @Months = 12;
    IF @Months > 60 SET @Months = 60;
    DECLARE @From DATETIME; SET @From = DATEADD(MONTH, DATEDIFF(MONTH, 0, GETDATE()) - (@Months - 1), 0);
    SELECT DATEADD(MONTH, DATEDIFF(MONTH, 0, l.TxnDate), 0) AS MonthStart,
           CAST(SUM(CASE WHEN l.Type = 1 THEN ISNULL(l.DebitAmount, 0) ELSE 0 END) AS DECIMAL(18,2)) AS Purchases,
           CAST(SUM(CASE WHEN l.Type = 2 THEN ISNULL(l.CreditAmount, 0) ELSE 0 END) AS DECIMAL(18,2)) AS Payments,
           CAST(SUM(CASE WHEN l.Type = 3 THEN ISNULL(l.CreditAmount, 0) ELSE 0 END) AS DECIMAL(18,2)) AS Returns
    FROM dbo.z_tb_SupplierLedger l
    WHERE l.TxnDate >= @From
      AND (@SuppId IS NULL OR l.SuppId = @SuppId)
    GROUP BY DATEADD(MONTH, DATEDIFF(MONTH, 0, l.TxnDate), 0)
    ORDER BY MonthStart;
END
GO
PRINT 'U015 back office: supplier ledger overview procedures are ready.';
GO
SET NOEXEC OFF;
GO
