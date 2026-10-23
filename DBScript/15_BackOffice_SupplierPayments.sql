/* =============================================================================
   15_BackOffice_SupplierPayments.sql   (2026-10-14) - full script for a new install.
   Run on: back office db (easyway). SQL Server 2008 R2 and newer. Safe to run again.
   Needs: z_tb_Supplier and z_tb_SupplierLedger. Then the new ItemApi.
   Deployed databases get the same file as DBScript/Updates/U007_BackOffice_SupplierPayments.sql - change both together.

   Supplier bills -> cheques (StockSystem.md section 6.19).
     z_tb_Supplier          + PayeeName  (the name printed on cheques; NULL = SuppName) - z_tb_Payee is merged in here
                            + CreditDays (cheque period: a bill is due TxnDate + CreditDays)
                            + LedgerSeq  (counter for the ledger reference SUPPCODE-00001)
     z_tb_SupplierLedger    + InvoiceNo  (the supplier's bill number)  + DueDate (bills)  + ChequeId (payment made by a cheque)
                            ReferenceId is made from SuppCode + number when left empty.
     z_tb_SupplierPaymentAlloc  which bills (Type 1 rows) a payment / return (Type 2 / 3 rows) paid, and how much.
     z_tb_WrittenCheque     + SuppId, LedgerId (the PAYMENT ledger row the cheque made), PayeeName. PayeeId may be NULL.
   Writing a cheque for a supplier adds ONE payment row (credit = cheque amount) to the ledger and allocates it to
   the bills picked on the cheque writer. A bill's open amount = DebitAmount - its allocations.
   Cheque less than the bill (returns taken off): per bill "cheque pay" (Amount) + Deduction = what is settled. The
   deduction is taken from the supplier's returns not yet set against a bill (oldest first); what is still left
   becomes a new RETURN row "Deducted on cheque ..." (ChequeId set). So the bill is Paid and the balance stays right.
   z_tb_SupplierPaymentAlloc.ChequeId = the cheque whose writing made the allocation (deleting the cheque undoes it).

   z_tb_Payee is kept (read only from now on): each payee name is copied to the supplier with the same name, and
   old cheques get SuppId the same way. Payees with no supplier of that name are listed at the end - set the
   payee name on the right supplier by hand.
   ============================================================================= */
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
IF OBJECT_ID(N'dbo.z_tb_Supplier', 'U') IS NULL OR OBJECT_ID(N'dbo.z_tb_SupplierLedger', 'U') IS NULL
BEGIN
    RAISERROR('This is not the back office database (z_tb_Supplier / z_tb_SupplierLedger not found) - nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
GO

/* ---------------------------------------------------------------------------
   1. Tables and columns
   --------------------------------------------------------------------------- */
IF COL_LENGTH('dbo.z_tb_Supplier', 'PayeeName') IS NULL
    ALTER TABLE dbo.z_tb_Supplier ADD PayeeName NVARCHAR(200) NULL;
IF COL_LENGTH('dbo.z_tb_Supplier', 'CreditDays') IS NULL
    ALTER TABLE dbo.z_tb_Supplier ADD CreditDays INT NULL;
IF COL_LENGTH('dbo.z_tb_Supplier', 'LedgerSeq') IS NULL
    ALTER TABLE dbo.z_tb_Supplier ADD LedgerSeq INT NOT NULL CONSTRAINT DF_z_tb_Supplier_LedgerSeq DEFAULT (0);
GO
IF COL_LENGTH('dbo.z_tb_SupplierLedger', 'InvoiceNo') IS NULL
    ALTER TABLE dbo.z_tb_SupplierLedger ADD InvoiceNo NVARCHAR(50) NULL;
IF COL_LENGTH('dbo.z_tb_SupplierLedger', 'DueDate') IS NULL
    ALTER TABLE dbo.z_tb_SupplierLedger ADD DueDate DATE NULL;
IF COL_LENGTH('dbo.z_tb_SupplierLedger', 'ChequeId') IS NULL
    ALTER TABLE dbo.z_tb_SupplierLedger ADD ChequeId INT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_z_tb_SupplierLedger_Supp' AND object_id = OBJECT_ID('dbo.z_tb_SupplierLedger'))
    CREATE INDEX IX_z_tb_SupplierLedger_Supp ON dbo.z_tb_SupplierLedger (SuppId, TxnDate, LedgerId);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_z_tb_SupplierLedger_Due' AND object_id = OBJECT_ID('dbo.z_tb_SupplierLedger'))
    CREATE INDEX IX_z_tb_SupplierLedger_Due ON dbo.z_tb_SupplierLedger (Type, DueDate);
GO
IF OBJECT_ID('dbo.z_tb_SupplierPaymentAlloc', 'U') IS NULL
CREATE TABLE dbo.z_tb_SupplierPaymentAlloc (
    AllocId          INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_z_tb_SupplierPaymentAlloc PRIMARY KEY,
    PaymentLedgerId  INT            NOT NULL,   -- the PAYMENT / RETURN ledger row
    InvoiceLedgerId  INT            NOT NULL,   -- the bill (PURCHASE ledger row) it pays
    Amount           DECIMAL(18,2)  NOT NULL,
    ChequeId         INT            NULL,       -- made when this cheque was written (NULL = set on the ledger page)
    CDate            DATETIME       NOT NULL CONSTRAINT DF_z_tb_SupplierPaymentAlloc_CDate DEFAULT (GETDATE()),
    CONSTRAINT UQ_z_tb_SupplierPaymentAlloc UNIQUE (PaymentLedgerId, InvoiceLedgerId, ChequeId),
    CONSTRAINT FK_z_tb_SupplierPaymentAlloc_Payment FOREIGN KEY (PaymentLedgerId) REFERENCES dbo.z_tb_SupplierLedger (LedgerId),
    CONSTRAINT FK_z_tb_SupplierPaymentAlloc_Invoice FOREIGN KEY (InvoiceLedgerId) REFERENCES dbo.z_tb_SupplierLedger (LedgerId)
);
GO
-- databases that got the first U007 (dev, 2026-10-14): ChequeId + the unique key with it
IF COL_LENGTH('dbo.z_tb_SupplierPaymentAlloc', 'ChequeId') IS NULL
    ALTER TABLE dbo.z_tb_SupplierPaymentAlloc ADD ChequeId INT NULL;
GO
IF (SELECT COUNT(*) FROM sys.indexes i JOIN sys.index_columns ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id
    WHERE i.object_id = OBJECT_ID('dbo.z_tb_SupplierPaymentAlloc') AND i.name = 'UQ_z_tb_SupplierPaymentAlloc') = 2
    ALTER TABLE dbo.z_tb_SupplierPaymentAlloc DROP CONSTRAINT UQ_z_tb_SupplierPaymentAlloc;
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UQ_z_tb_SupplierPaymentAlloc' AND object_id = OBJECT_ID('dbo.z_tb_SupplierPaymentAlloc'))
    ALTER TABLE dbo.z_tb_SupplierPaymentAlloc ADD CONSTRAINT UQ_z_tb_SupplierPaymentAlloc UNIQUE (PaymentLedgerId, InvoiceLedgerId, ChequeId);
-- allocations a cheque made through its own payment row
UPDATE a SET ChequeId = l.ChequeId
FROM dbo.z_tb_SupplierPaymentAlloc a JOIN dbo.z_tb_SupplierLedger l ON l.LedgerId = a.PaymentLedgerId
WHERE a.ChequeId IS NULL AND l.ChequeId IS NOT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_z_tb_SupplierPaymentAlloc_Invoice' AND object_id = OBJECT_ID('dbo.z_tb_SupplierPaymentAlloc'))
    CREATE INDEX IX_z_tb_SupplierPaymentAlloc_Invoice ON dbo.z_tb_SupplierPaymentAlloc (InvoiceLedgerId);
GO

-- payees and written cheques: made here when this database never had the cheque writer
IF OBJECT_ID('dbo.z_tb_Payee', 'U') IS NULL
CREATE TABLE dbo.z_tb_Payee (
    PayeeId        INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_z_tb_Payee PRIMARY KEY,
    PayeeName      NVARCHAR(200) NOT NULL,
    SupplierName   NVARCHAR(200) NOT NULL,
    BankName       NVARCHAR(150) NULL,
    AccountNumber  NVARCHAR(50)  NULL,
    PhoneNumber    NVARCHAR(50)  NULL,
    Email          NVARCHAR(150) NULL,
    IsActive       BIT           NOT NULL CONSTRAINT DF_z_tb_Payee_IsActive DEFAULT (1),
    CreatedDate    DATETIME      NOT NULL CONSTRAINT DF_z_tb_Payee_CreatedDate DEFAULT (GETDATE()),
    UpdatedDate    DATETIME      NULL
);
GO
IF OBJECT_ID('dbo.z_tb_WrittenCheque', 'U') IS NULL
CREATE TABLE dbo.z_tb_WrittenCheque (
    ChequeId           INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_z_tb_WrittenCheque PRIMARY KEY,
    ChequeNumber       INT            NOT NULL CONSTRAINT UQ_z_tb_WrittenCheque_ChequeNumber UNIQUE,
    Amount             DECIMAL(18,2)  NOT NULL,
    ChequeDate         DATE           NOT NULL,
    ChequeWrittenDate  DATETIME       NOT NULL CONSTRAINT DF_z_tb_WrittenCheque_ChequeWrittenDate DEFAULT (GETDATE()),
    PayeeId            INT            NULL,
    SupplierName       NVARCHAR(200)  NOT NULL,
    CreatedDate        DATETIME       NOT NULL CONSTRAINT DF_z_tb_WrittenCheque_CreatedDate DEFAULT (GETDATE()),
    IsSync             INT            NULL,
    IsDebited          INT            NOT NULL CONSTRAINT DF_z_tb_WrittenCheque_IsDebited DEFAULT (0),
    CONSTRAINT FK_z_tb_WrittenCheque_z_tb_Payee FOREIGN KEY (PayeeId) REFERENCES dbo.z_tb_Payee (PayeeId)
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Cheque_ChequeDate' AND object_id = OBJECT_ID('dbo.z_tb_WrittenCheque'))
    CREATE INDEX IX_Cheque_ChequeDate ON dbo.z_tb_WrittenCheque (ChequeDate);
GO
IF COL_LENGTH('dbo.z_tb_WrittenCheque', 'SuppId') IS NULL
    ALTER TABLE dbo.z_tb_WrittenCheque ADD SuppId INT NULL;
IF COL_LENGTH('dbo.z_tb_WrittenCheque', 'LedgerId') IS NULL
    ALTER TABLE dbo.z_tb_WrittenCheque ADD LedgerId INT NULL;
IF COL_LENGTH('dbo.z_tb_WrittenCheque', 'PayeeName') IS NULL
    ALTER TABLE dbo.z_tb_WrittenCheque ADD PayeeName NVARCHAR(200) NULL;
GO
-- a cheque for a supplier needs no payee row any more
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.z_tb_WrittenCheque') AND name = 'PayeeId' AND is_nullable = 0)
BEGIN
    IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_z_tb_WrittenCheque_z_tb_Payee')
        ALTER TABLE dbo.z_tb_WrittenCheque DROP CONSTRAINT FK_z_tb_WrittenCheque_z_tb_Payee;
    ALTER TABLE dbo.z_tb_WrittenCheque ALTER COLUMN PayeeId INT NULL;
END
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_z_tb_WrittenCheque_z_tb_Payee')
    ALTER TABLE dbo.z_tb_WrittenCheque ADD CONSTRAINT FK_z_tb_WrittenCheque_z_tb_Payee
        FOREIGN KEY (PayeeId) REFERENCES dbo.z_tb_Payee (PayeeId);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_z_tb_WrittenCheque_Supp' AND object_id = OBJECT_ID('dbo.z_tb_WrittenCheque'))
    CREATE INDEX IX_z_tb_WrittenCheque_Supp ON dbo.z_tb_WrittenCheque (SuppId);
GO

/* ---------------------------------------------------------------------------
   2. Data: payees -> suppliers, old cheques -> SuppId, bills -> DueDate
   --------------------------------------------------------------------------- */
-- the payee name of the supplier with the same name (first active payee); a name already set is kept
UPDATE s SET PayeeName = p.PayeeName, UDate = SYSDATETIME()
FROM dbo.z_tb_Supplier s
CROSS APPLY (SELECT TOP 1 x.PayeeName FROM dbo.z_tb_Payee x
             WHERE LTRIM(RTRIM(x.SupplierName)) = LTRIM(RTRIM(s.SuppName))
             ORDER BY x.IsActive DESC, x.PayeeId) p
WHERE s.PayeeName IS NULL;

-- old cheques: supplier by the payee's supplier name, else by the name written on the cheque
UPDATE c SET SuppId = s.SuppId
FROM dbo.z_tb_WrittenCheque c
LEFT JOIN dbo.z_tb_Payee p ON p.PayeeId = c.PayeeId
CROSS APPLY (SELECT TOP 1 x.SuppId FROM dbo.z_tb_Supplier x
             WHERE LTRIM(RTRIM(x.SuppName)) = LTRIM(RTRIM(ISNULL(p.SupplierName, c.SupplierName)))
             ORDER BY x.Status DESC, x.SuppId) s
WHERE c.SuppId IS NULL;

UPDATE c SET PayeeName = p.PayeeName
FROM dbo.z_tb_WrittenCheque c JOIN dbo.z_tb_Payee p ON p.PayeeId = c.PayeeId
WHERE c.PayeeName IS NULL;

-- bills entered before this: due = bill date + the supplier's cheque period (0 when not set)
UPDATE l SET DueDate = DATEADD(DAY, ISNULL(s.CreditDays, 0), l.TxnDate)
FROM dbo.z_tb_SupplierLedger l JOIN dbo.z_tb_Supplier s ON s.SuppId = l.SuppId
WHERE l.Type = 1 AND l.DueDate IS NULL;
GO

/* ---------------------------------------------------------------------------
   3. Type and procedures
   --------------------------------------------------------------------------- */
IF OBJECT_ID('dbo.z_sp_NextSupplierRef', 'P')          IS NOT NULL DROP PROCEDURE dbo.z_sp_NextSupplierRef;
IF OBJECT_ID('dbo.z_sp_AllocateSupplierPayment', 'P')  IS NOT NULL DROP PROCEDURE dbo.z_sp_AllocateSupplierPayment;
IF OBJECT_ID('dbo.z_sp_SaveSupplierLedger', 'P')       IS NOT NULL DROP PROCEDURE dbo.z_sp_SaveSupplierLedger;
IF OBJECT_ID('dbo.z_sp_DeleteSupplierLedger', 'P')     IS NOT NULL DROP PROCEDURE dbo.z_sp_DeleteSupplierLedger;
IF OBJECT_ID('dbo.z_Sp_GetSupplierLedger', 'P')        IS NOT NULL DROP PROCEDURE dbo.z_Sp_GetSupplierLedger;
IF OBJECT_ID('dbo.z_sp_GetSupplierLedger_ByDate', 'P') IS NOT NULL DROP PROCEDURE dbo.z_sp_GetSupplierLedger_ByDate;
IF OBJECT_ID('dbo.z_sp_GetSupplierInvoices', 'P')      IS NOT NULL DROP PROCEDURE dbo.z_sp_GetSupplierInvoices;
IF OBJECT_ID('dbo.z_sp_GetSupplierPaymentsDue', 'P')   IS NOT NULL DROP PROCEDURE dbo.z_sp_GetSupplierPaymentsDue;
IF OBJECT_ID('dbo.z_sp_LinkWrittenCheque', 'P')        IS NOT NULL DROP PROCEDURE dbo.z_sp_LinkWrittenCheque;
IF OBJECT_ID('dbo.z_sp_UnlinkWrittenCheque', 'P')      IS NOT NULL DROP PROCEDURE dbo.z_sp_UnlinkWrittenCheque;
GO
IF TYPE_ID('dbo.z_tt_SupplierAlloc') IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM sys.table_types tt JOIN sys.columns c ON c.object_id = tt.type_table_object_id
    WHERE tt.name = 'z_tt_SupplierAlloc' AND c.name = 'Deduction')
    DROP TYPE dbo.z_tt_SupplierAlloc;   -- first U007 (dev): no Deduction yet; its procedures were dropped above
GO
IF TYPE_ID('dbo.z_tt_SupplierAlloc') IS NULL
CREATE TYPE dbo.z_tt_SupplierAlloc AS TABLE (
    LedgerId  INT            NOT NULL PRIMARY KEY,   -- the bill (PURCHASE ledger row)
    Amount    DECIMAL(18,2)  NOT NULL,               -- paid by this payment / cheque ("cheque pay")
    Deduction DECIMAL(18,2)  NOT NULL DEFAULT (0)    -- cheques only: taken off for returns, the bill counts it as paid
);
GO

-- ---- next ledger reference of a supplier: SUPPCODE-00001 (counter z_tb_Supplier.LedgerSeq)
CREATE PROCEDURE dbo.z_sp_NextSupplierRef
    @SuppId INT,
    @Ref    NVARCHAR(100) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Seq INT, @Code VARCHAR(10);
    UPDATE dbo.z_tb_Supplier SET @Seq = LedgerSeq = LedgerSeq + 1, @Code = SuppCode WHERE SuppId = @SuppId;
    SET @Ref = CASE WHEN @Seq IS NULL THEN NULL
                    ELSE RTRIM(@Code) + '-' + CASE WHEN @Seq < 100000 THEN RIGHT('0000' + CAST(@Seq AS VARCHAR(10)), 5)
                                                   ELSE CAST(@Seq AS VARCHAR(10)) END END;
END
GO

-- ---- set which bills a payment / return pays (replaces what it paid before; empty = pays no bill).
--      @ChequeId NULL = from the ledger page: what cheques set against this row (deductions) is kept.
--      @ChequeId set  = from z_sp_LinkWrittenCheque: the rows are marked with the cheque.
CREATE PROCEDURE dbo.z_sp_AllocateSupplierPayment
    @PaymentLedgerId INT,
    @Allocations     dbo.z_tt_SupplierAlloc READONLY,
    @ChequeId        INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @z_tc INT; SET @z_tc = @@TRANCOUNT;
    BEGIN TRY
        DECLARE @SuppId INT, @Type INT, @Credit DECIMAL(18,2), @Kept DECIMAL(18,2), @Msg NVARCHAR(400), @Bad NVARCHAR(100);
        BEGIN TRAN;
            SELECT @SuppId = SuppId, @Type = Type, @Credit = ISNULL(CreditAmount, 0)
            FROM dbo.z_tb_SupplierLedger WITH (UPDLOCK, HOLDLOCK) WHERE LedgerId = @PaymentLedgerId;
            IF @Type IS NULL RAISERROR(N'%s', 16, 1, N'Ledger entry not found.');
            IF @Type NOT IN (2, 3) AND EXISTS (SELECT 1 FROM @Allocations)
                RAISERROR(N'%s', 16, 1, N'Only a payment or a return can pay bills.');
            IF EXISTS (SELECT 1 FROM @Allocations WHERE Amount <= 0)
                RAISERROR(N'%s', 16, 1, N'Each bill needs an amount above 0.');
            IF EXISTS (SELECT 1 FROM @Allocations WHERE Deduction <> 0)
                RAISERROR(N'%s', 16, 1, N'A deduction is only taken when a cheque is written.');

            -- what other cheques set against this row stays
            SELECT @Kept = ISNULL(SUM(Amount), 0) FROM dbo.z_tb_SupplierPaymentAlloc
            WHERE PaymentLedgerId = @PaymentLedgerId
              AND ISNULL(ChequeId, 0) <> ISNULL(@ChequeId, 0);
            IF @Kept > @Credit
            BEGIN
                SET @Msg = N'Written cheques took ' + CONVERT(NVARCHAR(30), CAST(@Kept AS MONEY), 1) + N' of this off bills - the amount cannot be less.';
                RAISERROR(N'%s', 16, 1, @Msg);
            END
            IF (SELECT ISNULL(SUM(Amount), 0) FROM @Allocations) + @Kept > @Credit
            BEGIN
                SET @Msg = N'The bills picked come to more than the payment (' + CONVERT(NVARCHAR(30), CAST(@Credit - @Kept AS MONEY), 1) + N').';
                RAISERROR(N'%s', 16, 1, @Msg);
            END

            SELECT TOP 1 @Bad = ISNULL(l.ReferenceId, CAST(a.LedgerId AS NVARCHAR(20)))
            FROM @Allocations a
            LEFT JOIN dbo.z_tb_SupplierLedger l WITH (UPDLOCK, HOLDLOCK) ON l.LedgerId = a.LedgerId
            WHERE l.LedgerId IS NULL OR l.SuppId <> @SuppId OR l.Type <> 1;
            IF @Bad IS NOT NULL
            BEGIN
                SET @Msg = N'Bill ' + @Bad + N' is not a bill of this supplier.';
                RAISERROR(N'%s', 16, 1, @Msg);
            END

            DELETE FROM dbo.z_tb_SupplierPaymentAlloc
            WHERE PaymentLedgerId = @PaymentLedgerId
              AND ISNULL(ChequeId, 0) = ISNULL(@ChequeId, 0);

            -- no bill may be paid more than its amount
            SELECT TOP 1 @Bad = l.ReferenceId
            FROM @Allocations a
            JOIN dbo.z_tb_SupplierLedger l ON l.LedgerId = a.LedgerId
            WHERE a.Amount > ISNULL(l.DebitAmount, 0)
                             - ISNULL((SELECT SUM(x.Amount) FROM dbo.z_tb_SupplierPaymentAlloc x WHERE x.InvoiceLedgerId = a.LedgerId), 0);
            IF @Bad IS NOT NULL
            BEGIN
                SET @Msg = N'Bill ' + @Bad + N' would be paid more than its amount - check what is still open on it.';
                RAISERROR(N'%s', 16, 1, @Msg);
            END

            INSERT INTO dbo.z_tb_SupplierPaymentAlloc (PaymentLedgerId, InvoiceLedgerId, Amount, ChequeId)
            SELECT @PaymentLedgerId, LedgerId, Amount, @ChequeId FROM @Allocations;
        COMMIT;
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

-- ---- add (@LedgerId 0) or change a ledger entry. Returns LedgerId, ReferenceId.
--      ReferenceId empty -> SUPPCODE-00001. A bill (Type 1) with no @DueDate is due TxnDate + the supplier's CreditDays.
--      @SetAllocations = 1: a payment / return pays the bills in @Allocations (replacing what it paid before).
CREATE PROCEDURE dbo.z_sp_SaveSupplierLedger
    @LedgerId       INT            = 0,
    @SuppId         INT,
    @TxnDate        DATE,
    @Type           INT,
    @ReferenceId    NVARCHAR(100)  = NULL,
    @InvoiceNo      NVARCHAR(50)   = NULL,
    @Remark         NVARCHAR(500)  = NULL,
    @DebitAmount    DECIMAL(18,2)  = 0,
    @CreditAmount   DECIMAL(18,2)  = 0,
    @DueDate        DATE           = NULL,
    @UserId         INT            = NULL,
    @SetAllocations BIT            = 0,
    @Allocations    dbo.z_tt_SupplierAlloc READONLY
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @z_tc INT; SET @z_tc = @@TRANCOUNT;
    BEGIN TRY
        DECLARE @CreditDays INT, @OldSupp INT, @OldType INT, @OldCheque INT, @OldTxn DATE, @OldDue DATE,
                @Paid DECIMAL(18,2), @Msg NVARCHAR(400);
        SET @LedgerId = ISNULL(@LedgerId, 0);
        SET @ReferenceId = NULLIF(LTRIM(RTRIM(@ReferenceId)), N'');
        SET @InvoiceNo = NULLIF(LTRIM(RTRIM(@InvoiceNo)), N'');
        SET @DebitAmount = ISNULL(@DebitAmount, 0);
        SET @CreditAmount = ISNULL(@CreditAmount, 0);

        IF @Type NOT IN (1, 2, 3) RAISERROR(N'%s', 16, 1, N'Type must be 1 (PURCHASE), 2 (PAYMENT) or 3 (RETURN).');
        IF @DebitAmount < 0 OR @CreditAmount < 0 RAISERROR(N'%s', 16, 1, N'Amounts cannot be below 0.');
        IF @DebitAmount > 0 AND @CreditAmount > 0 RAISERROR(N'%s', 16, 1, N'Only DebitAmount or CreditAmount can be set, not both.');
        IF @DebitAmount = 0 AND @CreditAmount = 0 RAISERROR(N'%s', 16, 1, N'Either DebitAmount or CreditAmount must be greater than 0.');
        IF @TxnDate IS NULL RAISERROR(N'%s', 16, 1, N'Give the date.');

        BEGIN TRAN;
            SELECT @CreditDays = CreditDays FROM dbo.z_tb_Supplier WHERE SuppId = @SuppId;
            IF @@ROWCOUNT = 0 RAISERROR(N'%s', 16, 1, N'Supplier not found.');

            IF @Type = 1 AND @InvoiceNo IS NOT NULL AND EXISTS (
                SELECT 1 FROM dbo.z_tb_SupplierLedger WITH (UPDLOCK, HOLDLOCK)
                WHERE SuppId = @SuppId AND Type = 1 AND InvoiceNo = @InvoiceNo AND LedgerId <> @LedgerId)
            BEGIN
                SET @Msg = N'Bill ' + @InvoiceNo + N' of this supplier is already in the ledger.';
                RAISERROR(N'%s', 16, 1, @Msg);
            END

            IF @LedgerId = 0
            BEGIN
                IF @ReferenceId IS NULL EXEC dbo.z_sp_NextSupplierRef @SuppId, @ReferenceId OUTPUT;
                INSERT INTO dbo.z_tb_SupplierLedger
                    (SuppId, TxnDate, Type, ReferenceId, InvoiceNo, Remark, DebitAmount, CreditAmount, DueDate, UserId, CDate, UDate)
                VALUES
                    (@SuppId, @TxnDate, @Type, @ReferenceId, @InvoiceNo, @Remark, @DebitAmount, @CreditAmount,
                     CASE WHEN @Type = 1 THEN ISNULL(@DueDate, DATEADD(DAY, ISNULL(@CreditDays, 0), @TxnDate)) END,
                     @UserId, SYSDATETIME(), SYSDATETIME());
                SET @LedgerId = SCOPE_IDENTITY();
            END
            ELSE
            BEGIN
                SELECT @OldSupp = SuppId, @OldType = Type, @OldCheque = ChequeId, @OldTxn = TxnDate, @OldDue = DueDate,
                       @ReferenceId = ISNULL(@ReferenceId, ReferenceId)
                FROM dbo.z_tb_SupplierLedger WITH (UPDLOCK, HOLDLOCK) WHERE LedgerId = @LedgerId;
                IF @OldType IS NULL RAISERROR(N'%s', 16, 1, N'Ledger entry not found.');
                IF @OldCheque IS NOT NULL
                    RAISERROR(N'%s', 16, 1, N'This entry was made by a written cheque - change or delete the cheque instead.');

                SELECT @Paid = ISNULL(SUM(Amount), 0) FROM dbo.z_tb_SupplierPaymentAlloc
                WHERE InvoiceLedgerId = @LedgerId OR PaymentLedgerId = @LedgerId;
                IF @Paid > 0 AND (@OldSupp <> @SuppId OR @OldType <> @Type)
                    RAISERROR(N'%s', 16, 1, N'This entry is linked to payments - the supplier and type cannot change.');
                IF @Type = 1 AND @Paid > @DebitAmount
                BEGIN
                    SET @Msg = N'This bill is already paid ' + CONVERT(NVARCHAR(30), CAST(@Paid AS MONEY), 1) + N' - the amount cannot be less.';
                    RAISERROR(N'%s', 16, 1, @Msg);
                END
                IF @Type IN (2, 3) AND @SetAllocations = 0 AND @Paid > @CreditAmount
                BEGIN
                    SET @Msg = N'This payment pays bills of ' + CONVERT(NVARCHAR(30), CAST(@Paid AS MONEY), 1) + N' - the amount cannot be less.';
                    RAISERROR(N'%s', 16, 1, @Msg);
                END

                UPDATE dbo.z_tb_SupplierLedger SET
                    SuppId = @SuppId, TxnDate = @TxnDate, Type = @Type, ReferenceId = @ReferenceId, InvoiceNo = @InvoiceNo,
                    Remark = @Remark, DebitAmount = @DebitAmount, CreditAmount = @CreditAmount, UserId = ISNULL(@UserId, UserId),
                    -- a new bill date moves the due date with it, unless a due date is given
                    DueDate = CASE WHEN @Type <> 1 THEN NULL
                                   WHEN @DueDate IS NOT NULL THEN @DueDate
                                   WHEN @OldDue IS NULL OR @OldTxn <> @TxnDate OR @OldSupp <> @SuppId
                                        THEN DATEADD(DAY, ISNULL(@CreditDays, 0), @TxnDate)
                                   ELSE @OldDue END,
                    UDate = SYSDATETIME()
                WHERE LedgerId = @LedgerId;
            END

            IF @SetAllocations = 1
                EXEC dbo.z_sp_AllocateSupplierPayment @LedgerId, @Allocations;
        COMMIT;

        SELECT @LedgerId AS LedgerId, @ReferenceId AS ReferenceId;
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

-- ---- delete a ledger entry. A cheque payment goes with its cheque; a bill that is paid stays.
CREATE PROCEDURE dbo.z_sp_DeleteSupplierLedger
    @LedgerId INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @z_tc INT; SET @z_tc = @@TRANCOUNT;
    BEGIN TRY
        DECLARE @Type INT, @ChequeId INT;
        BEGIN TRAN;
            SELECT @Type = Type, @ChequeId = ChequeId FROM dbo.z_tb_SupplierLedger WITH (UPDLOCK, HOLDLOCK) WHERE LedgerId = @LedgerId;
            IF @Type IS NULL RAISERROR(N'%s', 16, 1, N'Ledger entry not found.');
            IF @ChequeId IS NOT NULL
                RAISERROR(N'%s', 16, 1, N'This entry was made by a written cheque - delete the cheque instead.');
            IF EXISTS (SELECT 1 FROM dbo.z_tb_SupplierPaymentAlloc WHERE InvoiceLedgerId = @LedgerId)
                RAISERROR(N'%s', 16, 1, N'This bill is (partly) paid - remove it from those payments first.');
            IF EXISTS (SELECT 1 FROM dbo.z_tb_SupplierPaymentAlloc WHERE PaymentLedgerId = @LedgerId AND ChequeId IS NOT NULL)
                RAISERROR(N'%s', 16, 1, N'This return was taken off a written cheque - delete the cheque first.');
            DELETE FROM dbo.z_tb_SupplierPaymentAlloc WHERE PaymentLedgerId = @LedgerId;
            DELETE FROM dbo.z_tb_SupplierLedger WHERE LedgerId = @LedgerId;
        COMMIT;
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

-- ---- a supplier's ledger with the running balance (SQL 2008 R2: no SUM() OVER (ORDER BY)).
--      With a date range the balance still counts everything before @FromDate (it starts at the opening balance).
CREATE PROCEDURE dbo.z_Sp_GetSupplierLedger
    @SuppId   INT,
    @FromDate DATE = NULL,
    @ToDate   DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        l.LedgerId, l.SuppId, l.TxnDate, l.Type,
        CASE l.Type WHEN 1 THEN 'PURCHASE' WHEN 2 THEN 'PAYMENT' WHEN 3 THEN 'RETURN' ELSE 'UNKNOWN' END AS TypeName,
        l.ReferenceId, l.InvoiceNo, l.Remark,
        ISNULL(l.DebitAmount, 0) AS DebitAmount, ISNULL(l.CreditAmount, 0) AS CreditAmount,
        l.DueDate, l.ChequeId, c.ChequeNumber, c.ChequeDate, c.IsDebited AS ChequeDebited,
        -- bill: paid so far / still open. payment / return: how much of it pays bills
        CAST(ISNULL(CASE WHEN l.Type = 1 THEN pi.Amount ELSE pp.Amount END, 0) AS DECIMAL(18,2)) AS AllocatedAmount,
        CAST(CASE WHEN l.Type = 1 THEN ISNULL(l.DebitAmount, 0) - ISNULL(pi.Amount, 0) ELSE 0 END AS DECIMAL(18,2)) AS OpenAmount,
        CAST((SELECT SUM(ISNULL(x.DebitAmount, 0) - ISNULL(x.CreditAmount, 0)) FROM dbo.z_tb_SupplierLedger x
              WHERE x.SuppId = l.SuppId AND (x.TxnDate < l.TxnDate OR (x.TxnDate = l.TxnDate AND x.LedgerId <= l.LedgerId)))
             AS DECIMAL(18,2)) AS RunningBalance,
        l.UserId, l.CDate, l.UDate
    FROM dbo.z_tb_SupplierLedger l
    LEFT JOIN dbo.z_tb_WrittenCheque c ON c.ChequeId = l.ChequeId
    OUTER APPLY (SELECT SUM(a.Amount) AS Amount FROM dbo.z_tb_SupplierPaymentAlloc a WHERE a.InvoiceLedgerId = l.LedgerId) pi
    OUTER APPLY (SELECT SUM(a.Amount) AS Amount FROM dbo.z_tb_SupplierPaymentAlloc a WHERE a.PaymentLedgerId = l.LedgerId) pp
    WHERE l.SuppId = @SuppId
      AND (@FromDate IS NULL OR l.TxnDate >= @FromDate)
      AND (@ToDate IS NULL OR l.TxnDate <= @ToDate)
    ORDER BY l.TxnDate, l.LedgerId;
END
GO
CREATE PROCEDURE dbo.z_sp_GetSupplierLedger_ByDate
    @SuppId   INT,
    @FromDate DATE,
    @ToDate   DATE
AS
BEGIN
    SET NOCOUNT ON;
    EXEC dbo.z_Sp_GetSupplierLedger @SuppId, @FromDate, @ToDate;
END
GO

-- ---- a supplier's bills for the cheque writer: open ones (or all), oldest due first, with what paid them
CREATE PROCEDURE dbo.z_sp_GetSupplierInvoices
    @SuppId      INT,
    @IncludePaid BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Today DATE; SET @Today = GETDATE();
    SELECT
        l.LedgerId, l.SuppId, l.TxnDate, l.ReferenceId, l.InvoiceNo, l.Remark, l.DueDate,
        DATEDIFF(DAY, @Today, l.DueDate) AS DaysToDue,
        CAST(ISNULL(l.DebitAmount, 0) AS DECIMAL(18,2)) AS Amount,
        CAST(ISNULL(p.Amount, 0) AS DECIMAL(18,2)) AS PaidAmount,
        CAST(ISNULL(p.Deducted, 0) AS DECIMAL(18,2)) AS DeductedAmount,   -- part of PaidAmount settled by returns
        CAST(ISNULL(l.DebitAmount, 0) - ISNULL(p.Amount, 0) AS DECIMAL(18,2)) AS OpenAmount,
        CASE WHEN ISNULL(p.Amount, 0) = 0 THEN 'Open'
             WHEN ISNULL(p.Amount, 0) < ISNULL(l.DebitAmount, 0) THEN 'Part paid'
             ELSE 'Paid' END AS Status,
        -- "900001 (23,000.00), RETURN SUP001-00004 (2,000.00), PAYMENT SUP001-00005 (500.00)"
        STUFF((SELECT N', ' + CASE WHEN pl.Type = 3 THEN N'RETURN ' + ISNULL(pl.ReferenceId, N'')
                                   ELSE ISNULL(CAST(c.ChequeNumber AS NVARCHAR(20)), N'PAYMENT ' + ISNULL(pl.ReferenceId, N'')) END
                      + N' (' + CONVERT(NVARCHAR(30), CAST(a.Amount AS MONEY), 1) + N')'
               FROM dbo.z_tb_SupplierPaymentAlloc a
               JOIN dbo.z_tb_SupplierLedger pl ON pl.LedgerId = a.PaymentLedgerId
               LEFT JOIN dbo.z_tb_WrittenCheque c ON c.ChequeId = pl.ChequeId
               WHERE a.InvoiceLedgerId = l.LedgerId
               ORDER BY a.AllocId
               FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)'), 1, 2, N'') AS PaidBy
    FROM dbo.z_tb_SupplierLedger l
    OUTER APPLY (SELECT SUM(a.Amount) AS Amount, SUM(CASE WHEN pl.Type = 3 THEN a.Amount ELSE 0 END) AS Deducted
                 FROM dbo.z_tb_SupplierPaymentAlloc a JOIN dbo.z_tb_SupplierLedger pl ON pl.LedgerId = a.PaymentLedgerId
                 WHERE a.InvoiceLedgerId = l.LedgerId) p
    WHERE l.SuppId = @SuppId AND l.Type = 1
      AND (@IncludePaid = 1 OR ISNULL(l.DebitAmount, 0) - ISNULL(p.Amount, 0) > 0)
    ORDER BY CASE WHEN ISNULL(l.DebitAmount, 0) - ISNULL(p.Amount, 0) > 0 THEN 0 ELSE 1 END, l.DueDate, l.TxnDate, l.LedgerId;
END
GO

-- ---- bills to pay: every open bill due on or before @ToDate (overdue ones too), all suppliers or one
CREATE PROCEDURE dbo.z_sp_GetSupplierPaymentsDue
    @ToDate DATE = NULL,
    @SuppId INT  = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Today DATE; SET @Today = GETDATE();
    SET @ToDate = ISNULL(@ToDate, DATEADD(DAY, 30, @Today));
    SELECT
        l.LedgerId, l.SuppId, s.SuppCode, s.SuppName, ISNULL(s.PayeeName, s.SuppName) AS PayeeName, s.CreditDays,
        l.TxnDate, l.ReferenceId, l.InvoiceNo, l.DueDate,
        DATEDIFF(DAY, @Today, l.DueDate) AS DaysToDue,
        CAST(ISNULL(l.DebitAmount, 0) AS DECIMAL(18,2)) AS Amount,
        CAST(ISNULL(p.Amount, 0) AS DECIMAL(18,2)) AS PaidAmount,
        CAST(ISNULL(l.DebitAmount, 0) - ISNULL(p.Amount, 0) AS DECIMAL(18,2)) AS OpenAmount
    FROM dbo.z_tb_SupplierLedger l
    JOIN dbo.z_tb_Supplier s ON s.SuppId = l.SuppId
    OUTER APPLY (SELECT SUM(a.Amount) AS Amount FROM dbo.z_tb_SupplierPaymentAlloc a WHERE a.InvoiceLedgerId = l.LedgerId) p
    WHERE l.Type = 1
      AND l.DueDate <= @ToDate
      AND (@SuppId IS NULL OR l.SuppId = @SuppId)
      AND ISNULL(l.DebitAmount, 0) - ISNULL(p.Amount, 0) > 0
    ORDER BY l.DueDate, s.SuppName, l.LedgerId;
END
GO

-- ---- a cheque just written for a supplier: ONE payment row in the ledger (credit = cheque amount), paying the
--      bills in @Allocations (Amount = "cheque pay"). Deduction = taken off the bill for returns: it is set against the
--      supplier's returns not yet set against a bill (oldest first); what is still left becomes a new RETURN row
--      "Deducted on cheque ..." (ChequeId set). Amount + Deduction may not be more than what is open on the bill.
--      Run in the same transaction as the cheque insert. Returns LedgerId, ReferenceId (of the payment row).
CREATE PROCEDURE dbo.z_sp_LinkWrittenCheque
    @ChequeId    INT,
    @SuppId      INT,
    @UserId      INT = NULL,
    @Allocations dbo.z_tt_SupplierAlloc READONLY
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @z_tc INT; SET @z_tc = @@TRANCOUNT;
    BEGIN TRY
        DECLARE @No INT, @Amount DECIMAL(18,2), @ChqDate DATE, @Written DATETIME, @Linked INT, @TxnDate DATE,
                @Ref NVARCHAR(100), @LedgerId INT, @Remark NVARCHAR(500), @Bills NVARCHAR(400), @Msg NVARCHAR(400),
                @Bad NVARCHAR(100), @DedTotal DECIMAL(18,2), @Free DECIMAL(18,2), @RetRef NVARCHAR(100), @RetId INT,
                @B INT, @BL DECIMAL(18,2), @R INT, @RF DECIMAL(18,2), @X DECIMAL(18,2);
        DECLARE @Pay dbo.z_tt_SupplierAlloc;
        DECLARE @Ded TABLE (LedgerId INT PRIMARY KEY, LeftAmt DECIMAL(18,2) NOT NULL);
        DECLARE @Ret TABLE (Seq INT IDENTITY(1,1) PRIMARY KEY, LedgerId INT NOT NULL, FreeAmt DECIMAL(18,2) NOT NULL);

        BEGIN TRAN;
            SELECT @No = ChequeNumber, @Amount = Amount, @ChqDate = ChequeDate, @Written = ChequeWrittenDate, @Linked = LedgerId
            FROM dbo.z_tb_WrittenCheque WITH (UPDLOCK, HOLDLOCK) WHERE ChequeId = @ChequeId;
            IF @No IS NULL RAISERROR(N'%s', 16, 1, N'Cheque not found.');
            IF @Linked IS NOT NULL RAISERROR(N'%s', 16, 1, N'This cheque is already in the supplier ledger.');
            IF NOT EXISTS (SELECT 1 FROM dbo.z_tb_Supplier WHERE SuppId = @SuppId)
                RAISERROR(N'%s', 16, 1, N'Supplier not found.');
            IF EXISTS (SELECT 1 FROM @Allocations WHERE Amount < 0 OR Deduction < 0 OR Amount + Deduction <= 0)
                RAISERROR(N'%s', 16, 1, N'Each bill needs a cheque amount (or a deduction) above 0.');

            SELECT TOP 1 @Bad = ISNULL(l.ReferenceId, CAST(a.LedgerId AS NVARCHAR(20)))
            FROM @Allocations a
            LEFT JOIN dbo.z_tb_SupplierLedger l WITH (UPDLOCK, HOLDLOCK) ON l.LedgerId = a.LedgerId
            WHERE l.LedgerId IS NULL OR l.SuppId <> @SuppId OR l.Type <> 1;
            IF @Bad IS NOT NULL
            BEGIN
                SET @Msg = N'Bill ' + @Bad + N' is not a bill of this supplier.';
                RAISERROR(N'%s', 16, 1, @Msg);
            END
            SELECT TOP 1 @Bad = ISNULL(l.InvoiceNo, l.ReferenceId)
            FROM @Allocations a JOIN dbo.z_tb_SupplierLedger l ON l.LedgerId = a.LedgerId
            WHERE a.Amount + a.Deduction > ISNULL(l.DebitAmount, 0)
                  - ISNULL((SELECT SUM(x.Amount) FROM dbo.z_tb_SupplierPaymentAlloc x WHERE x.InvoiceLedgerId = a.LedgerId), 0);
            IF @Bad IS NOT NULL
            BEGIN
                SET @Msg = N'Bill ' + @Bad + N': cheque pay + deduction is more than what is still open on it.';
                RAISERROR(N'%s', 16, 1, @Msg);
            END

            SET @TxnDate = CAST(ISNULL(@Written, GETDATE()) AS DATE);
            SELECT @DedTotal = ISNULL(SUM(Deduction), 0) FROM @Allocations;
            SET @Bills = STUFF((SELECT N', ' + ISNULL(l.InvoiceNo, l.ReferenceId)
                                FROM @Allocations a JOIN dbo.z_tb_SupplierLedger l ON l.LedgerId = a.LedgerId
                                ORDER BY l.TxnDate, l.LedgerId
                                FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)'), 1, 2, N'');
            SET @Remark = LEFT(N'Cheque ' + CAST(@No AS NVARCHAR(20)) + N' dated ' + CONVERT(NCHAR(10), @ChqDate, 120)
                               + ISNULL(N' for ' + @Bills, N'')
                               + CASE WHEN @DedTotal > 0 THEN N' (less returns ' + CONVERT(NVARCHAR(30), CAST(@DedTotal AS MONEY), 1) + N')'
                                      ELSE N'' END, 500);

            -- 1. the cheque: one PAYMENT row paying the "cheque pay" amounts
            EXEC dbo.z_sp_NextSupplierRef @SuppId, @Ref OUTPUT;
            INSERT INTO dbo.z_tb_SupplierLedger
                (SuppId, TxnDate, Type, ReferenceId, InvoiceNo, Remark, DebitAmount, CreditAmount, DueDate, ChequeId, UserId, CDate, UDate)
            VALUES
                (@SuppId, @TxnDate, 2, @Ref, NULL, @Remark, 0, @Amount, NULL, @ChequeId, @UserId, SYSDATETIME(), SYSDATETIME());
            SET @LedgerId = SCOPE_IDENTITY();

            UPDATE dbo.z_tb_WrittenCheque SET SuppId = @SuppId, LedgerId = @LedgerId WHERE ChequeId = @ChequeId;

            INSERT INTO @Pay (LedgerId, Amount, Deduction) SELECT LedgerId, Amount, 0 FROM @Allocations WHERE Amount > 0;
            EXEC dbo.z_sp_AllocateSupplierPayment @LedgerId, @Pay, @ChequeId;

            -- 2. deductions: returns not yet set against a bill first, then a new RETURN row for the rest
            IF @DedTotal > 0
            BEGIN
                INSERT INTO @Ded (LedgerId, LeftAmt) SELECT LedgerId, Deduction FROM @Allocations WHERE Deduction > 0;

                INSERT INTO @Ret (LedgerId, FreeAmt)
                SELECT r.LedgerId, ISNULL(r.CreditAmount, 0) - ISNULL(u.Amount, 0)
                FROM dbo.z_tb_SupplierLedger r WITH (UPDLOCK, HOLDLOCK)
                OUTER APPLY (SELECT SUM(a.Amount) AS Amount FROM dbo.z_tb_SupplierPaymentAlloc a WHERE a.PaymentLedgerId = r.LedgerId) u
                WHERE r.SuppId = @SuppId AND r.Type = 3 AND ISNULL(r.CreditAmount, 0) - ISNULL(u.Amount, 0) > 0
                ORDER BY r.TxnDate, r.LedgerId;

                SELECT @Free = ISNULL(SUM(FreeAmt), 0) FROM @Ret;
                IF @Free < @DedTotal
                BEGIN
                    EXEC dbo.z_sp_NextSupplierRef @SuppId, @RetRef OUTPUT;
                    INSERT INTO dbo.z_tb_SupplierLedger
                        (SuppId, TxnDate, Type, ReferenceId, InvoiceNo, Remark, DebitAmount, CreditAmount, DueDate, ChequeId, UserId, CDate, UDate)
                    VALUES
                        (@SuppId, @TxnDate, 3, @RetRef, NULL,
                         LEFT(N'Deducted on cheque ' + CAST(@No AS NVARCHAR(20)) + N' (returns)' + ISNULL(N' for ' + @Bills, N''), 500),
                         0, @DedTotal - @Free, NULL, @ChequeId, @UserId, SYSDATETIME(), SYSDATETIME());
                    SET @RetId = SCOPE_IDENTITY();
                    INSERT INTO @Ret (LedgerId, FreeAmt) VALUES (@RetId, @DedTotal - @Free);
                END

                WHILE EXISTS (SELECT 1 FROM @Ded WHERE LeftAmt > 0)
                BEGIN
                    SELECT TOP 1 @B = LedgerId, @BL = LeftAmt FROM @Ded WHERE LeftAmt > 0 ORDER BY LedgerId;
                    SELECT TOP 1 @R = LedgerId, @RF = FreeAmt FROM @Ret WHERE FreeAmt > 0 ORDER BY Seq;
                    SET @X = CASE WHEN @BL < @RF THEN @BL ELSE @RF END;
                    INSERT INTO dbo.z_tb_SupplierPaymentAlloc (PaymentLedgerId, InvoiceLedgerId, Amount, ChequeId)
                    VALUES (@R, @B, @X, @ChequeId);
                    UPDATE @Ded SET LeftAmt = LeftAmt - @X WHERE LedgerId = @B;
                    UPDATE @Ret SET FreeAmt = FreeAmt - @X WHERE LedgerId = @R;
                END
            END
        COMMIT;

        SELECT @LedgerId AS LedgerId, @Ref AS ReferenceId;
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

-- ---- before a cheque is deleted: everything its writing made goes - its payment row, the RETURN row it made for
--      deductions, and every bill it paid or set a return against (those bills and returns are open again)
CREATE PROCEDURE dbo.z_sp_UnlinkWrittenCheque
    @ChequeId INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRAN;
        DELETE FROM dbo.z_tb_SupplierPaymentAlloc WHERE ChequeId = @ChequeId;
        DELETE a FROM dbo.z_tb_SupplierPaymentAlloc a
        JOIN dbo.z_tb_SupplierLedger l ON l.LedgerId = a.PaymentLedgerId
        WHERE l.ChequeId = @ChequeId;
        UPDATE dbo.z_tb_WrittenCheque SET LedgerId = NULL WHERE ChequeId = @ChequeId;
        DELETE FROM dbo.z_tb_SupplierLedger WHERE ChequeId = @ChequeId;
    COMMIT;
END
GO

/* ---------------------------------------------------------------------------
   Supplier Ledger page overview (U015): totals, aging, monthly purchases / payments
   --------------------------------------------------------------------------- */
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

/* ---------------------------------------------------------------------------
   4. Payees that matched no supplier: set their payee name on the supplier by hand
   --------------------------------------------------------------------------- */
IF EXISTS (SELECT 1 FROM dbo.z_tb_Payee p
           WHERE NOT EXISTS (SELECT 1 FROM dbo.z_tb_Supplier s WHERE LTRIM(RTRIM(s.SuppName)) = LTRIM(RTRIM(p.SupplierName))))
BEGIN
    PRINT 'U007: these payees have no supplier with the same name (set the payee name on the supplier page):';
    SELECT p.PayeeId, p.PayeeName, p.SupplierName FROM dbo.z_tb_Payee p
    WHERE NOT EXISTS (SELECT 1 FROM dbo.z_tb_Supplier s WHERE LTRIM(RTRIM(s.SuppName)) = LTRIM(RTRIM(p.SupplierName)))
    ORDER BY p.SupplierName;
END
GO
PRINT 'U007 back office: supplier bills, cheque links and payment allocations are ready.';
GO
SET NOEXEC OFF;
GO
