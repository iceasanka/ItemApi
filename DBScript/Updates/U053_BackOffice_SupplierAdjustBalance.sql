/* =============================================================================
   U053_BackOffice_SupplierAdjustBalance.sql   (2026-11-06)
   Update for a back office db (easyway) that is ALREADY deployed. SQL Server 2008 R2 and newer. Safe to run again.

   What changes:
     Supplier Ledger > "Adjust balance to 0": start a supplier fresh (data correction). Nothing old is deleted or
     changed - balancing entries are ADDED, so the history stays. New proc z_sp_SupplierAdjustBalance, in one
     transaction:
       1. payments / returns not yet set against a bill are set against the open bills (oldest first);
       2. bills still open      -> ONE new PAYMENT  "adjustment" set against them      (balance was above 0);
       3. payments / returns still not used -> ONE new PURCHASE "adjustment" that they pay (balance was below 0).
     After it every bill is paid, every payment / return is used and the balance is 0. A new bill after it is open
     until it is paid.
     Undo: delete the adjustment PAYMENT; for an adjustment PURCHASE edit the payments that pay it (remove the bill)
     and then delete it.
   Needs U007 / 15 (supplier payments) and U032 / 26 (till payments). Same as the full script:
   33_BackOffice_SupplierAdjustBalance.sql.

   Run:  sqlcmd -S <server> -d easyway -E -I -b -i U053_BackOffice_SupplierAdjustBalance.sql
   Then: the new ItemApi (POST api/SupplierLedger/AdjustBalance) and the back office UI.
   ============================================================================= */
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;
GO
IF OBJECT_ID(N'dbo.z_tb_SupplierPaymentAlloc', 'U') IS NULL OR OBJECT_ID(N'dbo.z_sp_NextSupplierRef', 'P') IS NULL
   OR OBJECT_ID(N'dbo.z_tb_TillPayRequestLine', 'U') IS NULL
BEGIN
    RAISERROR('The supplier payments (U007) and the till payments (U032) are not in this database - run them first. Nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
GO

IF OBJECT_ID(N'dbo.z_sp_SupplierAdjustBalance', 'P') IS NOT NULL DROP PROCEDURE dbo.z_sp_SupplierAdjustBalance;
GO
-- ---- Supplier Ledger "Adjust balance to 0" (U053): balancing entries are added so the supplier's balance is 0,
--      every bill is paid and every payment / return is used. Nothing old is changed or deleted.
--      Returns Matched (credits set against bills), PaymentLedgerId / PaymentRef / PaymentAmount (bills still open),
--      PurchaseLedgerId / PurchaseRef / PurchaseAmount (credits still not used). Ids NULL = not needed.
CREATE PROCEDURE dbo.z_sp_SupplierAdjustBalance
    @SuppId  INT,
    @TxnDate DATE,
    @Remark  NVARCHAR(500) = NULL,
    @UserId  INT           = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @z_tc INT; SET @z_tc = @@TRANCOUNT;
    BEGIN TRY
        DECLARE @Msg NVARCHAR(400), @Bad NVARCHAR(100), @Matched DECIMAL(18,2), @Avail DECIMAL(18,2), @Take DECIMAL(18,2),
                @Open DECIMAL(18,2), @Cr INT, @Bill INT,
                @PayId INT, @PayRef NVARCHAR(100), @PayAmt DECIMAL(18,2),
                @PurId INT, @PurRef NVARCHAR(100), @PurAmt DECIMAL(18,2);
        SET @Remark = ISNULL(NULLIF(LTRIM(RTRIM(@Remark)), N''), N'Balance adjustment - start from 0');
        IF @TxnDate IS NULL RAISERROR(N'%s', 16, 1, N'Give the date.');

        CREATE TABLE #Bills (LedgerId INT PRIMARY KEY, TxnDate DATE, OpenAmt DECIMAL(18,2));
        CREATE TABLE #Cred  (LedgerId INT PRIMARY KEY, TxnDate DATE, LeftAmt DECIMAL(18,2));

        BEGIN TRAN;
            IF NOT EXISTS (SELECT 1 FROM dbo.z_tb_Supplier WITH (UPDLOCK, HOLDLOCK) WHERE SuppId = @SuppId)
                RAISERROR(N'%s', 16, 1, N'Supplier not found.');

            -- lock the supplier's ledger while it is worked out
            SELECT @Open = COUNT(*) FROM dbo.z_tb_SupplierLedger WITH (UPDLOCK, HOLDLOCK) WHERE SuppId = @SuppId;

            -- a bill waiting on a till payment would be paid twice
            SELECT TOP 1 @Bad = l.ReferenceId
            FROM dbo.z_tb_TillPayRequest r
            JOIN dbo.z_tb_TillPayRequestLine x ON x.RequestId = r.RequestId
            JOIN dbo.z_tb_SupplierLedger l ON l.LedgerId = x.LedgerId
            WHERE r.Status = 0 AND l.SuppId = @SuppId;
            IF @Bad IS NOT NULL
            BEGIN
                SET @Msg = N'Entry ' + @Bad + N' is waiting on a till payment - cancel that first (Pay from till).';
                RAISERROR(N'%s', 16, 1, @Msg);
            END

            INSERT #Bills (LedgerId, TxnDate, OpenAmt)
            SELECT l.LedgerId, l.TxnDate, x.OpenAmt
            FROM dbo.z_tb_SupplierLedger l
            CROSS APPLY (SELECT ISNULL(l.DebitAmount, 0)
                                - ISNULL((SELECT SUM(a.Amount) FROM dbo.z_tb_SupplierPaymentAlloc a WHERE a.InvoiceLedgerId = l.LedgerId), 0) AS OpenAmt) x
            WHERE l.SuppId = @SuppId AND l.Type = 1 AND x.OpenAmt > 0;

            INSERT #Cred (LedgerId, TxnDate, LeftAmt)
            SELECT l.LedgerId, l.TxnDate, x.LeftAmt
            FROM dbo.z_tb_SupplierLedger l
            CROSS APPLY (SELECT ISNULL(l.CreditAmount, 0)
                                - ISNULL((SELECT SUM(a.Amount) FROM dbo.z_tb_SupplierPaymentAlloc a WHERE a.PaymentLedgerId = l.LedgerId), 0) AS LeftAmt) x
            WHERE l.SuppId = @SuppId AND l.Type IN (2, 3) AND x.LeftAmt > 0;

            IF NOT EXISTS (SELECT 1 FROM #Bills) AND NOT EXISTS (SELECT 1 FROM #Cred)
                RAISERROR(N'%s', 16, 1, N'Nothing to adjust - the balance is already 0 and every bill is paid.');

            -- 1. unused payments / returns against the open bills, oldest first (a NULL-cheque link: set on the
            --    ledger page; deleting a written cheque still removes every link of its payment)
            SET @Matched = 0;
            DECLARE cr CURSOR LOCAL FAST_FORWARD FOR SELECT LedgerId, LeftAmt FROM #Cred ORDER BY TxnDate, LedgerId;
            OPEN cr;
            FETCH NEXT FROM cr INTO @Cr, @Avail;
            WHILE @@FETCH_STATUS = 0
            BEGIN
                WHILE @Avail > 0 AND EXISTS (SELECT 1 FROM #Bills WHERE OpenAmt > 0)
                BEGIN
                    SELECT TOP 1 @Bill = LedgerId, @Open = OpenAmt FROM #Bills WHERE OpenAmt > 0 ORDER BY TxnDate, LedgerId;
                    SET @Take = CASE WHEN @Open < @Avail THEN @Open ELSE @Avail END;
                    IF EXISTS (SELECT 1 FROM dbo.z_tb_SupplierPaymentAlloc WHERE PaymentLedgerId = @Cr AND InvoiceLedgerId = @Bill AND ChequeId IS NULL)
                        UPDATE dbo.z_tb_SupplierPaymentAlloc SET Amount = Amount + @Take
                        WHERE PaymentLedgerId = @Cr AND InvoiceLedgerId = @Bill AND ChequeId IS NULL;
                    ELSE
                        INSERT dbo.z_tb_SupplierPaymentAlloc (PaymentLedgerId, InvoiceLedgerId, Amount, ChequeId, CDate)
                        VALUES (@Cr, @Bill, @Take, NULL, GETDATE());
                    UPDATE #Bills SET OpenAmt = OpenAmt - @Take WHERE LedgerId = @Bill;
                    UPDATE #Cred  SET LeftAmt = LeftAmt - @Take WHERE LedgerId = @Cr;
                    SET @Avail = @Avail - @Take;
                    SET @Matched = @Matched + @Take;
                END
                FETCH NEXT FROM cr INTO @Cr, @Avail;
            END
            CLOSE cr;
            DEALLOCATE cr;

            -- 2. bills still open -> one adjustment PAYMENT
            SELECT @PayAmt = ISNULL(SUM(OpenAmt), 0) FROM #Bills WHERE OpenAmt > 0;
            IF @PayAmt > 0
            BEGIN
                EXEC dbo.z_sp_NextSupplierRef @SuppId, @PayRef OUTPUT;
                INSERT INTO dbo.z_tb_SupplierLedger
                    (SuppId, TxnDate, Type, ReferenceId, InvoiceNo, Remark, DebitAmount, CreditAmount, DueDate, UserId, CDate, UDate)
                VALUES (@SuppId, @TxnDate, 2, @PayRef, NULL, @Remark, 0, @PayAmt, NULL, @UserId, SYSDATETIME(), SYSDATETIME());
                SET @PayId = SCOPE_IDENTITY();
                INSERT dbo.z_tb_SupplierPaymentAlloc (PaymentLedgerId, InvoiceLedgerId, Amount, ChequeId, CDate)
                SELECT @PayId, LedgerId, OpenAmt, NULL, GETDATE() FROM #Bills WHERE OpenAmt > 0;
            END

            -- 3. payments / returns still not used -> one adjustment PURCHASE that they pay
            SELECT @PurAmt = ISNULL(SUM(LeftAmt), 0) FROM #Cred WHERE LeftAmt > 0;
            IF @PurAmt > 0
            BEGIN
                EXEC dbo.z_sp_NextSupplierRef @SuppId, @PurRef OUTPUT;
                INSERT INTO dbo.z_tb_SupplierLedger
                    (SuppId, TxnDate, Type, ReferenceId, InvoiceNo, Remark, DebitAmount, CreditAmount, DueDate, UserId, CDate, UDate)
                VALUES (@SuppId, @TxnDate, 1, @PurRef, NULL, @Remark, @PurAmt, 0, @TxnDate, @UserId, SYSDATETIME(), SYSDATETIME());
                SET @PurId = SCOPE_IDENTITY();
                INSERT dbo.z_tb_SupplierPaymentAlloc (PaymentLedgerId, InvoiceLedgerId, Amount, ChequeId, CDate)
                SELECT LedgerId, @PurId, LeftAmt, NULL, GETDATE() FROM #Cred WHERE LeftAmt > 0;
            END
        COMMIT;

        SELECT CAST(@Matched AS DECIMAL(18,2)) AS Matched,
               @PayId AS PaymentLedgerId, @PayRef AS PaymentRef, CAST(ISNULL(@PayAmt, 0) AS DECIMAL(18,2)) AS PaymentAmount,
               @PurId AS PurchaseLedgerId, @PurRef AS PurchaseRef, CAST(ISNULL(@PurAmt, 0) AS DECIMAL(18,2)) AS PurchaseAmount;
    END TRY
    BEGIN CATCH
        DECLARE @z_msg NVARCHAR(2048); SET @z_msg = ERROR_MESSAGE();
        IF @z_tc = 0 BEGIN IF XACT_STATE() <> 0 ROLLBACK; END
        ELSE BEGIN WHILE @@TRANCOUNT > @z_tc AND XACT_STATE() = 1 COMMIT; END
        RAISERROR(N'%s', 16, 1, @z_msg);
        RETURN 1;
    END CATCH
END
GO

SET NOEXEC OFF;
GO
