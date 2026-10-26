/* =============================================================================
   F001_BackOffice_NAND001_LedgerAllocations.sql   (2026-10-26)
   One-time data fix on the back office db (easyway). SQL Server 2008 R2 and newer.
   STATUS: run on production 2026-10-26 - done. Do not run again (it would find nothing to set and stop).

   Supplier Nandana (NAND001) ledger restarted at 0: the old bills were deleted (01053023 too) and one purchase
   "TO get 0" (1,244,190.00) was added by hand on the Supplier Ledger page. Balance was 0, but the page showed
   1 open bill and 1,244,190.00 "Not set against a bill" - the cheque payments paid no bill. This sets every
   payment / return of the supplier that is not (fully) set against a bill against "TO get 0".
   The page cannot do it: a payment made by a written cheque cannot be edited there.

   Only adds z_tb_SupplierPaymentAlloc rows (ChequeId NULL = "set on the ledger page"); no ledger entry or
   cheque is changed. Stops without a change when the bill is not found or the amounts differ.
   @DryRun = 1 only shows; set it to 0 and run again to do it.
   ============================================================================= */
SET NOCOUNT ON;
DECLARE @DryRun BIT;
SET @DryRun = 1;

DECLARE @SuppId INT, @Bill INT;
DECLARE @BillOpen DECIMAL(18,2), @Free DECIMAL(18,2);

SELECT @SuppId = SuppId
FROM dbo.z_tb_Supplier
WHERE SuppCode = 'NAND001';

SELECT @Bill = LedgerId
FROM dbo.z_tb_SupplierLedger
WHERE SuppId = @SuppId
  AND Type = 1
  AND InvoiceNo = N'TO get 0';

IF @Bill IS NULL
BEGIN
    RAISERROR('Bill "TO get 0" of NAND001 not found - nothing changed.', 16, 1);
    RETURN;
END

-- what each payment / return already pays
DECLARE @used TABLE (LedgerId INT PRIMARY KEY, Used DECIMAL(18,2));
INSERT @used (LedgerId, Used)
SELECT x.PaymentLedgerId, SUM(x.Amount)
FROM dbo.z_tb_SupplierPaymentAlloc x
GROUP BY x.PaymentLedgerId;

DECLARE @p TABLE (
    LedgerId    INT PRIMARY KEY,
    ReferenceId NVARCHAR(100),
    Remark      NVARCHAR(500),
    Credit      DECIMAL(18,2),
    NotSet      DECIMAL(18,2)
);
INSERT @p (LedgerId, ReferenceId, Remark, Credit, NotSet)
SELECT l.LedgerId, l.ReferenceId, l.Remark, l.CreditAmount,
       l.CreditAmount - ISNULL(u.Used, 0)
FROM dbo.z_tb_SupplierLedger l
LEFT JOIN @used u ON u.LedgerId = l.LedgerId
WHERE l.SuppId = @SuppId
  AND l.Type IN (2, 3);

DELETE FROM @p WHERE NotSet <= 0;

SELECT @Free = ISNULL(SUM(NotSet), 0) FROM @p;

-- what is still open on the bill
SELECT @BillOpen = l.DebitAmount - ISNULL(SUM(x.Amount), 0)
FROM dbo.z_tb_SupplierLedger l
LEFT JOIN dbo.z_tb_SupplierPaymentAlloc x
       ON x.InvoiceLedgerId = l.LedgerId
WHERE l.LedgerId = @Bill
GROUP BY l.DebitAmount;

SELECT ReferenceId, Remark, Credit, NotSet AS WillPayTheBill
FROM @p
ORDER BY LedgerId;

SELECT @BillOpen AS BillOpen, @Free AS PaymentsNotSet;

IF @Free <> @BillOpen
BEGIN
    RAISERROR('Payments not set and the bill open amount differ - nothing changed.', 16, 1);
    RETURN;
END

IF @DryRun = 0
BEGIN
    BEGIN TRAN;
        INSERT dbo.z_tb_SupplierPaymentAlloc
            (PaymentLedgerId, InvoiceLedgerId, Amount, ChequeId)
        SELECT LedgerId, @Bill, NotSet, NULL
        FROM @p;
    COMMIT;
    PRINT 'Done - refresh the Supplier Ledger page.';
END
ELSE
    PRINT 'Dry run - nothing changed. Change SET @DryRun = 1 to 0 and run again.';
