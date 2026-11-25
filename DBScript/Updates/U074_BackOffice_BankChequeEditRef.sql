/* =============================================================================
   U074_BackOffice_BankChequeEditRef.sql   (2026-11-23)
   Update for a back office db (easyway) that is ALREADY deployed (U060 run). SQL Server 2008 R2 and newer.
   Safe to run again (the edits already saved are kept).

   What changes (back office Sales > Bank transfer & cheque report):
     The transfer reference / cheque number typed at the till is often missing or wrong. It can now be corrected on
     the report (click the reference). The bill's payment line (z_tb_SalesPayment.RefNo) is changed; the till's own
     copy is not (a bill is uploaded once, so the till never overwrites the correction).
     - new table z_tb_BankChequeRefEdit: every change (old / new reference, who, when)
     - new proc  z_sp_BankChequeSetRef: change the reference of one bank transfer / cheque line
     - z_sp_DayReportBankCheque re-created: + OrigRefNo (the till's reference before the first edit),
       RefEditedBy, RefEditedAt (the last change)
   Same as the full script: 45_BackOffice_BankChequeEditRef.sql.

   Run:  sqlcmd -S <server> -d easyway -E -I -b -i U074_BackOffice_BankChequeEditRef.sql
   Then: the new ItemApi (POST api/DayReport/BankCheque/Ref) and the back office UI of 2026-11-23.
   The old ItemApi keeps working after it (the extra columns are ignored).
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
IF OBJECT_ID(N'dbo.z_tb_BankChequeStatus', 'U') IS NULL OR OBJECT_ID(N'dbo.z_sp_DayReportBankCheque', 'P') IS NULL
BEGIN
    RAISERROR('The bank transfer & cheque received status (U060) is not in this database - run it first. Nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
GO

-- one row per change of a bank transfer / cheque reference on the back office
IF OBJECT_ID(N'dbo.z_tb_BankChequeRefEdit', 'U') IS NULL
CREATE TABLE dbo.z_tb_BankChequeRefEdit (
    EditId    INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_z_tb_BankChequeRefEdit PRIMARY KEY,
    InvoiceId INT          NOT NULL,
    LineNum   INT          NOT NULL,
    OldRefNo  VARCHAR(30)  NULL,
    NewRefNo  VARCHAR(30)  NULL,
    UserId    INT          NULL,       -- z_tb_User who changed it
    EditedAt  DATETIME     NOT NULL CONSTRAINT DF_z_tb_BankChequeRefEdit_EditedAt DEFAULT (GETDATE())
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_z_tb_BankChequeRefEdit_Line' AND object_id = OBJECT_ID(N'dbo.z_tb_BankChequeRefEdit'))
CREATE INDEX IX_z_tb_BankChequeRefEdit_Line ON dbo.z_tb_BankChequeRefEdit (InvoiceId, LineNum, EditId);
GO

IF OBJECT_ID(N'dbo.z_sp_BankChequeSetRef', 'P') IS NOT NULL DROP PROCEDURE dbo.z_sp_BankChequeSetRef;
GO
-- Bank transfer & cheque report: change the reference / cheque no of one payment line (bank transfer 5 / cheque 6
-- of a bill of @LocationId, not voided). Empty = no reference. The change is logged. Returns Changed (0 = same as before).
CREATE PROCEDURE dbo.z_sp_BankChequeSetRef
    @InvoiceId  INT,
    @LineNum    INT,
    @RefNo      VARCHAR(30) = NULL,
    @UserId     INT         = NULL,
    @LocationId INT         = 1
AS
BEGIN
    DECLARE @z_tc INT; SET @z_tc = @@TRANCOUNT;   -- SQL 2008 R2 error handling (RAISERROR in TRY/CATCH)
    BEGIN TRY
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @old VARCHAR(30), @n INT;
    SET @RefNo = NULLIF(LTRIM(RTRIM(@RefNo)), '');
    SET @n = 0;

    BEGIN TRAN;
    SELECT @old = p.RefNo
    FROM dbo.z_tb_SalesPayment p WITH (UPDLOCK, HOLDLOCK)
    JOIN dbo.z_tb_SalesInvoice s ON s.InvoiceId = p.InvoiceId
    WHERE p.InvoiceId = @InvoiceId AND p.LineNum = @LineNum AND p.PayType IN (5, 6)
      AND s.Status <> 9 AND s.LocationId = @LocationId;
    IF @@ROWCOUNT = 0
        RAISERROR(N'%s', 16, 1, N'This line is not a bank transfer / cheque of a bill here (or the bill was voided).');

    IF ISNULL(@old, '') <> ISNULL(@RefNo, '')
    BEGIN
        UPDATE dbo.z_tb_SalesPayment SET RefNo = @RefNo WHERE InvoiceId = @InvoiceId AND LineNum = @LineNum;
        INSERT dbo.z_tb_BankChequeRefEdit (InvoiceId, LineNum, OldRefNo, NewRefNo, UserId)
        VALUES (@InvoiceId, @LineNum, @old, @RefNo, @UserId);
        SET @n = 1;
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
-- U074: + OrigRefNo (the till's reference before the first edit), RefEditedBy, RefEditedAt (NULL = never edited).
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
           ISNULL(mu.UserName, mu.LoginName) AS ReceivedBy, b.MarkedAt,
           fe.OldRefNo AS OrigRefNo, ISNULL(eu.UserName, eu.LoginName) AS RefEditedBy, le.EditedAt AS RefEditedAt
    FROM dbo.z_tb_SalesInvoice s
    JOIN dbo.z_tb_SalesPayment p ON p.InvoiceId = s.InvoiceId
    JOIN dbo.z_tb_Terminal t ON t.TerminalId = s.TerminalId
    LEFT JOIN dbo.z_tb_User u ON u.LoginName = s.CashierId
    LEFT JOIN dbo.z_tb_BankChequeStatus b ON b.InvoiceId = p.InvoiceId AND b.LineNum = p.LineNum
    LEFT JOIN dbo.z_tb_User mu ON mu.UserId = b.UserId
    OUTER APPLY (SELECT TOP 1 e.OldRefNo FROM dbo.z_tb_BankChequeRefEdit e
                 WHERE e.InvoiceId = p.InvoiceId AND e.LineNum = p.LineNum ORDER BY e.EditId) fe
    OUTER APPLY (SELECT TOP 1 e.UserId, e.EditedAt FROM dbo.z_tb_BankChequeRefEdit e
                 WHERE e.InvoiceId = p.InvoiceId AND e.LineNum = p.LineNum ORDER BY e.EditId DESC) le
    LEFT JOIN dbo.z_tb_User eu ON eu.UserId = le.UserId
    WHERE s.InvDate >= @F AND s.InvDate < @T AND s.LocationId = @LocationId AND s.Status <> 9
      AND p.PayType IN (5, 6)
      AND (@PayType IS NULL OR p.PayType = @PayType)
      AND (@TerminalId IS NULL OR s.TerminalId = @TerminalId)
      AND (@Status IS NULL OR (@Status = 0 AND b.InvoiceId IS NULL) OR (@Status = 1 AND b.InvoiceId IS NOT NULL))
    ORDER BY s.InvDate, s.InvoiceId, p.LineNum;
END
GO
SET NOEXEC OFF;
GO
PRINT 'U074 back office: bank transfer & cheque reference edit (z_tb_BankChequeRefEdit, z_sp_BankChequeSetRef).';
GO
