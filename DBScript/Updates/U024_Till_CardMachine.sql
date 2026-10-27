/* =============================================================================
   U024_Till_CardMachine.sql   (2026-10-27)
   Update for a till db (z_pos_fnt_db) that is ALREADY deployed. SQL Server 2008 R2 and newer.
   Safe to run again. Bills, Z reports and logs are not changed (one new, empty table).

   What changes (card machine / ECR - PAX A910 on the till PC, Docs/StockSystem.md 6.29):
     - table zf_tb_CardPayment: every card charge sent to the machine, written BEFORE the bill (EcrRef, amount,
       approved or not, approval code, the machine's invoice number, masked card number, the bill it went on).
       Status 0 at the machine, 1 approved, 2 not approved, 3 approved for another amount, 4 no answer,
       5 voided on the machine (marked by a supervisor).
     - type zf_tt_CardPayUse
     - zf_sp_StartCardPayment (before charging: reuse an approved one of the bill, or the same EcrRef for a retry),
       zf_sp_EndCardPayment (the machine's answer), zf_sp_UseCardPayments (on the bill, in the bill's transaction),
       zf_sp_GetCardPayments (one / to check / one day), zf_sp_SetCardPaymentVoided (supervisor)
   Same change in the full script: 02_FrontCashier_zf.sql.

   Order: on each till
     1. sqlcmd -S .\SQLEXPRESS -d z_pos_fnt_db -E -I -b -i U024_Till_CardMachine.sql
     2. install the new TillService and the new billing page (the old ones keep working after the script).
        The card machine is OFF until it is switched on in Menu > Card machine (ecr.json next to TillService.exe).
   ============================================================================= */
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
IF OBJECT_ID(N'dbo.zf_tb_InvoicePayment', 'U') IS NULL OR OBJECT_ID(N'dbo.zf_tb_ZReport', 'U') IS NULL
   OR OBJECT_ID(N'dbo.zf_tb_Config', 'U') IS NULL
BEGIN
    RAISERROR('This is not a till database (zf_tb_InvoicePayment / zf_tb_ZReport / zf_tb_Config not found) - nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
GO

-- 1. table
IF OBJECT_ID(N'dbo.zf_tb_CardPayment', 'U') IS NULL
CREATE TABLE dbo.zf_tb_CardPayment (
    CardPayId     INT              IDENTITY(1,1) NOT NULL CONSTRAINT PK_zf_tb_CardPayment PRIMARY KEY,
    EcrRef        VARCHAR(32)      NULL,       -- sent to the machine: 3-digit terminal + 9-digit CardPayId
    BillKey       UNIQUEIDENTIFIER NOT NULL,   -- the bill on the screen (its draft key)
    CashierId     VARCHAR(20)      NULL,
    Amount        DECIMAL(18,2)    NOT NULL,
    Status        INT              NOT NULL,
    Attempts      INT              NOT NULL CONSTRAINT DF_zf_tb_CardPayment_Attempts DEFAULT (1),
    Message       NVARCHAR(400)    NULL,
    ResponseCode  VARCHAR(10)      NULL,
    ApprovalCode  VARCHAR(20)      NULL,
    TermInvoiceNo VARCHAR(20)      NULL,       -- the machine's invoice number (to void on the machine)
    BatchNo       VARCHAR(20)      NULL,
    Tid           VARCHAR(20)      NULL,
    Mid           VARCHAR(30)      NULL,
    CardNo        VARCHAR(20)      NULL,       -- masked, e.g. 411111XXXXXX1234
    CardType      VARCHAR(20)      NULL,
    CardHolder    NVARCHAR(50)     NULL,
    EntryMode     VARCHAR(20)      NULL,
    FromLast      BIT              NOT NULL CONSTRAINT DF_zf_tb_CardPayment_FromLast DEFAULT (0),
    StartedAt     DATETIME         NOT NULL CONSTRAINT DF_zf_tb_CardPayment_StartedAt DEFAULT (GETDATE()),
    EndedAt       DATETIME         NULL,
    InvoiceNo     VARCHAR(30)      NULL,       -- the bill it is on
    PayLineNum    INT              NULL,
    UsedAt        DATETIME         NULL,
    VoidedBy      VARCHAR(20)      NULL,
    VoidReason    NVARCHAR(100)    NULL,
    VoidedAt      DATETIME         NULL
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_zf_tb_CardPayment_Bill' AND object_id = OBJECT_ID('dbo.zf_tb_CardPayment'))
    CREATE INDEX IX_zf_tb_CardPayment_Bill ON dbo.zf_tb_CardPayment (BillKey);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_zf_tb_CardPayment_Status' AND object_id = OBJECT_ID('dbo.zf_tb_CardPayment'))
    CREATE INDEX IX_zf_tb_CardPayment_Status ON dbo.zf_tb_CardPayment (Status, InvoiceNo);
GO

-- 2. type (its proc is dropped first)
IF OBJECT_ID(N'dbo.zf_sp_UseCardPayments', 'P') IS NOT NULL DROP PROCEDURE dbo.zf_sp_UseCardPayments;
GO
IF TYPE_ID(N'dbo.zf_tt_CardPayUse') IS NOT NULL DROP TYPE dbo.zf_tt_CardPayUse;
GO
-- card payments going on a bill (zf_sp_UseCardPayments): which one, on which payment line, for how much
CREATE TYPE dbo.zf_tt_CardPayUse AS TABLE (
    CardPayId INT           NOT NULL PRIMARY KEY,
    LineNum   INT           NOT NULL,
    Amount    DECIMAL(18,2) NOT NULL
);
GO

-- 3. procedures (same as 02_FrontCashier_zf.sql)
IF OBJECT_ID(N'dbo.zf_sp_GetCardPayments', 'P') IS NOT NULL DROP PROCEDURE dbo.zf_sp_GetCardPayments;
GO
-- One card payment (@CardPayId), or the ones that need a look (@ToCheck 1: approved but on no bill, approved for
-- another amount, no answer, at the machine for more than 5 minutes), or one day's (@Date, by StartedAt). Newest first.
CREATE PROCEDURE dbo.zf_sp_GetCardPayments
    @CardPayId INT  = NULL,
    @ToCheck   BIT  = 0,
    @Date      DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT CardPayId, EcrRef, BillKey, CashierId, Amount, Status, Attempts, Message, ResponseCode, ApprovalCode,
           TermInvoiceNo, BatchNo, Tid, Mid, CardNo, CardType, CardHolder, EntryMode, FromLast, StartedAt, EndedAt,
           InvoiceNo, PayLineNum, UsedAt, VoidedBy, VoidReason, VoidedAt
    FROM dbo.zf_tb_CardPayment
    WHERE (@CardPayId IS NOT NULL AND CardPayId = @CardPayId)
       OR (@CardPayId IS NULL AND @ToCheck = 1
           AND InvoiceNo IS NULL
           AND (Status IN (1, 3, 4) OR (Status = 0 AND StartedAt < DATEADD(MINUTE, -5, GETDATE()))))
       OR (@CardPayId IS NULL AND @ToCheck = 0 AND @Date IS NOT NULL
           AND StartedAt >= @Date AND StartedAt < DATEADD(DAY, 1, @Date))
    ORDER BY CardPayId DESC;
END
GO

IF OBJECT_ID(N'dbo.zf_sp_StartCardPayment', 'P') IS NOT NULL DROP PROCEDURE dbo.zf_sp_StartCardPayment;
GO
-- Before the machine is asked to charge @Amount for the bill @BillKey. Returns the row to use:
--   Status 1 = this bill already has an approved card payment of @Amount not on a bill yet - use it, do NOT charge;
--   Status 0 = charge it with its EcrRef. The last try of the same amount that was not approved / had no answer is
--              used again (same EcrRef: if the customer paid after all, the machine's last transaction shows it).
-- An approved one of ANOTHER amount still waiting for this bill -> 51082 (never two charges on one bill by mistake).
CREATE PROCEDURE dbo.zf_sp_StartCardPayment
    @BillKey   UNIQUEIDENTIFIER,
    @CashierId VARCHAR(20) = NULL,
    @Amount    DECIMAL(18,2)
AS
BEGIN
    DECLARE @z_tc INT; SET @z_tc = @@TRANCOUNT;   -- SQL 2008 R2 error handling (RAISERROR in TRY/CATCH)
    BEGIN TRY
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @Id INT, @Other DECIMAL(18,2), @TermId INT, @Msg NVARCHAR(400);
    IF @Amount <= 0 OR @Amount > 999999.99
        RAISERROR(N'%s', 16, 1, N'Card amount must be above 0 and below 1,000,000.');

    BEGIN TRAN;
        SELECT TOP 1 @Id = CardPayId, @Other = Amount
        FROM dbo.zf_tb_CardPayment WITH (UPDLOCK, HOLDLOCK)
        WHERE BillKey = @BillKey AND Status = 1 AND InvoiceNo IS NULL
        ORDER BY CardPayId;
        IF @Id IS NOT NULL AND @Other <> @Amount
        BEGIN
            SET @Msg = N'A card payment of Rs ' + CONVERT(NVARCHAR(30), @Other) + N' is already approved for this bill. '
                     + N'Pay Rs ' + CONVERT(NVARCHAR(30), @Other) + N' by card, or void it on the card machine and mark it '
                     + N'voided (Menu > Card machine).';
            RAISERROR(N'%s', 16, 1, @Msg);
        END

        IF @Id IS NULL
        BEGIN
            SELECT TOP 1 @Id = CardPayId
            FROM dbo.zf_tb_CardPayment WITH (UPDLOCK, HOLDLOCK)
            WHERE BillKey = @BillKey AND Amount = @Amount AND InvoiceNo IS NULL AND Status IN (0, 2, 4)
            ORDER BY CardPayId DESC;

            IF @Id IS NOT NULL
                UPDATE dbo.zf_tb_CardPayment
                SET Status = 0, Attempts = Attempts + 1, StartedAt = GETDATE(), EndedAt = NULL, Message = NULL,
                    CashierId = ISNULL(@CashierId, CashierId)
                WHERE CardPayId = @Id;
            ELSE
            BEGIN
                SELECT @TermId = TerminalId FROM dbo.zf_tb_Config WHERE Id = 1;
                INSERT dbo.zf_tb_CardPayment (BillKey, CashierId, Amount, Status) VALUES (@BillKey, @CashierId, @Amount, 0);
                SET @Id = SCOPE_IDENTITY();
                UPDATE dbo.zf_tb_CardPayment
                SET EcrRef = RIGHT('000' + CAST(ISNULL(@TermId, 0) % 1000 AS VARCHAR(10)), 3)
                           + RIGHT('000000000' + CAST(@Id AS VARCHAR(10)), 9)
                WHERE CardPayId = @Id;
            END
        END
    COMMIT;

    EXEC dbo.zf_sp_GetCardPayments @CardPayId = @Id;
    END TRY
    BEGIN CATCH
        DECLARE @z_msg NVARCHAR(2048); SET @z_msg = ERROR_MESSAGE();
        IF @z_tc = 0
        BEGIN
            IF XACT_STATE() <> 0 ROLLBACK;
        END
        ELSE
        BEGIN
            -- called inside the caller's transaction: give its level back, the caller's CATCH rolls back
            WHILE @@TRANCOUNT > @z_tc AND XACT_STATE() = 1 COMMIT;
        END
        RAISERROR(N'%s', 16, 1, @z_msg);
        RETURN 1;
    END CATCH
END
GO

IF OBJECT_ID(N'dbo.zf_sp_EndCardPayment', 'P') IS NOT NULL DROP PROCEDURE dbo.zf_sp_EndCardPayment;
GO
-- The machine's answer. Only a row at the machine (0) or with no answer yet (4) changes. Returns the row.
CREATE PROCEDURE dbo.zf_sp_EndCardPayment
    @CardPayId     INT,
    @Status        INT,
    @Message       NVARCHAR(400) = NULL,
    @ResponseCode  VARCHAR(10)   = NULL,
    @ApprovalCode  VARCHAR(20)   = NULL,
    @TermInvoiceNo VARCHAR(20)   = NULL,
    @BatchNo       VARCHAR(20)   = NULL,
    @Tid           VARCHAR(20)   = NULL,
    @Mid           VARCHAR(30)   = NULL,
    @CardNo        VARCHAR(20)   = NULL,
    @CardType      VARCHAR(20)   = NULL,
    @CardHolder    NVARCHAR(50)  = NULL,
    @EntryMode     VARCHAR(20)   = NULL,
    @FromLast      BIT           = 0
AS
BEGIN
    DECLARE @z_tc INT; SET @z_tc = @@TRANCOUNT;   -- SQL 2008 R2 error handling (RAISERROR in TRY/CATCH)
    BEGIN TRY
    SET NOCOUNT ON;
    IF @Status NOT IN (1, 2, 3, 4)
        RAISERROR(N'%s', 16, 1, N'Card payment end Status must be 1 to 4.');
    UPDATE dbo.zf_tb_CardPayment
    SET Status = @Status, Message = @Message, ResponseCode = @ResponseCode, ApprovalCode = @ApprovalCode,
        TermInvoiceNo = @TermInvoiceNo, BatchNo = @BatchNo, Tid = @Tid, Mid = @Mid, CardNo = @CardNo,
        CardType = @CardType, CardHolder = @CardHolder, EntryMode = @EntryMode, FromLast = @FromLast, EndedAt = GETDATE()
    WHERE CardPayId = @CardPayId AND Status IN (0, 4);

    EXEC dbo.zf_sp_GetCardPayments @CardPayId = @CardPayId;
    END TRY
    BEGIN CATCH
        DECLARE @z_msg NVARCHAR(2048); SET @z_msg = ERROR_MESSAGE();
        IF @z_tc = 0
        BEGIN
            IF XACT_STATE() <> 0 ROLLBACK;
        END
        ELSE
        BEGIN
            -- called inside the caller's transaction: give its level back, the caller's CATCH rolls back
            WHILE @@TRANCOUNT > @z_tc AND XACT_STATE() = 1 COMMIT;
        END
        RAISERROR(N'%s', 16, 1, @z_msg);
        RETURN 1;
    END CATCH
END
GO

IF OBJECT_ID(N'dbo.zf_sp_UseCardPayments', 'P') IS NOT NULL DROP PROCEDURE dbo.zf_sp_UseCardPayments;
GO
-- Called by TillService in the SAME transaction as zf_sp_SaveInvoice: the approved card payments go on the bill.
-- Each must be approved, not on a bill yet, for the amount of its card payment line (51083 otherwise).
CREATE PROCEDURE dbo.zf_sp_UseCardPayments
    @InvoiceNo VARCHAR(30),
    @Rows      dbo.zf_tt_CardPayUse READONLY
AS
BEGIN
    DECLARE @z_tc INT; SET @z_tc = @@TRANCOUNT;   -- SQL 2008 R2 error handling (RAISERROR in TRY/CATCH)
    BEGIN TRY
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM @Rows r
               WHERE NOT EXISTS (SELECT 1 FROM dbo.zf_tb_CardPayment c WITH (UPDLOCK, HOLDLOCK)
                                 WHERE c.CardPayId = r.CardPayId AND c.Status = 1 AND c.InvoiceNo IS NULL AND c.Amount = r.Amount)
                  OR NOT EXISTS (SELECT 1 FROM dbo.zf_tb_InvoicePayment p
                                 WHERE p.InvoiceNo = @InvoiceNo AND p.LineNum = r.LineNum AND p.PayType = 2 AND p.Amount = r.Amount))
        RAISERROR(N'%s', 16, 1, N'The card payment is not approved, is already on a bill, or its amount differs - pay by card again.');

    UPDATE c SET InvoiceNo = @InvoiceNo, PayLineNum = r.LineNum, UsedAt = GETDATE()
    FROM dbo.zf_tb_CardPayment c
    JOIN @Rows r ON r.CardPayId = c.CardPayId;
    END TRY
    BEGIN CATCH
        DECLARE @z_msg NVARCHAR(2048); SET @z_msg = ERROR_MESSAGE();
        IF @z_tc = 0
        BEGIN
            IF XACT_STATE() <> 0 ROLLBACK;
        END
        ELSE
        BEGIN
            -- called inside the caller's transaction: give its level back, the caller's CATCH rolls back
            WHILE @@TRANCOUNT > @z_tc AND XACT_STATE() = 1 COMMIT;
        END
        RAISERROR(N'%s', 16, 1, @z_msg);
        RETURN 1;
    END CATCH
END
GO

IF OBJECT_ID(N'dbo.zf_sp_SetCardPaymentVoided', 'P') IS NOT NULL DROP PROCEDURE dbo.zf_sp_SetCardPaymentVoided;
GO
-- A supervisor says the payment was voided on the machine (or never went through). Only one not on a bill.
CREATE PROCEDURE dbo.zf_sp_SetCardPaymentVoided
    @CardPayId INT,
    @VoidedBy  VARCHAR(20) = NULL,
    @Reason    NVARCHAR(100)
AS
BEGIN
    DECLARE @z_tc INT; SET @z_tc = @@TRANCOUNT;   -- SQL 2008 R2 error handling (RAISERROR in TRY/CATCH)
    BEGIN TRY
    SET NOCOUNT ON;
    IF LTRIM(RTRIM(ISNULL(@Reason, N''))) = N''
        RAISERROR(N'%s', 16, 1, N'Give a reason.');
    UPDATE dbo.zf_tb_CardPayment
    SET Status = 5, VoidedBy = @VoidedBy, VoidReason = LTRIM(RTRIM(@Reason)), VoidedAt = GETDATE()
    WHERE CardPayId = @CardPayId AND InvoiceNo IS NULL AND Status <> 5;
    IF @@ROWCOUNT = 0
        RAISERROR(N'%s', 16, 1, N'This card payment is on a bill or was already marked voided.');
    END TRY
    BEGIN CATCH
        DECLARE @z_msg NVARCHAR(2048); SET @z_msg = ERROR_MESSAGE();
        IF @z_tc = 0
        BEGIN
            IF XACT_STATE() <> 0 ROLLBACK;
        END
        ELSE
        BEGIN
            -- called inside the caller's transaction: give its level back, the caller's CATCH rolls back
            WHILE @@TRANCOUNT > @z_tc AND XACT_STATE() = 1 COMMIT;
        END
        RAISERROR(N'%s', 16, 1, @z_msg);
        RETURN 1;
    END CATCH
END
GO

PRINT 'U024_Till_CardMachine done.';
GO
