/* =============================================================================
   37_BackOffice_Wallet.sql
   Run on: back office db (easyway). Prefix z_. Re-runnable. SQL Server 2008 R2 and newer.
   Needs 27_BackOffice_Loyalty.sql (the members). Same as Updates/U059_BackOffice_Wallet.sql.
   Customer wallet (its own function, separate from loyalty points; it only uses the loyalty members, by phone):
     - change kept on a bill goes into the member's wallet; the wallet pays part of a later bill; it may go below 0
       down to Wallet.MinusLimit. Wallet money is NEVER paid out as cash - only taken off a bill.
     - on the bill: ONE payment PayType 9 (WALLET), signed: + paid from the wallet, - change kept. The cash payment is
       the cash in the drawer, so Z / day end / reports need no change (the wallet is in "other").
     - the back office keeps the only balance (z_tb_LoyaltyMember.WalletBalance, history z_tb_WalletTxn); the till
       asks it BEFORE saving the bill (api/Wallet/Bill), gives it back if the bill is not saved (api/Wallet/Cancel),
       and links it to the bill when the bill goes up (api/Wallet/Bills; a voided bill gives it back).
     - settings group Wallet (System Settings): Wallet.Enabled (default off), Wallet.MaxKeep, Wallet.MaxBalance,
       Wallet.MinusLimit.
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
IF OBJECT_ID(N'dbo.z_tb_LoyaltyMember', 'U') IS NULL OR OBJECT_ID(N'dbo.z_tb_Setting', 'U') IS NULL
BEGIN
    RAISERROR('This back office database has no loyalty members (run U038 first) - nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
GO

-- 1. tables ------------------------------------------------------------------
-- the wallet balance of a member: + = the shop holds the customer's money, - = the customer owes the shop
IF COL_LENGTH('dbo.z_tb_LoyaltyMember', 'WalletBalance') IS NULL
    ALTER TABLE dbo.z_tb_LoyaltyMember ADD WalletBalance DECIMAL(18,2) NOT NULL
        CONSTRAINT DF_z_tb_LoyaltyMember_WalletBalance DEFAULT (0);
GO

IF OBJECT_ID(N'dbo.z_tb_WalletTxn', 'U') IS NULL
CREATE TABLE dbo.z_tb_WalletTxn (
    TxnId        INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_z_tb_WalletTxn PRIMARY KEY,
    MemberId     INT              NOT NULL,
    TxnType      INT              NOT NULL,   -- 1 on a bill (change kept / paid from the wallet), 3 given back (bill not saved / voided)
    Amount       DECIMAL(18,2)    NOT NULL,   -- the balance change: + change kept, - paid from the wallet (3: the opposite of its 1)
    BalanceAfter DECIMAL(18,2)    NOT NULL,
    TerminalId   INT              NULL,
    InvoiceNo    VARCHAR(30)      NULL,       -- filled when the bill comes up
    WalletKey    UNIQUEIDENTIFIER NOT NULL,   -- the till's key of the bill's wallet part
    CashierId    VARCHAR(20)      NULL,
    Remark       NVARCHAR(200)    NULL,
    TxnAt        DATETIME         NOT NULL CONSTRAINT DF_z_tb_WalletTxn_TxnAt DEFAULT (GETDATE()),
    CONSTRAINT FK_z_tb_WalletTxn_Member FOREIGN KEY (MemberId) REFERENCES dbo.z_tb_LoyaltyMember (MemberId)
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_z_tb_WalletTxn_Member')
    CREATE INDEX IX_z_tb_WalletTxn_Member ON dbo.z_tb_WalletTxn (MemberId, TxnId);
-- one bill txn and one give back per key (a retry / resend changes nothing)
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_z_tb_WalletTxn_Key')
    CREATE UNIQUE INDEX UX_z_tb_WalletTxn_Key ON dbo.z_tb_WalletTxn (WalletKey, TxnType);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_z_tb_WalletTxn_TxnAt')
    CREATE INDEX IX_z_tb_WalletTxn_TxnAt ON dbo.z_tb_WalletTxn (TxnAt);
GO

-- 2. settings (label, help, default set again on every run; the values are kept) -------------------------------
DECLARE @s TABLE (SettingKey VARCHAR(50), GroupName NVARCHAR(30), Label NVARCHAR(100), Descrip NVARCHAR(400), Scope INT,
                  ValueType VARCHAR(10), Options NVARCHAR(400), DefaultValue NVARCHAR(200), SortOrder INT);
INSERT @s VALUES
 ('Wallet.Enabled', N'Wallet', N'Customer wallet',
  N'On: with a loyalty member on the bill, change can be kept in the member''s wallet and the wallet can pay part of a bill. Wallet money is never paid out as cash. Off: every bill is a normal bill (separate from loyalty points).',
  1, 'bool', NULL, N'0', 200),
 ('Wallet.MaxKeep', N'Wallet', N'Most change kept per bill (Rs)',
  N'The most change one bill can put in the wallet, e.g. 50. 0 = change can''t be kept.',
  1, 'number', NULL, N'50', 210),
 ('Wallet.MaxBalance', N'Wallet', N'Most a wallet can hold (Rs)',
  N'Change is not kept when the wallet would hold more than this, e.g. 1000. 0 = no limit.',
  1, 'number', NULL, N'1000', 220),
 ('Wallet.MinusLimit', N'Wallet', N'Wallet may go below 0 by (Rs)',
  N'The customer is short: the wallet pays it and goes below 0, at most this much (they pay it back next time by keeping change). 0 = never below 0.',
  1, 'number', NULL, N'0', 230);

UPDATE t SET GroupName = s.GroupName, Label = s.Label, Descrip = s.Descrip, Scope = s.Scope, ValueType = s.ValueType,
             Options = s.Options, DefaultValue = s.DefaultValue, SortOrder = s.SortOrder
FROM dbo.z_tb_Setting t JOIN @s s ON s.SettingKey = t.SettingKey;

INSERT dbo.z_tb_Setting (SettingKey, GroupName, Label, Descrip, Scope, ValueType, Options, DefaultValue, SortOrder)
SELECT SettingKey, GroupName, Label, Descrip, Scope, ValueType, Options, DefaultValue, SortOrder
FROM @s s WHERE NOT EXISTS (SELECT 1 FROM dbo.z_tb_Setting t WHERE t.SettingKey = s.SettingKey);
GO

-- 3. procedures --------------------------------------------------------------
IF OBJECT_ID(N'dbo.z_sp_WalletSettings', 'P')   IS NOT NULL DROP PROCEDURE dbo.z_sp_WalletSettings;
IF OBJECT_ID(N'dbo.z_sp_WalletGetMember', 'P')  IS NOT NULL DROP PROCEDURE dbo.z_sp_WalletGetMember;
IF OBJECT_ID(N'dbo.z_sp_WalletBill', 'P')       IS NOT NULL DROP PROCEDURE dbo.z_sp_WalletBill;
IF OBJECT_ID(N'dbo.z_sp_WalletCancel', 'P')     IS NOT NULL DROP PROCEDURE dbo.z_sp_WalletCancel;
IF OBJECT_ID(N'dbo.z_sp_WalletSyncBills', 'P')  IS NOT NULL DROP PROCEDURE dbo.z_sp_WalletSyncBills;
IF OBJECT_ID(N'dbo.z_sp_WalletMembers', 'P')    IS NOT NULL DROP PROCEDURE dbo.z_sp_WalletMembers;
IF OBJECT_ID(N'dbo.z_sp_WalletMemberTxns', 'P') IS NOT NULL DROP PROCEDURE dbo.z_sp_WalletMemberTxns;
IF TYPE_ID(N'dbo.z_tt_WalletBill') IS NOT NULL DROP TYPE dbo.z_tt_WalletBill;
GO
-- a bill with a wallet part, as the till saved it (api/Wallet/Bills)
CREATE TYPE dbo.z_tt_WalletBill AS TABLE (
    InvoiceNo VARCHAR(30)      NOT NULL PRIMARY KEY,
    WalletKey UNIQUEIDENTIFIER NOT NULL,
    Status    INT              NOT NULL    -- the bill's: 1 completed, 9 voided
);
GO

-- the wallet settings as numbers
CREATE PROCEDURE dbo.z_sp_WalletSettings
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @v TABLE (SettingKey VARCHAR(50) PRIMARY KEY, Value NVARCHAR(200));
    INSERT @v SELECT SettingKey, COALESCE(Value, DefaultValue) FROM dbo.z_tb_Setting WHERE SettingKey LIKE 'Wallet.%';
    SELECT CAST(CASE WHEN (SELECT Value FROM @v WHERE SettingKey = 'Wallet.Enabled') = N'1' THEN 1 ELSE 0 END AS BIT) AS Enabled,
           CAST(ISNULL((SELECT Value FROM @v WHERE SettingKey = 'Wallet.MaxKeep'), N'0') AS DECIMAL(18,2)) AS MaxKeep,
           CAST(ISNULL((SELECT Value FROM @v WHERE SettingKey = 'Wallet.MaxBalance'), N'0') AS DECIMAL(18,2)) AS MaxBalance,
           CAST(ISNULL((SELECT Value FROM @v WHERE SettingKey = 'Wallet.MinusLimit'), N'0') AS DECIMAL(18,2)) AS MinusLimit;
END
GO

-- the wallet of one member by phone (no row = not a member)
CREATE PROCEDURE dbo.z_sp_WalletGetMember
    @Phone VARCHAR(15)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT MemberId, Phone, Name, Status, WalletBalance FROM dbo.z_tb_LoyaltyMember WHERE Phone = @Phone;
END
GO

-- The wallet part of a bill, done NOW, before the till saves the bill. @Amount = the bill's WALLET payment (PayType 9):
-- + paid from the wallet (balance down, at most to -Wallet.MinusLimit), - change kept (balance up, at most
-- Wallet.MaxKeep per bill and Wallet.MaxBalance in all). The same key again changes nothing (a retry).
-- -> the member: WalletBalance after it, BalanceBefore
CREATE PROCEDURE dbo.z_sp_WalletBill
    @WalletKey  UNIQUEIDENTIFIER,
    @Phone      VARCHAR(15),
    @Amount     DECIMAL(18,2),
    @TerminalId INT,
    @CashierId  VARCHAR(20) = NULL
AS
BEGIN
    DECLARE @z_tc INT; SET @z_tc = @@TRANCOUNT;   -- SQL 2008 R2 error handling (RAISERROR in TRY/CATCH)
    BEGIN TRY
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @Enabled BIT, @MaxKeep DECIMAL(18,2), @MaxBalance DECIMAL(18,2), @MinusLimit DECIMAL(18,2),
            @MemberId INT, @Status INT, @Balance DECIMAL(18,2), @New DECIMAL(18,2), @Done DECIMAL(18,2), @Msg NVARCHAR(300);
    -- the settings as z_sp_WalletSettings (read here: no INSERT ... EXEC, so a caller may capture this proc's answer)
    SELECT @Enabled = 0, @MaxKeep = 0, @MaxBalance = 0, @MinusLimit = 0;
    SELECT @Enabled = CASE WHEN COALESCE(Value, DefaultValue) = N'1' THEN 1 ELSE 0 END FROM dbo.z_tb_Setting WHERE SettingKey = 'Wallet.Enabled';
    SELECT @MaxKeep = CAST(ISNULL(COALESCE(Value, DefaultValue), N'0') AS DECIMAL(18,2)) FROM dbo.z_tb_Setting WHERE SettingKey = 'Wallet.MaxKeep';
    SELECT @MaxBalance = CAST(ISNULL(COALESCE(Value, DefaultValue), N'0') AS DECIMAL(18,2)) FROM dbo.z_tb_Setting WHERE SettingKey = 'Wallet.MaxBalance';
    SELECT @MinusLimit = CAST(ISNULL(COALESCE(Value, DefaultValue), N'0') AS DECIMAL(18,2)) FROM dbo.z_tb_Setting WHERE SettingKey = 'Wallet.MinusLimit';

    BEGIN TRAN;
        SELECT @MemberId = MemberId, @Status = Status, @Balance = WalletBalance
        FROM dbo.z_tb_LoyaltyMember WITH (UPDLOCK, HOLDLOCK) WHERE Phone = @Phone;
        IF @MemberId IS NULL
            RAISERROR(N'%s', 16, 1, N'This phone number is not a member.');

        -- a retry of a key already done: its answer again (even if the settings changed since)
        SELECT @Done = Amount FROM dbo.z_tb_WalletTxn WHERE WalletKey = @WalletKey AND TxnType = 1;
        IF @Done IS NULL
        BEGIN
            IF @Enabled = 0
                RAISERROR(N'%s', 16, 1, N'The customer wallet is switched off on the back office.');
            IF ISNULL(@Amount, 0) = 0
                RAISERROR(N'%s', 16, 1, N'Enter the wallet amount.');
            IF @Status <> 1
                RAISERROR(N'%s', 16, 1, N'This member is blocked on the back office - the wallet can''t be used.');

            SET @New = @Balance - @Amount;
            IF @Amount < 0 AND -@Amount > @MaxKeep
            BEGIN
                SET @Msg = CASE WHEN @MaxKeep <= 0 THEN N'Keeping change in the wallet is off (back office).'
                                ELSE N'At most Rs ' + CONVERT(NVARCHAR(20), @MaxKeep) + N' change can go to the wallet on one bill.' END;
                RAISERROR(N'%s', 16, 1, @Msg);
            END
            IF @Amount < 0 AND @MaxBalance > 0 AND @New > @MaxBalance
            BEGIN
                SET @Msg = N'The wallet can hold at most Rs ' + CONVERT(NVARCHAR(20), @MaxBalance) + N' - it has Rs '
                         + CONVERT(NVARCHAR(20), @Balance) + N'.';
                RAISERROR(N'%s', 16, 1, @Msg);
            END
            IF @Amount > 0 AND @New < -@MinusLimit
            BEGIN
                SET @Msg = CASE WHEN @MinusLimit <= 0
                                THEN N'The wallet has only Rs ' + CONVERT(NVARCHAR(20), @Balance) + N'.'
                                ELSE N'The wallet has Rs ' + CONVERT(NVARCHAR(20), @Balance) + N' and may go below 0 by Rs '
                                     + CONVERT(NVARCHAR(20), @MinusLimit) + N' at most.' END;
                RAISERROR(N'%s', 16, 1, @Msg);
            END

            UPDATE dbo.z_tb_LoyaltyMember SET WalletBalance = @New WHERE MemberId = @MemberId;
            INSERT dbo.z_tb_WalletTxn (MemberId, TxnType, Amount, BalanceAfter, TerminalId, WalletKey, CashierId)
            VALUES (@MemberId, 1, -@Amount, @New, @TerminalId, @WalletKey, @CashierId);
            SET @Done = -@Amount;
        END
    COMMIT;

    SELECT m.MemberId, m.Phone, m.Name, m.Status, m.WalletBalance, t.BalanceAfter - t.Amount AS BalanceBefore
    FROM dbo.z_tb_LoyaltyMember m
    JOIN dbo.z_tb_WalletTxn t ON t.WalletKey = @WalletKey AND t.TxnType = 1
    WHERE m.MemberId = @MemberId;
    END TRY
    BEGIN CATCH
        DECLARE @z_msg NVARCHAR(2048); SET @z_msg = ERROR_MESSAGE();
        IF @z_tc = 0 AND XACT_STATE() <> 0 ROLLBACK;
        RAISERROR(N'%s', 16, 1, @z_msg);
        RETURN 1;
    END CATCH
END
GO

-- The bill the wallet part was for was not saved (or was voided): the balance goes back. Only a txn not yet on a
-- bill unless @AnyState = 1; the same key again changes nothing. Never refused for the limits.
-- -> Returned 1 / 0 (nothing with @Quiet = 1: called from z_sp_WalletSyncBills)
CREATE PROCEDURE dbo.z_sp_WalletCancel
    @WalletKey UNIQUEIDENTIFIER,
    @Remark    NVARCHAR(200) = NULL,
    @AnyState  BIT = 0,
    @Quiet     BIT = 0
AS
BEGIN
    DECLARE @z_tc INT; SET @z_tc = @@TRANCOUNT;
    BEGIN TRY
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @MemberId INT, @Amount DECIMAL(18,2), @Balance DECIMAL(18,2), @TerminalId INT, @InvoiceNo VARCHAR(30), @Done BIT;
    SET @Done = 0;
    BEGIN TRAN;
        SELECT @MemberId = t.MemberId, @Amount = t.Amount, @TerminalId = t.TerminalId, @InvoiceNo = t.InvoiceNo
        FROM dbo.z_tb_WalletTxn t WITH (UPDLOCK, HOLDLOCK)
        WHERE t.WalletKey = @WalletKey AND t.TxnType = 1;

        IF @MemberId IS NOT NULL AND (@InvoiceNo IS NULL OR @AnyState = 1)
           AND NOT EXISTS (SELECT 1 FROM dbo.z_tb_WalletTxn WHERE WalletKey = @WalletKey AND TxnType = 3)
        BEGIN
            UPDATE dbo.z_tb_LoyaltyMember WITH (UPDLOCK)
            SET @Balance = WalletBalance = WalletBalance - @Amount
            WHERE MemberId = @MemberId;
            INSERT dbo.z_tb_WalletTxn (MemberId, TxnType, Amount, BalanceAfter, TerminalId, InvoiceNo, WalletKey, Remark)
            VALUES (@MemberId, 3, -@Amount, @Balance, @TerminalId, @InvoiceNo, @WalletKey,
                    ISNULL(@Remark, N'Bill not saved - wallet given back'));
            SET @Done = 1;
        END
    COMMIT;
    IF @Quiet = 0
        SELECT @Done AS Returned;
    END TRY
    BEGIN CATCH
        DECLARE @z_msg NVARCHAR(2048); SET @z_msg = ERROR_MESSAGE();
        IF @z_tc = 0 AND XACT_STATE() <> 0 ROLLBACK;
        RAISERROR(N'%s', 16, 1, @z_msg);
        RETURN 1;
    END CATCH
END
GO

-- Bills with a wallet part, uploaded by a till: the txn is linked to its bill; a voided bill gives it back.
-- A resend changes nothing. -> the InvoiceNo of every row (all are done)
CREATE PROCEDURE dbo.z_sp_WalletSyncBills
    @TerminalId INT,
    @Bills      dbo.z_tt_WalletBill READONLY
AS
BEGIN
    DECLARE @z_tc INT; SET @z_tc = @@TRANCOUNT;
    BEGIN TRY
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @No VARCHAR(30), @Key UNIQUEIDENTIFIER, @Status INT;

    DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT InvoiceNo, WalletKey, Status FROM @Bills ORDER BY InvoiceNo;
    OPEN c;
    FETCH NEXT FROM c INTO @No, @Key, @Status;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        BEGIN TRAN;
            UPDATE dbo.z_tb_WalletTxn SET InvoiceNo = @No
            WHERE WalletKey = @Key AND TxnType IN (1, 3) AND InvoiceNo IS NULL;
            IF @Status = 9
                EXEC dbo.z_sp_WalletCancel @WalletKey = @Key, @Remark = N'Bill voided - wallet given back', @AnyState = 1, @Quiet = 1;
        COMMIT;
        FETCH NEXT FROM c INTO @No, @Key, @Status;
    END
    CLOSE c;
    DEALLOCATE c;

    SELECT InvoiceNo FROM @Bills;
    END TRY
    BEGIN CATCH
        DECLARE @z_msg NVARCHAR(2048); SET @z_msg = ERROR_MESSAGE();
        IF @z_tc = 0 AND XACT_STATE() <> 0 ROLLBACK;
        IF CURSOR_STATUS('local', 'c') >= -1
        BEGIN
            IF CURSOR_STATUS('local', 'c') >= 0 CLOSE c;
            DEALLOCATE c;
        END
        RAISERROR(N'%s', 16, 1, @z_msg);
        RETURN 1;
    END CATCH
END
GO

-- Wallet tab (Loyalty page): members by phone or name; @NonZero = 1 only wallets not at 0. Then the totals.
CREATE PROCEDURE dbo.z_sp_WalletMembers
    @Text    NVARCHAR(100) = NULL,
    @NonZero BIT = 1,
    @Top     INT = 200
AS
BEGIN
    SET NOCOUNT ON;
    SET @Text = NULLIF(LTRIM(RTRIM(@Text)), N'');
    SELECT TOP (@Top) m.MemberId, m.Phone, m.Name, m.Status, m.WalletBalance,
           (SELECT MAX(t.TxnAt) FROM dbo.z_tb_WalletTxn t WHERE t.MemberId = m.MemberId) AS LastTxnAt
    FROM dbo.z_tb_LoyaltyMember m
    WHERE (@NonZero = 0 OR m.WalletBalance <> 0)
      AND (@Text IS NULL OR m.Phone LIKE '%' + @Text + '%' OR m.Name LIKE N'%' + @Text + N'%')
    ORDER BY ABS(m.WalletBalance) DESC, m.MemberId DESC;

    SELECT ISNULL(SUM(CASE WHEN WalletBalance > 0 THEN WalletBalance ELSE 0 END), 0) AS HeldForCustomers,
           ISNULL(SUM(CASE WHEN WalletBalance < 0 THEN -WalletBalance ELSE 0 END), 0) AS OwedByCustomers,
           SUM(CASE WHEN WalletBalance <> 0 THEN 1 ELSE 0 END) AS Wallets
    FROM dbo.z_tb_LoyaltyMember;
END
GO

-- a member's wallet history, newest first
CREATE PROCEDURE dbo.z_sp_WalletMemberTxns
    @MemberId INT,
    @Top      INT = 500
AS
BEGIN
    SET NOCOUNT ON;
    SELECT TOP (@Top) t.TxnId, t.TxnType, t.Amount, t.BalanceAfter, t.TerminalId, tm.TerminalCode, t.InvoiceNo, t.CashierId,
           t.Remark, t.TxnAt
    FROM dbo.z_tb_WalletTxn t
    LEFT JOIN dbo.z_tb_Terminal tm ON tm.TerminalId = t.TerminalId
    WHERE t.MemberId = @MemberId
    ORDER BY t.TxnId DESC;
END
GO

SET NOEXEC OFF;
GO
PRINT 'U059 done: customer wallet (z_tb_LoyaltyMember.WalletBalance, z_tb_WalletTxn, Wallet.* settings - off, z_sp_Wallet*).';
GO
