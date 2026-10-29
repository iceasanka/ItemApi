/* =============================================================================
   U032_BackOffice_TillPayments.sql   (2026-10-29)
   Update for the back office db (easyway) that is ALREADY deployed. SQL Server 2008 R2 and newer.
   Safe to run again. No data is changed (three new, empty tables). Needs U007 (supplier bill allocations) and U018
   (till cash movements).

   What changes (supplier bills paid in cash from a till, Docs/StockSystem.md 6.32):
     - tables z_tb_TillPayRequest (a request: supplier, cash to pay, till or any till, waiting / paid / cancelled, the
       paid out and the PAYMENT row it made), z_tb_TillPayRequestLine (the bills / returns picked and how much),
       z_tb_TillPayReceipt (each paid out received from a till - a resend is skipped)
     - types z_tt_TillPayLine, z_tt_TillPayPaid
     - procedures z_sp_TillPayRequestAdd, z_sp_TillPayRequestCancel, z_sp_GetTillPayRequests (Supplier Ledger page),
       z_sp_GetTillPayRequestsForSync (till download), z_sp_TillPayRequestsPaid + z_sp_TillPayAlloc (till upload: the
       PAYMENT row; returns then cash set against the bills, oldest first)
   Same objects in the full script: 26_BackOffice_TillPayments.sql.

   Order: this script, then the new ItemApi (the old one keeps working after it), then the back office UI; on each
   till U032_Till_PayRequests.sql, then the new TillService and billing page.
   ============================================================================= */
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
IF OBJECT_ID(N'dbo.z_tb_SupplierLedger', 'U') IS NULL OR OBJECT_ID(N'dbo.z_tb_Terminal', 'U') IS NULL
BEGIN
    RAISERROR('This is not the back office database (z_tb_SupplierLedger / z_tb_Terminal not found) - nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
GO
IF OBJECT_ID(N'dbo.z_tb_SupplierPaymentAlloc', 'U') IS NULL OR OBJECT_ID(N'dbo.z_sp_NextSupplierRef', 'P') IS NULL
BEGIN
    RAISERROR('Run U007_BackOffice_SupplierPayments.sql first (bill allocations) - nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
GO

-- 1. tables
-- A request to pay a supplier in cash from a till: made on the Supplier Ledger page from the bills (and returns) picked,
-- downloaded by the till(s), paid there as a Paid Out. When the till sends the paid out up, the ledger gets a PAYMENT
-- row and the bills are settled: the returns picked first, then the cash (oldest bill first). Less cash than the bills
-- after returns = part payment: the rest stays open on the bills.
IF OBJECT_ID(N'dbo.z_tb_TillPayRequest', 'U') IS NULL
CREATE TABLE dbo.z_tb_TillPayRequest (
    RequestId       INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_z_tb_TillPayRequest PRIMARY KEY,
    SuppId          INT            NOT NULL,
    TerminalId      INT            NULL,          -- the till to pay it; NULL = any till
    Amount          DECIMAL(18,2)  NOT NULL,      -- cash to pay
    Remark          NVARCHAR(100)  NOT NULL,      -- the paid out reason on the till
    Status          INT            NOT NULL CONSTRAINT DF_z_tb_TillPayRequest_Status DEFAULT (0),  -- 0 waiting, 1 paid, 2 cancelled
    CreatedAt       DATETIME       NOT NULL CONSTRAINT DF_z_tb_TillPayRequest_CreatedAt DEFAULT (GETDATE()),
    CreatedBy       INT            NULL,
    CancelledAt     DATETIME       NULL,
    CancelledBy     INT            NULL,
    PaidAt          DATETIME       NULL,          -- till time of the paid out
    PaidTerminalId  INT            NULL,
    PaidMoveId      INT            NULL,          -- zf_tb_CashMovement.MoveId on that till
    PaidZNo         INT            NULL,
    PaidCashierId   VARCHAR(20)    NULL,
    PaidAmount      DECIMAL(18,2)  NULL,
    PaymentLedgerId INT            NULL,          -- the PAYMENT row it made in z_tb_SupplierLedger
    ReceivedAt      DATETIME       NULL
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_z_tb_TillPayRequest_Status')
    CREATE INDEX IX_z_tb_TillPayRequest_Status ON dbo.z_tb_TillPayRequest (Status, TerminalId);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_z_tb_TillPayRequest_Supp')
    CREATE INDEX IX_z_tb_TillPayRequest_Supp ON dbo.z_tb_TillPayRequest (SuppId, CreatedAt);
GO
-- the bills (Type 1) and returns (Type 3) picked, with the amount of each to settle / use
IF OBJECT_ID(N'dbo.z_tb_TillPayRequestLine', 'U') IS NULL
CREATE TABLE dbo.z_tb_TillPayRequestLine (
    RequestId INT           NOT NULL,
    LedgerId  INT           NOT NULL,
    Amount    DECIMAL(18,2) NOT NULL,
    CONSTRAINT PK_z_tb_TillPayRequestLine PRIMARY KEY (RequestId, LedgerId)
);
GO
-- every paid out of a request a till sent up (a resend is skipped; a request paid twice gets a 2nd PAYMENT row)
IF OBJECT_ID(N'dbo.z_tb_TillPayReceipt', 'U') IS NULL
CREATE TABLE dbo.z_tb_TillPayReceipt (
    TerminalId      INT      NOT NULL,
    MoveId          INT      NOT NULL,
    RequestId       INT      NOT NULL,
    PaymentLedgerId INT      NULL,
    ReceivedAt      DATETIME NOT NULL CONSTRAINT DF_z_tb_TillPayReceipt_ReceivedAt DEFAULT (GETDATE()),
    CONSTRAINT PK_z_tb_TillPayReceipt PRIMARY KEY (TerminalId, MoveId)
);
GO

-- 2. types (dropped with their procs)
IF OBJECT_ID(N'dbo.z_sp_TillPayRequestAdd', 'P')        IS NOT NULL DROP PROCEDURE dbo.z_sp_TillPayRequestAdd;
IF OBJECT_ID(N'dbo.z_sp_TillPayRequestCancel', 'P')     IS NOT NULL DROP PROCEDURE dbo.z_sp_TillPayRequestCancel;
IF OBJECT_ID(N'dbo.z_sp_GetTillPayRequests', 'P')       IS NOT NULL DROP PROCEDURE dbo.z_sp_GetTillPayRequests;
IF OBJECT_ID(N'dbo.z_sp_GetTillPayRequestsForSync', 'P') IS NOT NULL DROP PROCEDURE dbo.z_sp_GetTillPayRequestsForSync;
IF OBJECT_ID(N'dbo.z_sp_TillPayRequestsPaid', 'P')      IS NOT NULL DROP PROCEDURE dbo.z_sp_TillPayRequestsPaid;
IF OBJECT_ID(N'dbo.z_sp_TillPayAlloc', 'P')             IS NOT NULL DROP PROCEDURE dbo.z_sp_TillPayAlloc;
GO
IF TYPE_ID(N'dbo.z_tt_TillPayLine') IS NOT NULL DROP TYPE dbo.z_tt_TillPayLine;
IF TYPE_ID(N'dbo.z_tt_TillPayPaid') IS NOT NULL DROP TYPE dbo.z_tt_TillPayPaid;
GO
CREATE TYPE dbo.z_tt_TillPayLine AS TABLE (
    LedgerId INT           NOT NULL PRIMARY KEY,   -- a bill (Type 1) or a return (Type 3) of the supplier
    Amount   DECIMAL(18,2) NOT NULL                -- bill: to settle, return: to use
);
GO
CREATE TYPE dbo.z_tt_TillPayPaid AS TABLE (
    MoveId    INT           NOT NULL PRIMARY KEY,  -- the paid out on the till
    RequestId INT           NOT NULL,
    ZNo       INT           NULL,
    Amount    DECIMAL(18,2) NOT NULL,
    CashierId VARCHAR(20)   NULL,
    PaidAt    DATETIME      NOT NULL
);
GO

-- 3. procedures
-- A new request from the Supplier Ledger page. Returns RequestId.
CREATE PROCEDURE dbo.z_sp_TillPayRequestAdd
    @SuppId     INT,
    @TerminalId INT = NULL,
    @Amount     DECIMAL(18,2),
    @Remark     NVARCHAR(100) = NULL,
    @Lines      dbo.z_tt_TillPayLine READONLY,
    @UserId     INT = NULL
AS
BEGIN
    DECLARE @z_tc INT; SET @z_tc = @@TRANCOUNT;   -- SQL 2008 R2 error handling (RAISERROR in TRY/CATCH)
    BEGIN TRY
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @SuppName NVARCHAR(200), @Bills DECIMAL(18,2), @Returns DECIMAL(18,2), @Bad NVARCHAR(100), @Msg NVARCHAR(400), @Id INT;

    SELECT @SuppName = SuppName FROM dbo.z_tb_Supplier WHERE SuppId = @SuppId;
    IF @SuppName IS NULL RAISERROR(N'%s', 16, 1, N'Supplier not found.');
    IF @TerminalId IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.z_tb_Terminal WHERE TerminalId = @TerminalId AND Status = 1)
        RAISERROR(N'%s', 16, 1, N'That till is not registered or is disabled.');
    IF NOT EXISTS (SELECT 1 FROM @Lines) RAISERROR(N'%s', 16, 1, N'Pick the bills to pay.');
    IF EXISTS (SELECT 1 FROM @Lines WHERE Amount <= 0) RAISERROR(N'%s', 16, 1, N'Each bill / return needs an amount above 0.');

    BEGIN TRAN;
        SELECT TOP 1 @Bad = ISNULL(l.ReferenceId, CAST(x.LedgerId AS NVARCHAR(20)))
        FROM @Lines x LEFT JOIN dbo.z_tb_SupplierLedger l WITH (UPDLOCK, HOLDLOCK) ON l.LedgerId = x.LedgerId
        WHERE l.LedgerId IS NULL OR l.SuppId <> @SuppId OR l.Type NOT IN (1, 3);
        IF @Bad IS NOT NULL
        BEGIN
            SET @Msg = N'Entry ' + @Bad + N' is not a bill or a return of this supplier.';
            RAISERROR(N'%s', 16, 1, @Msg);
        END
        IF NOT EXISTS (SELECT 1 FROM @Lines x JOIN dbo.z_tb_SupplierLedger l ON l.LedgerId = x.LedgerId WHERE l.Type = 1)
            RAISERROR(N'%s', 16, 1, N'Pick at least one bill (a purchase) to pay.');

        -- no more than is still open on each bill / left on each return
        SELECT TOP 1 @Bad = l.ReferenceId
        FROM @Lines x JOIN dbo.z_tb_SupplierLedger l ON l.LedgerId = x.LedgerId
        WHERE x.Amount > CASE WHEN l.Type = 1
                              THEN ISNULL(l.DebitAmount, 0) - ISNULL((SELECT SUM(a.Amount) FROM dbo.z_tb_SupplierPaymentAlloc a WHERE a.InvoiceLedgerId = l.LedgerId), 0)
                              ELSE ISNULL(l.CreditAmount, 0) - ISNULL((SELECT SUM(a.Amount) FROM dbo.z_tb_SupplierPaymentAlloc a WHERE a.PaymentLedgerId = l.LedgerId), 0) END;
        IF @Bad IS NOT NULL
        BEGIN
            SET @Msg = N'Entry ' + @Bad + N' has less open than that - refresh the ledger.';
            RAISERROR(N'%s', 16, 1, @Msg);
        END

        -- a bill / return can wait on one request only
        SELECT TOP 1 @Bad = l.ReferenceId
        FROM @Lines x
        JOIN dbo.z_tb_TillPayRequestLine rl ON rl.LedgerId = x.LedgerId
        JOIN dbo.z_tb_TillPayRequest r WITH (UPDLOCK, HOLDLOCK) ON r.RequestId = rl.RequestId AND r.Status = 0
        JOIN dbo.z_tb_SupplierLedger l ON l.LedgerId = x.LedgerId;
        IF @Bad IS NOT NULL
        BEGIN
            SET @Msg = N'Entry ' + @Bad + N' is already waiting to be paid at a till - cancel that request first.';
            RAISERROR(N'%s', 16, 1, @Msg);
        END

        SELECT @Bills = SUM(CASE WHEN l.Type = 1 THEN x.Amount ELSE 0 END),
               @Returns = SUM(CASE WHEN l.Type = 3 THEN x.Amount ELSE 0 END)
        FROM @Lines x JOIN dbo.z_tb_SupplierLedger l ON l.LedgerId = x.LedgerId;
        IF @Bills - @Returns <= 0
            RAISERROR(N'%s', 16, 1, N'The returns cover the bills - nothing to pay in cash. Set the returns against the bills on the ledger (Edit the return).');
        IF @Amount IS NULL OR @Amount <= 0 RAISERROR(N'%s', 16, 1, N'Enter the cash to pay (above 0).');
        IF @Amount > @Bills - @Returns
        BEGIN
            SET @Msg = N'The cash is more than the bills less the returns (' + CONVERT(NVARCHAR(30), CAST(@Bills - @Returns AS MONEY), 1) + N').';
            RAISERROR(N'%s', 16, 1, @Msg);
        END

        INSERT dbo.z_tb_TillPayRequest (SuppId, TerminalId, Amount, Remark, Status, CreatedBy)
        VALUES (@SuppId, @TerminalId, @Amount, LEFT(ISNULL(NULLIF(LTRIM(RTRIM(@Remark)), N''), N'Supplier ' + @SuppName), 100), 0, @UserId);
        SET @Id = SCOPE_IDENTITY();
        INSERT dbo.z_tb_TillPayRequestLine (RequestId, LedgerId, Amount) SELECT @Id, LedgerId, Amount FROM @Lines;
    COMMIT;
    SELECT @Id AS RequestId;
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

-- A waiting request is taken back (the tills drop it at their next download). A till that paid it before that still
-- sends the paid out up, and it is booked as usual.
CREATE PROCEDURE dbo.z_sp_TillPayRequestCancel
    @RequestId INT,
    @UserId    INT = NULL
AS
BEGIN
    DECLARE @z_tc INT; SET @z_tc = @@TRANCOUNT;
    BEGIN TRY
    SET NOCOUNT ON;
    UPDATE dbo.z_tb_TillPayRequest SET Status = 2, CancelledAt = GETDATE(), CancelledBy = @UserId
    WHERE RequestId = @RequestId AND Status = 0;
    IF @@ROWCOUNT = 0 RAISERROR(N'%s', 16, 1, N'Only a request that is still waiting can be cancelled.');
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

-- The requests (newest first): of one supplier / one status, NULL = all.
CREATE PROCEDURE dbo.z_sp_GetTillPayRequests
    @SuppId INT = NULL,
    @Status INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT TOP 300 r.RequestId, r.SuppId, s.SuppName, r.TerminalId, t.TerminalCode, r.Amount, r.Remark, r.Status,
           r.CreatedAt, r.CreatedBy, r.CancelledAt, r.PaidAt, r.PaidTerminalId, pt.TerminalCode AS PaidTerminalCode,
           r.PaidMoveId, r.PaidCashierId, r.PaidAmount, r.PaymentLedgerId, p.ReferenceId AS PaymentRef,
           CAST(ISNULL((SELECT SUM(x.Amount) FROM dbo.z_tb_TillPayRequestLine x JOIN dbo.z_tb_SupplierLedger l ON l.LedgerId = x.LedgerId
                        WHERE x.RequestId = r.RequestId AND l.Type = 1), 0) AS DECIMAL(18,2)) AS BillsAmount,
           CAST(ISNULL((SELECT SUM(x.Amount) FROM dbo.z_tb_TillPayRequestLine x JOIN dbo.z_tb_SupplierLedger l ON l.LedgerId = x.LedgerId
                        WHERE x.RequestId = r.RequestId AND l.Type = 3), 0) AS DECIMAL(18,2)) AS ReturnsAmount,
           CAST(STUFF((SELECT N', ' + ISNULL(NULLIF(l.InvoiceNo, N''), l.ReferenceId)
                       FROM dbo.z_tb_TillPayRequestLine x JOIN dbo.z_tb_SupplierLedger l ON l.LedgerId = x.LedgerId
                       WHERE x.RequestId = r.RequestId ORDER BY l.Type, l.TxnDate, l.LedgerId
                       FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)'), 1, 2, N'') AS NVARCHAR(1000)) AS Refs
    FROM dbo.z_tb_TillPayRequest r
    JOIN dbo.z_tb_Supplier s ON s.SuppId = r.SuppId
    LEFT JOIN dbo.z_tb_Terminal t ON t.TerminalId = r.TerminalId
    LEFT JOIN dbo.z_tb_Terminal pt ON pt.TerminalId = r.PaidTerminalId
    LEFT JOIN dbo.z_tb_SupplierLedger p ON p.LedgerId = r.PaymentLedgerId
    WHERE (@SuppId IS NULL OR r.SuppId = @SuppId) AND (@Status IS NULL OR r.Status = @Status)
    ORDER BY r.RequestId DESC;
END
GO

-- What a till may pay now: the waiting requests for that till or for any till (the whole list every download).
CREATE PROCEDURE dbo.z_sp_GetTillPayRequestsForSync
    @TerminalId INT
AS
BEGIN
    DECLARE @z_tc INT; SET @z_tc = @@TRANCOUNT;
    BEGIN TRY
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM dbo.z_tb_Terminal WHERE TerminalId = @TerminalId AND Status = 1)
        RAISERROR(N'%s', 16, 1, N'Terminal is not registered or is disabled.');
    SELECT r.RequestId, s.SuppName, r.Amount, r.Remark, r.CreatedAt
    FROM dbo.z_tb_TillPayRequest r
    JOIN dbo.z_tb_Supplier s ON s.SuppId = r.SuppId
    WHERE r.Status = 0 AND (r.TerminalId IS NULL OR r.TerminalId = @TerminalId)
    ORDER BY r.RequestId;
    END TRY
    BEGIN CATCH
        DECLARE @z_msg NVARCHAR(2048); SET @z_msg = ERROR_MESSAGE();
        RAISERROR(N'%s', 16, 1, @z_msg);
        RETURN 1;
    END CATCH
END
GO

-- (inside z_sp_TillPayRequestsPaid) sets @Available of a payment / return row against the request's bills, oldest bill
-- first, each bill no more than its line amount less what this payment already set (#TillPayDone) and what is still
-- open on it. @Available comes back as what was not used.
CREATE PROCEDURE dbo.z_sp_TillPayAlloc
    @RequestId       INT,
    @PaymentLedgerId INT,
    @Available       DECIMAL(18,2) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Bill INT, @Need DECIMAL(18,2), @Open DECIMAL(18,2), @Take DECIMAL(18,2);
    DECLARE bills CURSOR LOCAL FAST_FORWARD FOR
        SELECT x.LedgerId, x.Amount
        FROM dbo.z_tb_TillPayRequestLine x JOIN dbo.z_tb_SupplierLedger l ON l.LedgerId = x.LedgerId
        WHERE x.RequestId = @RequestId AND l.Type = 1
        ORDER BY l.TxnDate, l.LedgerId;
    OPEN bills;
    FETCH NEXT FROM bills INTO @Bill, @Need;
    WHILE @@FETCH_STATUS = 0 AND @Available > 0
    BEGIN
        SELECT @Open = ISNULL(l.DebitAmount, 0) - ISNULL((SELECT SUM(a.Amount) FROM dbo.z_tb_SupplierPaymentAlloc a WHERE a.InvoiceLedgerId = l.LedgerId), 0)
        FROM dbo.z_tb_SupplierLedger l WHERE l.LedgerId = @Bill;
        SET @Take = @Need - ISNULL((SELECT SUM(Amount) FROM #TillPayDone WHERE BillId = @Bill), 0);
        IF @Take > @Open SET @Take = @Open;
        IF @Take > @Available SET @Take = @Available;
        IF @Take > 0
        BEGIN
            IF EXISTS (SELECT 1 FROM dbo.z_tb_SupplierPaymentAlloc WHERE PaymentLedgerId = @PaymentLedgerId AND InvoiceLedgerId = @Bill AND ChequeId IS NULL)
                UPDATE dbo.z_tb_SupplierPaymentAlloc SET Amount = Amount + @Take
                WHERE PaymentLedgerId = @PaymentLedgerId AND InvoiceLedgerId = @Bill AND ChequeId IS NULL;
            ELSE
                INSERT dbo.z_tb_SupplierPaymentAlloc (PaymentLedgerId, InvoiceLedgerId, Amount, ChequeId, CDate) VALUES (@PaymentLedgerId, @Bill, @Take, NULL, GETDATE());
            INSERT #TillPayDone (BillId, Amount) VALUES (@Bill, @Take);
            SET @Available = @Available - @Take;
        END
        FETCH NEXT FROM bills INTO @Bill, @Need;
    END
    CLOSE bills;
    DEALLOCATE bills;
END
GO

-- A till sends the paid outs it made for requests. Each one (once - a resend is skipped) becomes a PAYMENT row of the
-- supplier; the first payment of a request also settles its bills: the returns picked, then the cash. A request paid
-- again (two tills, or after a cancel) gets one more PAYMENT row, not set against bills (remark "paid again").
-- Returns Received = how many were booked.
CREATE PROCEDURE dbo.z_sp_TillPayRequestsPaid
    @TerminalId INT,
    @Rows       dbo.z_tt_TillPayPaid READONLY
AS
BEGIN
    DECLARE @z_tc INT; SET @z_tc = @@TRANCOUNT;
    BEGIN TRY
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @Code VARCHAR(10), @MoveId INT, @ReqId INT, @ZNo INT, @Amount DECIMAL(18,2), @CashierId VARCHAR(20), @PaidAt DATETIME,
            @SuppId INT, @Status INT, @Remark NVARCHAR(100), @Ref NVARCHAR(100), @PayId INT, @Left DECIMAL(18,2),
            @RetId INT, @RetAmt DECIMAL(18,2), @RetOpen DECIMAL(18,2), @Received INT;
    SET @Received = 0;
    SELECT @Code = TerminalCode FROM dbo.z_tb_Terminal WHERE TerminalId = @TerminalId AND Status = 1;
    IF @Code IS NULL RAISERROR(N'%s', 16, 1, N'Terminal is not registered or is disabled.');
    IF EXISTS (SELECT 1 FROM @Rows WHERE Amount <= 0) RAISERROR(N'%s', 16, 1, N'A paid out needs an amount above 0.');

    CREATE TABLE #TillPayDone (BillId INT NOT NULL, Amount DECIMAL(18,2) NOT NULL);
    DECLARE paid CURSOR LOCAL FAST_FORWARD FOR
        SELECT MoveId, RequestId, ZNo, Amount, CashierId, PaidAt FROM @Rows ORDER BY PaidAt, MoveId;
    OPEN paid;
    FETCH NEXT FROM paid INTO @MoveId, @ReqId, @ZNo, @Amount, @CashierId, @PaidAt;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @SuppId = NULL;
        BEGIN TRAN;
            IF NOT EXISTS (SELECT 1 FROM dbo.z_tb_TillPayReceipt WITH (UPDLOCK, HOLDLOCK) WHERE TerminalId = @TerminalId AND MoveId = @MoveId)
            BEGIN
                SELECT @SuppId = SuppId, @Status = Status, @Remark = Remark
                FROM dbo.z_tb_TillPayRequest WITH (UPDLOCK, HOLDLOCK) WHERE RequestId = @ReqId;
                SET @PayId = NULL;
                IF @SuppId IS NOT NULL
                BEGIN
                    SET @Ref = NULL;
                    EXEC dbo.z_sp_NextSupplierRef @SuppId, @Ref OUTPUT;
                    INSERT dbo.z_tb_SupplierLedger (SuppId, TxnDate, Type, ReferenceId, InvoiceNo, Remark, DebitAmount, CreditAmount, DueDate, UserId, CDate, UDate)
                    VALUES (@SuppId, CAST(@PaidAt AS DATE), 2, @Ref, NULL,
                            LEFT(CASE WHEN @Status = 1 THEN N'PAID AGAIN - check. ' ELSE N'' END
                                 + N'Cash at till ' + @Code + N' (paid out ' + CAST(@MoveId AS NVARCHAR(10)) + N', request '
                                 + CAST(@ReqId AS NVARCHAR(10)) + N') - ' + ISNULL(@Remark, N''), 500),
                            0, @Amount, NULL, NULL, SYSDATETIME(), SYSDATETIME());
                    SET @PayId = SCOPE_IDENTITY();

                    IF @Status <> 1
                    BEGIN
                        TRUNCATE TABLE #TillPayDone;
                        -- 1. the returns picked (what is still left on each)
                        DECLARE rets CURSOR LOCAL FAST_FORWARD FOR
                            SELECT x.LedgerId, x.Amount FROM dbo.z_tb_TillPayRequestLine x
                            JOIN dbo.z_tb_SupplierLedger l ON l.LedgerId = x.LedgerId
                            WHERE x.RequestId = @ReqId AND l.Type = 3 ORDER BY l.TxnDate, l.LedgerId;
                        OPEN rets;
                        FETCH NEXT FROM rets INTO @RetId, @RetAmt;
                        WHILE @@FETCH_STATUS = 0
                        BEGIN
                            SELECT @RetOpen = ISNULL(l.CreditAmount, 0) - ISNULL((SELECT SUM(a.Amount) FROM dbo.z_tb_SupplierPaymentAlloc a WHERE a.PaymentLedgerId = l.LedgerId), 0)
                            FROM dbo.z_tb_SupplierLedger l WHERE l.LedgerId = @RetId;
                            SET @Left = CASE WHEN @RetAmt < @RetOpen THEN @RetAmt ELSE @RetOpen END;
                            IF @Left > 0 EXEC dbo.z_sp_TillPayAlloc @ReqId, @RetId, @Left OUTPUT;
                            FETCH NEXT FROM rets INTO @RetId, @RetAmt;
                        END
                        CLOSE rets;
                        DEALLOCATE rets;
                        -- 2. the cash
                        SET @Left = @Amount;
                        EXEC dbo.z_sp_TillPayAlloc @ReqId, @PayId, @Left OUTPUT;

                        UPDATE dbo.z_tb_TillPayRequest
                        SET Status = 1, PaidAt = @PaidAt, PaidTerminalId = @TerminalId, PaidMoveId = @MoveId, PaidZNo = @ZNo,
                            PaidCashierId = @CashierId, PaidAmount = @Amount, PaymentLedgerId = @PayId, ReceivedAt = GETDATE()
                        WHERE RequestId = @ReqId;
                    END
                END
                INSERT dbo.z_tb_TillPayReceipt (TerminalId, MoveId, RequestId, PaymentLedgerId) VALUES (@TerminalId, @MoveId, @ReqId, @PayId);
                SET @Received = @Received + 1;
            END
        COMMIT;
        FETCH NEXT FROM paid INTO @MoveId, @ReqId, @ZNo, @Amount, @CashierId, @PaidAt;
    END
    CLOSE paid;
    DEALLOCATE paid;
    SELECT @Received AS Received;
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

PRINT 'U032_BackOffice_TillPayments done.';
GO
