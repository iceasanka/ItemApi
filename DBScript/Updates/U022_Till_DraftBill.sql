/* =============================================================================
   U022_Till_DraftBill.sql   (2026-10-26)
   Update for a till db (z_pos_fnt_db) that is ALREADY deployed. SQL Server 2008 R2 and newer.
   Safe to run again. Bills, Z reports, suspended bills and logs are not changed (four new, empty tables).

   What changes (bill recovery after a power cut, back office Day Reports > Abandoned bills, Docs/StockSystem.md 6.27):
     - table zf_tb_DraftBill (+ zf_tb_DraftBillItem): the bill on the billing screen, saved by the page as it changes
       (POST /draft). Status 0 open, 1 paid, 2 suspended, 3 cleared, 8 thrown away after a restart. A bill paid or
       suspended closes its draft in the SAME transaction (TillService), so a power cut can never leave a paid bill
       that is offered again.
     - table zf_tb_AbandonedBill (+ zf_tb_AbandonedBillItem): a bill found open after a restart (power cut, crash,
       browser closed) - what was on it then, taken back (Outcome 1) or thrown away (2), and how it ended.
       Sent to the back office (api/Sync/AbandonedBills); a row whose end changes is sent again.
     - types zf_tt_DraftItem, zf_tt_AbandonSent
     - zf_sp_SaveDraftBill / zf_sp_CloseDraftBill / zf_sp_GetOpenDraftBills / zf_sp_RecoverDraftBill /
       zf_sp_DiscardDraftBill / zf_sp_LogAbandonedBill                     the billing page via TillService
     - zf_sp_GetUnsyncedAbandonedBills / zf_sp_MarkAbandonedBillsSynced   upload
   Same change in the full script: 02_FrontCashier_zf.sql.

   Order: U022_BackOffice_AbandonedBills.sql + the new ItemApi first, then on each till:
     1. sqlcmd -S .\SQLEXPRESS -d z_pos_fnt_db -E -I -b -i U022_Till_DraftBill.sql
     2. install the new TillService and the new billing page (the old ones keep working after the script)
   ============================================================================= */
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
IF OBJECT_ID(N'dbo.zf_tb_SuspendedBill', 'U') IS NULL OR OBJECT_ID(N'dbo.zf_tb_ZReport', 'U') IS NULL
   OR OBJECT_ID(N'dbo.zf_tb_Config', 'U') IS NULL
BEGIN
    RAISERROR('This is not a till database (zf_tb_SuspendedBill / zf_tb_ZReport / zf_tb_Config not found) - nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
GO
-- The bill on the billing screen, saved by the page as it changes (one row per bill, DraftKey made by the page).
-- Status 0 open (on the screen - or left there by a power cut / crash / closed browser), 1 paid, 2 suspended,
-- 3 cleared (void bill / every line taken off), 8 thrown away after a restart. A closed row loses its lines and is
-- deleted after 7 days; until then a save that arrives late can't open it again. SaveSeq: an older save is ignored.
IF OBJECT_ID(N'dbo.zf_tb_DraftBill', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.zf_tb_DraftBill (
        DraftKey         UNIQUEIDENTIFIER NOT NULL CONSTRAINT PK_zf_tb_DraftBill PRIMARY KEY,
        SaveSeq          INT           NOT NULL,
        Status           INT           NOT NULL,
        CashierId        VARCHAR(20)   NULL,
        InvType          INT           NOT NULL,   -- 1 sale, 2 refund
        PriceType        INT           NOT NULL,   -- the page's default for new lines (1 retail, 2 wholesale)
        Discount         DECIMAL(18,2) NOT NULL,   -- bill discount
        DiscountPercent  DECIMAL(5,2)  NULL,
        LineCount        INT           NOT NULL,
        NetAmount        DECIMAL(18,2) NOT NULL,   -- SUM(line Amount) - Discount
        PageState        NVARCHAR(MAX) NULL,       -- the page's own extras (an exchange held for the bill), JSON
        StartedAt        DATETIME      NOT NULL,
        SavedAt          DATETIME      NOT NULL,
        ClosedAt         DATETIME      NULL,
        InvoiceNo        VARCHAR(30)   NULL,       -- Status 1
        SuspendId        INT           NULL,       -- Status 2
        Recovered        INT           NOT NULL CONSTRAINT DF_zf_tb_DraftBill_Recovered DEFAULT (0)   -- taken back after a restart
    );
    CREATE INDEX IX_zf_tb_DraftBill_Status ON dbo.zf_tb_DraftBill (Status, SavedAt);
    PRINT 'zf_tb_DraftBill created.';
END
GO
IF OBJECT_ID(N'dbo.zf_tb_DraftBillItem', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.zf_tb_DraftBillItem (
        DraftKey    UNIQUEIDENTIFIER NOT NULL,
        LineNum     INT           NOT NULL,
        ItemId      INT           NOT NULL,   -- 0 = other item
        PriceLinkId INT           NULL,
        PriceType   INT           NOT NULL,   -- 1 retail, 2 wholesale
        Qty         DECIMAL(18,3) NOT NULL,
        UnitPrice   DECIMAL(18,2) NOT NULL,
        Discount    DECIMAL(18,2) NOT NULL,
        Amount      DECIMAL(18,2) NOT NULL,
        LineDescrip NVARCHAR(50)  NULL,       -- other item only
        Name        NVARCHAR(100) NULL,       -- as on the screen (the abandoned bills report keeps it)
        CONSTRAINT PK_zf_tb_DraftBillItem PRIMARY KEY (DraftKey, LineNum)
    );
    PRINT 'zf_tb_DraftBillItem created.';
END
GO
-- A bill found open after a restart: what was on it at that moment (LineCount / NetAmount / the lines), taken back
-- (Outcome 1) or thrown away (Outcome 2, supervisor PIN, Reason), and how the bill ended: FinalStatus as
-- zf_tb_DraftBill.Status (NULL = still open). ZNo = the open Z when it was found. A row whose FinalStatus changes
-- is set back to Synced 0 and goes to the back office again.
IF OBJECT_ID(N'dbo.zf_tb_AbandonedBill', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.zf_tb_AbandonedBill (
        AbandonId    INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_zf_tb_AbandonedBill PRIMARY KEY,
        DraftKey     UNIQUEIDENTIFIER NOT NULL,
        ZNo          INT           NULL,
        CashierId    VARCHAR(20)   NULL,       -- who was billing
        InvType      INT           NOT NULL,
        LineCount    INT           NOT NULL,
        NetAmount    DECIMAL(18,2) NOT NULL,
        StartedAt    DATETIME      NOT NULL,   -- first line of the bill
        LastSavedAt  DATETIME      NOT NULL,   -- last change saved before it stopped
        FoundAt      DATETIME      NOT NULL,
        FoundBy      VARCHAR(20)   NULL,       -- cashier signed in when it was found
        Outcome      INT           NOT NULL,   -- 1 taken back, 2 thrown away
        Reason       NVARCHAR(100) NULL,
        FinalStatus  INT           NULL,       -- 1 paid, 2 suspended, 3 cleared, 8 thrown away
        FinalAt      DATETIME      NULL,
        InvoiceNo    VARCHAR(30)   NULL,
        SuspendId    INT           NULL,
        Synced       BIT           NOT NULL CONSTRAINT DF_zf_tb_AbandonedBill_Synced DEFAULT (0),
        SyncedAt     DATETIME      NULL
    );
    CREATE INDEX IX_zf_tb_AbandonedBill_Synced ON dbo.zf_tb_AbandonedBill (Synced, AbandonId);
    CREATE INDEX IX_zf_tb_AbandonedBill_Draft ON dbo.zf_tb_AbandonedBill (DraftKey);
    PRINT 'zf_tb_AbandonedBill created.';
END
GO
IF OBJECT_ID(N'dbo.zf_tb_AbandonedBillItem', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.zf_tb_AbandonedBillItem (
        AbandonId  INT           NOT NULL,
        LineNum    INT           NOT NULL,
        ItemId     INT           NOT NULL,   -- 0 = other item
        Descrip    NVARCHAR(100) NULL,
        Qty        DECIMAL(18,3) NOT NULL,
        UnitPrice  DECIMAL(18,2) NOT NULL,
        Discount   DECIMAL(18,2) NOT NULL,
        Amount     DECIMAL(18,2) NOT NULL,
        CONSTRAINT PK_zf_tb_AbandonedBillItem PRIMARY KEY (AbandonId, LineNum)
    );
    PRINT 'zf_tb_AbandonedBillItem created.';
END
GO
IF OBJECT_ID(N'dbo.zf_sp_SaveDraftBill', 'P') IS NOT NULL DROP PROCEDURE dbo.zf_sp_SaveDraftBill;
IF OBJECT_ID(N'dbo.zf_sp_CloseDraftBill', 'P') IS NOT NULL DROP PROCEDURE dbo.zf_sp_CloseDraftBill;
IF OBJECT_ID(N'dbo.zf_sp_GetOpenDraftBills', 'P') IS NOT NULL DROP PROCEDURE dbo.zf_sp_GetOpenDraftBills;
IF OBJECT_ID(N'dbo.zf_sp_LogAbandonedBill', 'P') IS NOT NULL DROP PROCEDURE dbo.zf_sp_LogAbandonedBill;
IF OBJECT_ID(N'dbo.zf_sp_RecoverDraftBill', 'P') IS NOT NULL DROP PROCEDURE dbo.zf_sp_RecoverDraftBill;
IF OBJECT_ID(N'dbo.zf_sp_DiscardDraftBill', 'P') IS NOT NULL DROP PROCEDURE dbo.zf_sp_DiscardDraftBill;
IF OBJECT_ID(N'dbo.zf_sp_GetUnsyncedAbandonedBills', 'P') IS NOT NULL DROP PROCEDURE dbo.zf_sp_GetUnsyncedAbandonedBills;
IF OBJECT_ID(N'dbo.zf_sp_MarkAbandonedBillsSynced', 'P') IS NOT NULL DROP PROCEDURE dbo.zf_sp_MarkAbandonedBillsSynced;
GO
IF TYPE_ID('dbo.zf_tt_DraftItem') IS NOT NULL DROP TYPE dbo.zf_tt_DraftItem;
IF TYPE_ID('dbo.zf_tt_AbandonSent') IS NOT NULL DROP TYPE dbo.zf_tt_AbandonSent;
GO
-- the lines of the bill on the screen (zf_sp_SaveDraftBill)
CREATE TYPE dbo.zf_tt_DraftItem AS TABLE (
    LineNum     INT           NOT NULL PRIMARY KEY,
    ItemId      INT           NOT NULL,
    PriceLinkId INT           NULL,
    PriceType   INT           NULL,      -- NULL -> the bill's @PriceType
    Qty         DECIMAL(18,3) NOT NULL,
    UnitPrice   DECIMAL(18,2) NOT NULL,
    Discount    DECIMAL(18,2) NOT NULL,
    Amount      DECIMAL(18,2) NOT NULL,
    LineDescrip NVARCHAR(50)  NULL,      -- only for ItemId 0 ("other item")
    Name        NVARCHAR(100) NULL
);
GO
-- abandoned bills the back office answered for, with the FinalStatus that was sent (zf_sp_MarkAbandonedBillsSynced)
CREATE TYPE dbo.zf_tt_AbandonSent AS TABLE (
    AbandonId   INT NOT NULL PRIMARY KEY,
    FinalStatus INT NULL
);
GO
-- Saves the bill on the screen (whole bill each time: header + every line). Returns one row: Saved, Status.
-- Saved 0 = not saved: the bill is already closed (Status <> 0, e.g. a save that arrived after Pay), or a newer save
-- (higher SaveSeq) is already stored.
CREATE PROCEDURE dbo.zf_sp_SaveDraftBill
    @DraftKey        UNIQUEIDENTIFIER,
    @SaveSeq         INT,
    @CashierId       VARCHAR(20) = NULL,
    @InvType         INT = 1,
    @PriceType       INT = 1,
    @Discount        DECIMAL(18,2) = 0,
    @DiscountPercent DECIMAL(5,2) = NULL,
    @PageState       NVARCHAR(MAX) = NULL,
    @Items           dbo.zf_tt_DraftItem READONLY
AS
BEGIN
    DECLARE @z_tc INT; SET @z_tc = @@TRANCOUNT;   -- SQL 2008 R2 error handling (RAISERROR in TRY/CATCH)
    BEGIN TRY
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Now DATETIME, @Status INT, @Seq INT, @Lines INT, @Net DECIMAL(18,2);
    IF NOT EXISTS (SELECT 1 FROM @Items)
        RAISERROR(N'%s', 16, 1, N'A draft bill needs at least one line - close it instead.');
    IF @InvType NOT IN (1, 2) OR @PriceType NOT IN (1, 2)
        RAISERROR(N'%s', 16, 1, N'InvType and PriceType must be 1 or 2.');

    SET @Now = GETDATE();
    SELECT @Lines = COUNT(*), @Net = ISNULL(SUM(Amount), 0) - ISNULL(@Discount, 0) FROM @Items;

    BEGIN TRAN;
        SELECT @Status = Status, @Seq = SaveSeq
        FROM dbo.zf_tb_DraftBill WITH (UPDLOCK, HOLDLOCK) WHERE DraftKey = @DraftKey;

        IF @Status IS NOT NULL AND (@Status <> 0 OR @Seq >= @SaveSeq)
        BEGIN
            COMMIT;
            SELECT CAST(0 AS BIT) AS Saved, @Status AS Status;
            RETURN 0;
        END

        IF @Status IS NULL
        BEGIN
            -- closed bills are kept 7 days (a late save can't open them again), then go
            DELETE FROM dbo.zf_tb_DraftBill WHERE Status <> 0 AND ClosedAt < DATEADD(DAY, -7, @Now);
            INSERT dbo.zf_tb_DraftBill (DraftKey, SaveSeq, Status, CashierId, InvType, PriceType, Discount, DiscountPercent,
                                        LineCount, NetAmount, PageState, StartedAt, SavedAt)
            VALUES (@DraftKey, @SaveSeq, 0, @CashierId, @InvType, @PriceType, ISNULL(@Discount, 0), @DiscountPercent,
                    @Lines, @Net, @PageState, @Now, @Now);
        END
        ELSE
        BEGIN
            UPDATE dbo.zf_tb_DraftBill
            SET SaveSeq = @SaveSeq, CashierId = @CashierId, InvType = @InvType, PriceType = @PriceType,
                Discount = ISNULL(@Discount, 0), DiscountPercent = @DiscountPercent, LineCount = @Lines, NetAmount = @Net,
                PageState = @PageState, SavedAt = @Now
            WHERE DraftKey = @DraftKey;
            DELETE FROM dbo.zf_tb_DraftBillItem WHERE DraftKey = @DraftKey;
        END

        INSERT dbo.zf_tb_DraftBillItem (DraftKey, LineNum, ItemId, PriceLinkId, PriceType, Qty, UnitPrice, Discount, Amount,
                                        LineDescrip, Name)
        SELECT @DraftKey, LineNum, ItemId, PriceLinkId, ISNULL(PriceType, @PriceType), Qty, UnitPrice, Discount, Amount,
               LEFT(LineDescrip, 50), LEFT(Name, 100)
        FROM @Items;
    COMMIT;

    SELECT CAST(1 AS BIT) AS Saved, 0 AS Status;
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
-- Ends the bill on the screen: @Status 1 paid (@InvoiceNo), 2 suspended (@SuspendId), 3 cleared. TillService calls it
-- in the same transaction as zf_sp_SaveInvoice / zf_sp_SuspendBill. A bill never saved as a draft gets a closed row
-- (so a save still on its way can't open it). An abandoned bill taken back gets its end (sent again).
CREATE PROCEDURE dbo.zf_sp_CloseDraftBill
    @DraftKey  UNIQUEIDENTIFIER,
    @Status    INT,
    @InvoiceNo VARCHAR(30) = NULL,
    @SuspendId INT = NULL
AS
BEGIN
    DECLARE @z_tc INT; SET @z_tc = @@TRANCOUNT;   -- SQL 2008 R2 error handling (RAISERROR in TRY/CATCH)
    BEGIN TRY
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Now DATETIME;
    IF @Status NOT IN (1, 2, 3)
        RAISERROR(N'%s', 16, 1, N'Draft Status must be 1 (paid), 2 (suspended) or 3 (cleared).');
    SET @Now = GETDATE();

    BEGIN TRAN;
        UPDATE dbo.zf_tb_DraftBill WITH (UPDLOCK, HOLDLOCK)
        SET Status = @Status, ClosedAt = @Now, InvoiceNo = @InvoiceNo, SuspendId = @SuspendId
        WHERE DraftKey = @DraftKey AND Status = 0;

        IF @@ROWCOUNT > 0
        BEGIN
            DELETE FROM dbo.zf_tb_DraftBillItem WHERE DraftKey = @DraftKey;
            UPDATE dbo.zf_tb_AbandonedBill
            SET FinalStatus = @Status, FinalAt = @Now, InvoiceNo = @InvoiceNo, SuspendId = @SuspendId, Synced = 0
            WHERE DraftKey = @DraftKey AND FinalStatus IS NULL;
        END
        ELSE IF NOT EXISTS (SELECT 1 FROM dbo.zf_tb_DraftBill WHERE DraftKey = @DraftKey)
            INSERT dbo.zf_tb_DraftBill (DraftKey, SaveSeq, Status, InvType, PriceType, Discount, LineCount, NetAmount,
                                        StartedAt, SavedAt, ClosedAt, InvoiceNo, SuspendId)
            VALUES (@DraftKey, 0, @Status, 1, 1, 0, 0, 0, @Now, @Now, @Now, @InvoiceNo, @SuspendId);
    COMMIT;
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
-- Bills left open on this till (the billing page asks when it starts), newest first. FirstItems = a short preview.
CREATE PROCEDURE dbo.zf_sp_GetOpenDraftBills
AS
BEGIN
    SET NOCOUNT ON;
    SELECT d.DraftKey, d.CashierId, d.InvType, d.PriceType, d.LineCount, d.NetAmount, d.StartedAt, d.SavedAt, d.Recovered,
           STUFF((SELECT TOP 3 N', ' + ISNULL(l.Name, ISNULL(l.LineDescrip, N'Item ' + CAST(l.ItemId AS NVARCHAR(10))))
                  FROM dbo.zf_tb_DraftBillItem l
                  WHERE l.DraftKey = d.DraftKey
                  ORDER BY l.LineNum
                  FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)'), 1, 2, N'') AS FirstItems
    FROM dbo.zf_tb_DraftBill d
    WHERE d.Status = 0 AND d.LineCount > 0
    ORDER BY d.SavedAt DESC;
END
GO
-- Copies an open draft into zf_tb_AbandonedBill (+ its lines) as it is now. Called by zf_sp_RecoverDraftBill and
-- zf_sp_DiscardDraftBill inside their transaction. Returns the new AbandonId in @AbandonId.
CREATE PROCEDURE dbo.zf_sp_LogAbandonedBill
    @DraftKey  UNIQUEIDENTIFIER,
    @FoundBy   VARCHAR(20) = NULL,
    @Outcome   INT,
    @Reason    NVARCHAR(100) = NULL,
    @AbandonId INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Now DATETIME, @ZNo INT;
    SET @Now = GETDATE();
    SELECT @ZNo = ZNo FROM dbo.zf_tb_ZReport WHERE Status = 0;

    INSERT dbo.zf_tb_AbandonedBill (DraftKey, ZNo, CashierId, InvType, LineCount, NetAmount, StartedAt, LastSavedAt,
                                    FoundAt, FoundBy, Outcome, Reason, FinalStatus, FinalAt)
    SELECT DraftKey, @ZNo, CashierId, InvType, LineCount, NetAmount, StartedAt, SavedAt,
           @Now, @FoundBy, @Outcome, LEFT(@Reason, 100),
           CASE WHEN @Outcome = 2 THEN 8 END, CASE WHEN @Outcome = 2 THEN @Now END
    FROM dbo.zf_tb_DraftBill WHERE DraftKey = @DraftKey;
    SET @AbandonId = SCOPE_IDENTITY();

    INSERT dbo.zf_tb_AbandonedBillItem (AbandonId, LineNum, ItemId, Descrip, Qty, UnitPrice, Discount, Amount)
    SELECT @AbandonId, LineNum, ItemId, ISNULL(Name, LineDescrip), Qty, UnitPrice, Discount, Amount
    FROM dbo.zf_tb_DraftBillItem WHERE DraftKey = @DraftKey;
END
GO
-- Takes a bill found open after a restart back to the screen: it is logged as abandoned (Outcome 1) and stays open
-- (same DraftKey, the page goes on saving it). 2 result sets like zf_sp_RecallSuspendedBill: the header (with
-- SaveSeq and PageState), then the lines with ItemFound / the item's current name.
CREATE PROCEDURE dbo.zf_sp_RecoverDraftBill
    @DraftKey  UNIQUEIDENTIFIER,
    @CashierId VARCHAR(20) = NULL
AS
BEGIN
    DECLARE @z_tc INT; SET @z_tc = @@TRANCOUNT;   -- SQL 2008 R2 error handling (RAISERROR in TRY/CATCH)
    BEGIN TRY
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @AbandonId INT;
    BEGIN TRAN;
        UPDATE dbo.zf_tb_DraftBill WITH (UPDLOCK, HOLDLOCK)
        SET Recovered = Recovered + 1
        WHERE DraftKey = @DraftKey AND Status = 0 AND LineCount > 0;
        IF @@ROWCOUNT = 0
            RAISERROR(N'%s', 16, 1, N'This bill is no longer open - it was already taken back, paid or thrown away.');

        EXEC dbo.zf_sp_LogAbandonedBill @DraftKey, @CashierId, 1, NULL, @AbandonId OUTPUT;
    COMMIT;

    SELECT DraftKey, SaveSeq, CashierId, InvType, PriceType, Discount, DiscountPercent, LineCount, NetAmount,
           StartedAt, SavedAt, PageState, @AbandonId AS AbandonId
    FROM dbo.zf_tb_DraftBill WHERE DraftKey = @DraftKey;

    SELECT l.LineNum, l.ItemId, l.PriceLinkId, l.PriceType, l.Qty, l.UnitPrice, l.Discount, l.Amount, l.LineDescrip,
           CAST(CASE WHEN l.ItemId = 0 OR i.Status = 1 THEN 1 ELSE 0 END AS BIT) AS ItemFound,
           ISNULL(l.Name, ISNULL(l.LineDescrip, ISNULL(i.Inv_Descrip, i.Descrip))) AS Name
    FROM dbo.zf_tb_DraftBillItem l
    LEFT JOIN dbo.zf_tb_Item i ON i.ItemId = l.ItemId AND l.ItemId <> 0
    WHERE l.DraftKey = @DraftKey
    ORDER BY l.LineNum;
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
-- Throws away a bill found open after a restart (supervisor PIN in TillService): logged as abandoned (Outcome 2,
-- FinalStatus 8) with the reason, the draft is closed (Status 8). Returns one row: AbandonId.
CREATE PROCEDURE dbo.zf_sp_DiscardDraftBill
    @DraftKey  UNIQUEIDENTIFIER,
    @CashierId VARCHAR(20) = NULL,
    @Reason    NVARCHAR(100) = NULL
AS
BEGIN
    DECLARE @z_tc INT; SET @z_tc = @@TRANCOUNT;   -- SQL 2008 R2 error handling (RAISERROR in TRY/CATCH)
    BEGIN TRY
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @AbandonId INT;
    BEGIN TRAN;
        IF NOT EXISTS (SELECT 1 FROM dbo.zf_tb_DraftBill WITH (UPDLOCK, HOLDLOCK) WHERE DraftKey = @DraftKey AND Status = 0)
            RAISERROR(N'%s', 16, 1, N'This bill is no longer open - it was already taken back, paid or thrown away.');

        EXEC dbo.zf_sp_LogAbandonedBill @DraftKey, @CashierId, 2, @Reason, @AbandonId OUTPUT;

        UPDATE dbo.zf_tb_DraftBill SET Status = 8, ClosedAt = GETDATE() WHERE DraftKey = @DraftKey;
        DELETE FROM dbo.zf_tb_DraftBillItem WHERE DraftKey = @DraftKey;
    COMMIT;

    SELECT @AbandonId AS AbandonId;
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
-- Oldest abandoned bills not sent yet (POST api/Sync/AbandonedBills). 2 result sets: the bills, then their lines.
CREATE PROCEDURE dbo.zf_sp_GetUnsyncedAbandonedBills
    @Top INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Ids TABLE (AbandonId INT NOT NULL PRIMARY KEY);
    INSERT @Ids (AbandonId)
    SELECT TOP (@Top) AbandonId FROM dbo.zf_tb_AbandonedBill WHERE Synced = 0 ORDER BY AbandonId;

    SELECT a.AbandonId, a.DraftKey, a.ZNo, a.CashierId, a.InvType, a.LineCount, a.NetAmount, a.StartedAt, a.LastSavedAt,
           a.FoundAt, a.FoundBy, a.Outcome, a.Reason, a.FinalStatus, a.FinalAt, a.InvoiceNo, a.SuspendId
    FROM dbo.zf_tb_AbandonedBill a JOIN @Ids i ON i.AbandonId = a.AbandonId
    ORDER BY a.AbandonId;

    SELECT l.AbandonId, l.LineNum, l.ItemId, l.Descrip, l.Qty, l.UnitPrice, l.Discount, l.Amount
    FROM dbo.zf_tb_AbandonedBillItem l JOIN @Ids i ON i.AbandonId = l.AbandonId
    ORDER BY l.AbandonId, l.LineNum;
END
GO
-- A row whose FinalStatus changed while it was on its way (the bill was paid meanwhile) stays unsent and goes again.
CREATE PROCEDURE dbo.zf_sp_MarkAbandonedBillsSynced
    @Rows dbo.zf_tt_AbandonSent READONLY
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE a SET Synced = 1, SyncedAt = GETDATE()
    FROM dbo.zf_tb_AbandonedBill a
    JOIN @Rows r ON r.AbandonId = a.AbandonId AND ISNULL(r.FinalStatus, -1) = ISNULL(a.FinalStatus, -1);
END
GO
SET NOEXEC OFF;
GO
PRINT 'U022_Till_DraftBill done.';
GO
