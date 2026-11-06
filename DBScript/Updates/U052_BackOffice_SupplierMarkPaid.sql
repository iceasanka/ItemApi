/* =============================================================================
   U052_BackOffice_SupplierMarkPaid.sql   (2026-11-06)
   Update for a back office db (easyway) that is ALREADY deployed. SQL Server 2008 R2 and newer. Safe to run again.

   What changes:
     Supplier Ledger > tick bills (and returns) > "Mark as paid": for money paid outside the system (a bank transfer
     straight from the account) or a data correction (start a supplier from 0). New proc z_sp_SupplierMarkPaid, in one
     transaction:
       1. the ticked returns are set against the ticked bills (oldest return first, oldest bill first), added to what
          they already pay;
       2. what is still open on the ticked bills becomes ONE new PAYMENT row set against them (none when the returns
          cover the bills).
     The ticked bills end at 0. Nothing else changes (no new table / column).
   Needs U007 / 15 (supplier payments) and U032 / 26 (till payments). Same as the full script:
   32_BackOffice_SupplierMarkPaid.sql.

   Run:  sqlcmd -S <server> -d easyway -E -I -b -i U052_BackOffice_SupplierMarkPaid.sql
   Then: the new ItemApi (POST api/SupplierLedger/MarkPaid) and the back office UI.
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
   OR OBJECT_ID(N'dbo.z_tb_TillPayRequestLine', 'U') IS NULL OR TYPE_ID(N'dbo.z_tt_IdList') IS NULL
BEGIN
    RAISERROR('The supplier payments (U007) and the till payments (U032) are not in this database - run them first. Nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
GO

IF OBJECT_ID(N'dbo.z_sp_SupplierMarkPaid', 'P') IS NOT NULL DROP PROCEDURE dbo.z_sp_SupplierMarkPaid;
GO
-- ---- Supplier Ledger "Mark as paid" (U052): the ticked bills (Type 1) of a supplier end at 0.
--      1. the ticked returns (Type 3, what is left on each) are set against the bills, oldest first;
--      2. what is still open on the bills = ONE new PAYMENT row (@TxnDate, @Remark) set against them.
--      Returns PaymentLedgerId (NULL = the returns covered the bills), ReferenceId, Paid, ReturnsUsed.
--      A bill / return made by a cheque, or waiting on a till payment, cannot be used.
CREATE PROCEDURE dbo.z_sp_SupplierMarkPaid
    @SuppId  INT,
    @TxnDate DATE,
    @Remark  NVARCHAR(500) = NULL,
    @UserId  INT           = NULL,
    @Ids     dbo.z_tt_IdList READONLY
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @z_tc INT; SET @z_tc = @@TRANCOUNT;
    BEGIN TRY
        DECLARE @Msg NVARCHAR(400), @Bad NVARCHAR(100), @Ref NVARCHAR(100), @PayId INT,
                @Rest DECIMAL(18,2), @Used DECIMAL(18,2), @Avail DECIMAL(18,2), @Take DECIMAL(18,2),
                @Ret INT, @Bill INT, @Open DECIMAL(18,2);
        SET @Remark = NULLIF(LTRIM(RTRIM(@Remark)), N'');
        IF @TxnDate IS NULL RAISERROR(N'%s', 16, 1, N'Give the payment date.');
        IF NOT EXISTS (SELECT 1 FROM @Ids) RAISERROR(N'%s', 16, 1, N'Tick at least one bill.');

        CREATE TABLE #Bills (LedgerId INT PRIMARY KEY, TxnDate DATE, OpenAmt DECIMAL(18,2));
        CREATE TABLE #Rets  (LedgerId INT PRIMARY KEY, TxnDate DATE, LeftAmt DECIMAL(18,2));

        BEGIN TRAN;
            IF NOT EXISTS (SELECT 1 FROM dbo.z_tb_Supplier WHERE SuppId = @SuppId)
                RAISERROR(N'%s', 16, 1, N'Supplier not found.');

            -- every id: a bill or a return of this supplier, not made by a cheque
            SELECT TOP 1 @Bad = ISNULL(l.ReferenceId, CAST(i.Id AS NVARCHAR(20)))
            FROM @Ids i
            LEFT JOIN dbo.z_tb_SupplierLedger l WITH (UPDLOCK, HOLDLOCK) ON l.LedgerId = i.Id
            WHERE l.LedgerId IS NULL OR l.SuppId <> @SuppId OR l.Type NOT IN (1, 3) OR l.ChequeId IS NOT NULL;
            IF @Bad IS NOT NULL
            BEGIN
                SET @Msg = N'Entry ' + @Bad + N' is not a bill or a return of this supplier (or it was made by a cheque).';
                RAISERROR(N'%s', 16, 1, @Msg);
            END

            -- not waiting on a till payment (the till would pay it again)
            SELECT TOP 1 @Bad = l.ReferenceId
            FROM @Ids i
            JOIN dbo.z_tb_TillPayRequestLine x ON x.LedgerId = i.Id
            JOIN dbo.z_tb_TillPayRequest r ON r.RequestId = x.RequestId AND r.Status = 0
            JOIN dbo.z_tb_SupplierLedger l ON l.LedgerId = i.Id;
            IF @Bad IS NOT NULL
            BEGIN
                SET @Msg = N'Entry ' + @Bad + N' is waiting on a till payment - cancel that first.';
                RAISERROR(N'%s', 16, 1, @Msg);
            END

            INSERT #Bills (LedgerId, TxnDate, OpenAmt)
            SELECT l.LedgerId, l.TxnDate,
                   ISNULL(l.DebitAmount, 0) - ISNULL((SELECT SUM(a.Amount) FROM dbo.z_tb_SupplierPaymentAlloc a WHERE a.InvoiceLedgerId = l.LedgerId), 0)
            FROM @Ids i JOIN dbo.z_tb_SupplierLedger l ON l.LedgerId = i.Id
            WHERE l.Type = 1;
            INSERT #Rets (LedgerId, TxnDate, LeftAmt)
            SELECT l.LedgerId, l.TxnDate,
                   ISNULL(l.CreditAmount, 0) - ISNULL((SELECT SUM(a.Amount) FROM dbo.z_tb_SupplierPaymentAlloc a WHERE a.PaymentLedgerId = l.LedgerId), 0)
            FROM @Ids i JOIN dbo.z_tb_SupplierLedger l ON l.LedgerId = i.Id
            WHERE l.Type = 3;

            IF NOT EXISTS (SELECT 1 FROM #Bills) RAISERROR(N'%s', 16, 1, N'Tick at least one bill (PURCHASE).');
            SELECT TOP 1 @Bad = l.ReferenceId FROM #Bills b JOIN dbo.z_tb_SupplierLedger l ON l.LedgerId = b.LedgerId WHERE b.OpenAmt <= 0;
            IF @Bad IS NOT NULL
            BEGIN
                SET @Msg = N'Bill ' + @Bad + N' is already paid.';
                RAISERROR(N'%s', 16, 1, @Msg);
            END
            SELECT TOP 1 @Bad = l.ReferenceId FROM #Rets r JOIN dbo.z_tb_SupplierLedger l ON l.LedgerId = r.LedgerId WHERE r.LeftAmt <= 0;
            IF @Bad IS NOT NULL
            BEGIN
                SET @Msg = N'Return ' + @Bad + N' is already used up.';
                RAISERROR(N'%s', 16, 1, @Msg);
            END

            -- 1. the returns against the bills, oldest first (added to what each return already pays)
            SET @Used = 0;
            DECLARE rets CURSOR LOCAL FAST_FORWARD FOR SELECT LedgerId, LeftAmt FROM #Rets ORDER BY TxnDate, LedgerId;
            OPEN rets;
            FETCH NEXT FROM rets INTO @Ret, @Avail;
            WHILE @@FETCH_STATUS = 0
            BEGIN
                WHILE @Avail > 0 AND EXISTS (SELECT 1 FROM #Bills WHERE OpenAmt > 0)
                BEGIN
                    SELECT TOP 1 @Bill = LedgerId, @Open = OpenAmt FROM #Bills WHERE OpenAmt > 0 ORDER BY TxnDate, LedgerId;
                    SET @Take = CASE WHEN @Open < @Avail THEN @Open ELSE @Avail END;
                    IF EXISTS (SELECT 1 FROM dbo.z_tb_SupplierPaymentAlloc WHERE PaymentLedgerId = @Ret AND InvoiceLedgerId = @Bill AND ChequeId IS NULL)
                        UPDATE dbo.z_tb_SupplierPaymentAlloc SET Amount = Amount + @Take
                        WHERE PaymentLedgerId = @Ret AND InvoiceLedgerId = @Bill AND ChequeId IS NULL;
                    ELSE
                        INSERT dbo.z_tb_SupplierPaymentAlloc (PaymentLedgerId, InvoiceLedgerId, Amount, ChequeId, CDate)
                        VALUES (@Ret, @Bill, @Take, NULL, GETDATE());
                    UPDATE #Bills SET OpenAmt = OpenAmt - @Take WHERE LedgerId = @Bill;
                    SET @Avail = @Avail - @Take;
                    SET @Used = @Used + @Take;
                END
                FETCH NEXT FROM rets INTO @Ret, @Avail;
            END
            CLOSE rets;
            DEALLOCATE rets;

            -- 2. what is still open on the bills = one PAYMENT set against them
            SELECT @Rest = ISNULL(SUM(OpenAmt), 0) FROM #Bills WHERE OpenAmt > 0;
            IF @Rest > 0
            BEGIN
                EXEC dbo.z_sp_NextSupplierRef @SuppId, @Ref OUTPUT;
                INSERT INTO dbo.z_tb_SupplierLedger
                    (SuppId, TxnDate, Type, ReferenceId, InvoiceNo, Remark, DebitAmount, CreditAmount, DueDate, UserId, CDate, UDate)
                VALUES (@SuppId, @TxnDate, 2, @Ref, NULL, @Remark, 0, @Rest, NULL, @UserId, SYSDATETIME(), SYSDATETIME());
                SET @PayId = SCOPE_IDENTITY();
                INSERT dbo.z_tb_SupplierPaymentAlloc (PaymentLedgerId, InvoiceLedgerId, Amount, ChequeId, CDate)
                SELECT @PayId, LedgerId, OpenAmt, NULL, GETDATE() FROM #Bills WHERE OpenAmt > 0;
            END
        COMMIT;

        SELECT @PayId AS PaymentLedgerId, @Ref AS ReferenceId, CAST(ISNULL(@Rest, 0) AS DECIMAL(18,2)) AS Paid,
               CAST(@Used AS DECIMAL(18,2)) AS ReturnsUsed;
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
