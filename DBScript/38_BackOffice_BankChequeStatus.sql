/* =============================================================================
   38_BackOffice_BankChequeStatus.sql   (2026-11-13)
   Full script for a back office db (easyway), run after 37_BackOffice_Wallet.sql. SQL Server 2008 R2 and newer.
   Safe to run again (the received marks already saved are kept).

   What changes: Bank transfer & cheque report - each payment line is Pending or Received (the day the cheque was
   handed over / the transfer reached the bank, a note, who marked it). New table z_tb_BankChequeStatus, type
   z_tt_BankChequeKey, proc z_sp_BankChequeSetStatus; re-creates z_sp_DayReportBankCheque (from 21) with the status
   and @Status (NULL all, 0 pending, 1 received). Till (live via api/Sync): z_sp_TillBankCheque,
   z_sp_TillBankChequeSetStatus, type z_tt_TillBankChequeKey.
   Same as the update script: Updates\U060_BackOffice_BankChequeStatus.sql.

   Run:  sqlcmd -S <server> -d easyway -E -I -b -i 38_BackOffice_BankChequeStatus.sql
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
IF OBJECT_ID(N'dbo.z_tb_SalesInvoice', 'U') IS NULL OR OBJECT_ID(N'dbo.z_tb_SalesPayment', 'U') IS NULL
   OR OBJECT_ID(N'dbo.z_sp_DayReportBankCheque', 'P') IS NULL
BEGIN
    RAISERROR('The bank transfer & cheque report (U042) is not in this database - run it first. Nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
GO

-- one row = that bank transfer / cheque payment line was received (no row = pending)
IF OBJECT_ID(N'dbo.z_tb_BankChequeStatus', 'U') IS NULL
CREATE TABLE dbo.z_tb_BankChequeStatus (
    InvoiceId    INT           NOT NULL,
    LineNum      INT           NOT NULL,
    ReceivedDate DATE          NOT NULL,   -- the day the cheque was handed over / the transfer reached the bank
    Note         NVARCHAR(200) NULL,
    UserId       INT           NULL,       -- z_tb_User who marked it
    MarkedAt     DATETIME      NOT NULL CONSTRAINT DF_z_tb_BankChequeStatus_MarkedAt DEFAULT (GETDATE()),
    CONSTRAINT PK_z_tb_BankChequeStatus PRIMARY KEY (InvoiceId, LineNum)
);
GO

-- the procs using the types go first, so the types can be dropped and made again
IF OBJECT_ID(N'dbo.z_sp_TillBankChequeSetStatus', 'P') IS NOT NULL DROP PROCEDURE dbo.z_sp_TillBankChequeSetStatus;
IF OBJECT_ID(N'dbo.z_sp_TillBankCheque', 'P') IS NOT NULL DROP PROCEDURE dbo.z_sp_TillBankCheque;
IF OBJECT_ID(N'dbo.z_sp_BankChequeSetStatus', 'P') IS NOT NULL DROP PROCEDURE dbo.z_sp_BankChequeSetStatus;
GO
IF TYPE_ID(N'dbo.z_tt_TillBankChequeKey') IS NOT NULL DROP TYPE dbo.z_tt_TillBankChequeKey;
IF TYPE_ID(N'dbo.z_tt_BankChequeKey') IS NOT NULL DROP TYPE dbo.z_tt_BankChequeKey;
GO
-- column order must match the DataTable built in AppDbContext.DayReport.cs
CREATE TYPE dbo.z_tt_BankChequeKey AS TABLE (
    InvoiceId INT NOT NULL,
    LineNum   INT NOT NULL,
    PRIMARY KEY (InvoiceId, LineNum)
);
GO
-- Bank transfer & cheque report: the ticked payment lines -> received (@Received 1, on @ReceivedDate with @Note;
-- already received = date / note changed) or back to pending (@Received 0, the row removed).
-- Only bank transfer (5) / cheque (6) lines of bills of @LocationId that are not voided. Returns Changed.
CREATE PROCEDURE dbo.z_sp_BankChequeSetStatus
    @Received     BIT,
    @ReceivedDate DATE          = NULL,
    @Note         NVARCHAR(200) = NULL,
    @UserId       INT           = NULL,
    @LocationId   INT           = 1,
    @Keys         dbo.z_tt_BankChequeKey READONLY
AS
BEGIN
    DECLARE @z_tc INT; SET @z_tc = @@TRANCOUNT;   -- SQL 2008 R2 error handling (RAISERROR in TRY/CATCH)
    BEGIN TRY
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @n INT;
    IF NOT EXISTS (SELECT 1 FROM @Keys)
        RAISERROR(N'%s', 16, 1, N'Tick at least one bank transfer or cheque.');
    IF EXISTS (SELECT 1 FROM @Keys k
               WHERE NOT EXISTS (SELECT 1 FROM dbo.z_tb_SalesPayment p
                                 JOIN dbo.z_tb_SalesInvoice s ON s.InvoiceId = p.InvoiceId
                                 WHERE p.InvoiceId = k.InvoiceId AND p.LineNum = k.LineNum AND p.PayType IN (5, 6)
                                   AND s.Status <> 9 AND s.LocationId = @LocationId))
        RAISERROR(N'%s', 16, 1, N'A ticked line is not a bank transfer / cheque of a bill here (or the bill was voided).');
    IF @Received = 1
    BEGIN
        IF @ReceivedDate IS NULL
            RAISERROR(N'%s', 16, 1, N'Pick the date it was received.');
        IF @ReceivedDate > CAST(GETDATE() AS DATE)
            RAISERROR(N'%s', 16, 1, N'The received date cannot be in the future.');
        IF EXISTS (SELECT 1 FROM @Keys k JOIN dbo.z_tb_SalesInvoice s ON s.InvoiceId = k.InvoiceId
                   WHERE CAST(s.InvDate AS DATE) > @ReceivedDate)
            RAISERROR(N'%s', 16, 1, N'The received date is before the bill date of a ticked line.');
    END

    BEGIN TRAN;
    IF @Received = 1
    BEGIN
        UPDATE b SET ReceivedDate = @ReceivedDate, Note = NULLIF(LTRIM(RTRIM(@Note)), N''), UserId = @UserId, MarkedAt = GETDATE()
        FROM dbo.z_tb_BankChequeStatus b WITH (UPDLOCK, HOLDLOCK)
        JOIN @Keys k ON k.InvoiceId = b.InvoiceId AND k.LineNum = b.LineNum;
        SET @n = @@ROWCOUNT;

        INSERT dbo.z_tb_BankChequeStatus (InvoiceId, LineNum, ReceivedDate, Note, UserId)
        SELECT k.InvoiceId, k.LineNum, @ReceivedDate, NULLIF(LTRIM(RTRIM(@Note)), N''), @UserId
        FROM @Keys k
        WHERE NOT EXISTS (SELECT 1 FROM dbo.z_tb_BankChequeStatus b WHERE b.InvoiceId = k.InvoiceId AND b.LineNum = k.LineNum);
        SET @n = @n + @@ROWCOUNT;
    END
    ELSE
    BEGIN
        DELETE b FROM dbo.z_tb_BankChequeStatus b
        JOIN @Keys k ON k.InvoiceId = b.InvoiceId AND k.LineNum = b.LineNum;
        SET @n = @@ROWCOUNT;
    END
    COMMIT;

    SELECT @n AS Changed;
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

IF OBJECT_ID(N'dbo.z_sp_DayReportBankCheque', 'P') IS NOT NULL DROP PROCEDURE dbo.z_sp_DayReportBankCheque;
GO
-- Bank transfer (5) and cheque (6) payments of the bills dated @From..@To (both included), oldest first (U042).
-- Voided bills (Status 9) left out; refund bills (InvType 2) negative, like the till Z. @PayType NULL = both.
-- U060: + the received status (z_tb_BankChequeStatus); @Status NULL = all, 0 = pending only, 1 = received only.
CREATE PROCEDURE dbo.z_sp_DayReportBankCheque
    @From DATE, @To DATE, @LocationId INT = 1, @TerminalId INT = NULL, @PayType INT = NULL, @Status INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @F DATETIME, @T DATETIME;
    SET @F = @From;
    SET @T = DATEADD(DAY, 1, CAST(@To AS DATETIME));

    SELECT s.InvoiceId, s.InvoiceNo, s.TerminalId, t.TerminalCode, s.ZNo, s.InvType, s.InvDate, s.CashierId,
           u.UserName AS CashierName, s.NetAmount, p.LineNum, p.PayType,
           CASE WHEN s.InvType = 2 THEN -p.Amount ELSE p.Amount END AS Amount,
           p.RefNo,
           CAST(CASE WHEN b.InvoiceId IS NULL THEN 0 ELSE 1 END AS BIT) AS Received,
           CAST(b.ReceivedDate AS DATETIME) AS ReceivedDate, b.Note AS ReceivedNote,
           ISNULL(mu.UserName, mu.LoginName) AS ReceivedBy, b.MarkedAt
    FROM dbo.z_tb_SalesInvoice s
    JOIN dbo.z_tb_SalesPayment p ON p.InvoiceId = s.InvoiceId
    JOIN dbo.z_tb_Terminal t ON t.TerminalId = s.TerminalId
    LEFT JOIN dbo.z_tb_User u ON u.LoginName = s.CashierId
    LEFT JOIN dbo.z_tb_BankChequeStatus b ON b.InvoiceId = p.InvoiceId AND b.LineNum = p.LineNum
    LEFT JOIN dbo.z_tb_User mu ON mu.UserId = b.UserId
    WHERE s.InvDate >= @F AND s.InvDate < @T AND s.LocationId = @LocationId AND s.Status <> 9
      AND p.PayType IN (5, 6)
      AND (@PayType IS NULL OR p.PayType = @PayType)
      AND (@TerminalId IS NULL OR s.TerminalId = @TerminalId)
      AND (@Status IS NULL OR (@Status = 0 AND b.InvoiceId IS NULL) OR (@Status = 1 AND b.InvoiceId IS NOT NULL))
    ORDER BY s.InvDate, s.InvoiceId, p.LineNum;
END
GO

-- ---- the till (Menu > Bank & cheque), called live by TillService with the terminal key ----

-- the bank transfer / cheque lines of one till: every line of Z @ZNo (any status) + the lines of its earlier Zs still
-- pending, bills from @Since. Bills not uploaded yet are not here (the till shows them as "not uploaded yet").
CREATE PROCEDURE dbo.z_sp_TillBankCheque
    @TerminalId INT, @ZNo INT = NULL, @Since DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @F DATETIME;
    SET @F = ISNULL(@Since, DATEADD(DAY, -365, CAST(GETDATE() AS DATE)));

    SELECT s.InvoiceNo, p.LineNum, s.ZNo, s.InvType, s.InvDate, s.CashierId, p.PayType,
           CASE WHEN s.InvType = 2 THEN -p.Amount ELSE p.Amount END AS Amount,
           p.RefNo,
           CAST(CASE WHEN b.InvoiceId IS NULL THEN 0 ELSE 1 END AS BIT) AS Received,
           CAST(b.ReceivedDate AS DATETIME) AS ReceivedDate, b.Note AS ReceivedNote,
           ISNULL(mu.UserName, mu.LoginName) AS ReceivedBy
    FROM dbo.z_tb_SalesInvoice s
    JOIN dbo.z_tb_SalesPayment p ON p.InvoiceId = s.InvoiceId
    LEFT JOIN dbo.z_tb_BankChequeStatus b ON b.InvoiceId = p.InvoiceId AND b.LineNum = p.LineNum
    LEFT JOIN dbo.z_tb_User mu ON mu.UserId = b.UserId
    WHERE s.TerminalId = @TerminalId AND s.Status <> 9 AND p.PayType IN (5, 6)
      AND (s.ZNo = @ZNo OR (b.InvoiceId IS NULL AND s.InvDate >= @F))
    ORDER BY s.InvDate, s.InvoiceId, p.LineNum;
END
GO
-- column order must match the DataTable built in AppDbContext.DayReport.cs
CREATE TYPE dbo.z_tt_TillBankChequeKey AS TABLE (
    InvoiceNo VARCHAR(30) NOT NULL,
    LineNum   INT         NOT NULL,
    PRIMARY KEY (InvoiceNo, LineNum)
);
GO
-- The till marks its own bills' lines received / back to pending (z_sp_BankChequeSetStatus, same checks); the user =
-- the cashier's back office login (none = no name). A bill not uploaded yet is refused. Returns Changed.
CREATE PROCEDURE dbo.z_sp_TillBankChequeSetStatus
    @TerminalId   INT,
    @CashierId    VARCHAR(50)   = NULL,
    @Received     BIT,
    @ReceivedDate DATE          = NULL,
    @Note         NVARCHAR(200) = NULL,
    @Keys         dbo.z_tt_TillBankChequeKey READONLY
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @LocationId INT, @UserId INT, @missing VARCHAR(30), @msg NVARCHAR(400);
    DECLARE @k dbo.z_tt_BankChequeKey;

    SELECT @LocationId = LocationId FROM dbo.z_tb_Terminal WHERE TerminalId = @TerminalId AND Status = 1;
    IF @LocationId IS NULL
    BEGIN
        RAISERROR(N'%s', 16, 1, N'Terminal is not registered or is disabled.');
        RETURN 1;
    END

    SELECT TOP 1 @missing = k.InvoiceNo FROM @Keys k
    WHERE NOT EXISTS (SELECT 1 FROM dbo.z_tb_SalesInvoice s JOIN dbo.z_tb_SalesPayment p ON p.InvoiceId = s.InvoiceId
                      WHERE s.InvoiceNo = k.InvoiceNo AND s.TerminalId = @TerminalId AND p.LineNum = k.LineNum);
    IF @missing IS NOT NULL
    BEGIN
        SET @msg = N'Bill ' + @missing + N' is not on the back office yet - wait for the till to upload it.';
        RAISERROR(N'%s', 16, 1, @msg);
        RETURN 1;
    END

    INSERT @k (InvoiceId, LineNum)
    SELECT s.InvoiceId, k.LineNum FROM @Keys k JOIN dbo.z_tb_SalesInvoice s ON s.InvoiceNo = k.InvoiceNo AND s.TerminalId = @TerminalId;

    SELECT @UserId = UserId FROM dbo.z_tb_User WHERE LoginName = @CashierId;

    EXEC dbo.z_sp_BankChequeSetStatus @Received = @Received, @ReceivedDate = @ReceivedDate, @Note = @Note,
         @UserId = @UserId, @LocationId = @LocationId, @Keys = @k;
END
GO
SET NOEXEC OFF;
GO
PRINT '38 back office: bank transfer & cheque received status (z_tb_BankChequeStatus, z_sp_BankChequeSetStatus).';
GO
