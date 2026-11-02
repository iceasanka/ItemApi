/* =============================================================================
   27_BackOffice_Loyalty.sql
   Run on: back office db (easyway). Prefix z_. Re-runnable. SQL Server 2008 R2 and newer.
   Customer loyalty points (Docs/StockSystem.md 6.33). API: api/Loyalty (LoyaltyController).

   - A member = a phone number + a name, registered on a till (Menu > Add loyalty member) or on the back office
     Loyalty page. The back office keeps the only balance: z_tb_LoyaltyMember.Points.
   - Earn: a bill with a member's phone earns FLOOR(amount paid with money / Loyalty.EarnAmount) points. The till
     works the points out, the bill goes up with api/Loyalty/Bills (TxnType 1). A refund with the member takes the
     points of the refund back (TxnType 4, never below 0).
   - Redeem (never paid out as cash), only when the balance has reached Loyalty.MinRedeem. Loyalty.RedeemMode 1: points
     pay part or all of a bill, 1 point = Loyalty.PointValue rupees. 2: Loyalty.DiscountPoints points give
     Loyalty.DiscountPercent % off the bill (after its other discounts), one step per bill. Either way the till puts
     the rupees on the bill as a POINTS payment. The till takes the points off HERE before it saves the bill
     (api/Loyalty/Redeem, TxnType 2, key RedeemKey) - two tills can't spend the same points; if the bill is not saved
     the till gives them back (api/Loyalty/RedeemCancel, TxnType 3). The bill upload links the redeem to the bill.
   - Settings (Loyalty group, sent to the tills like the other settings): Loyalty.Enabled (off = normal bills),
     Loyalty.EarnAmount, Loyalty.RedeemMode, Loyalty.PointValue, Loyalty.DiscountPoints, Loyalty.DiscountPercent,
     Loyalty.MinRedeem, Loyalty.PrintPoints.
   - Hand changes on the Loyalty page: TxnType 5 (adjust, with a remark).
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
IF OBJECT_ID(N'dbo.z_tb_Setting', 'U') IS NULL OR OBJECT_ID(N'dbo.z_tb_Terminal', 'U') IS NULL
BEGIN
    RAISERROR('This is not a back office database with the settings (U023) - z_tb_Setting / z_tb_Terminal not found. Nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
GO

-- 1. tables ------------------------------------------------------------------
IF OBJECT_ID(N'dbo.z_tb_LoyaltyMember', 'U') IS NULL
CREATE TABLE dbo.z_tb_LoyaltyMember (
    MemberId          INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_z_tb_LoyaltyMember PRIMARY KEY,
    Phone             VARCHAR(15)   NOT NULL,   -- digits only, e.g. 0771234567 (the member's key at the till)
    Name              NVARCHAR(100) NOT NULL,
    Points            INT           NOT NULL CONSTRAINT DF_z_tb_LoyaltyMember_Points DEFAULT (0),   -- balance now
    TotalEarned       INT           NOT NULL CONSTRAINT DF_z_tb_LoyaltyMember_Earned DEFAULT (0),
    TotalRedeemed     INT           NOT NULL CONSTRAINT DF_z_tb_LoyaltyMember_Redeemed DEFAULT (0),
    Status            INT           NOT NULL CONSTRAINT DF_z_tb_LoyaltyMember_Status DEFAULT (1),   -- 1 active, 0 blocked
    LastBillAt        DATETIME      NULL,
    CreatedAt         DATETIME      NOT NULL CONSTRAINT DF_z_tb_LoyaltyMember_CreatedAt DEFAULT (GETDATE()),
    CreatedTerminalId INT           NULL,       -- NULL = made on the back office
    CreatedBy         VARCHAR(50)   NULL,       -- till cashier id, or back office user id
    UpdatedAt         DATETIME      NULL,
    UpdatedBy         INT           NULL,
    CONSTRAINT UQ_z_tb_LoyaltyMember_Phone UNIQUE (Phone)
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_z_tb_LoyaltyMember_Name')
    CREATE INDEX IX_z_tb_LoyaltyMember_Name ON dbo.z_tb_LoyaltyMember (Name);
GO

IF OBJECT_ID(N'dbo.z_tb_LoyaltyTxn', 'U') IS NULL
CREATE TABLE dbo.z_tb_LoyaltyTxn (
    TxnId        INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_z_tb_LoyaltyTxn PRIMARY KEY,
    MemberId     INT              NOT NULL,
    TxnType      INT              NOT NULL,   -- 1 earned (bill), 2 redeemed (paid a bill), 3 redeem given back (bill not saved / voided),
                                              -- 4 taken back (refund), 5 changed by hand (Loyalty page)
    Points       INT              NOT NULL,   -- + added, - taken off
    BalanceAfter INT              NOT NULL,
    TerminalId   INT              NULL,
    InvoiceNo    VARCHAR(30)      NULL,       -- the bill (redeem: filled when the bill comes up)
    BillAmount   DECIMAL(18,2)    NULL,       -- earned / refund: the amount the points were worked out on; redeem: rupees paid
    RedeemKey    UNIQUEIDENTIFIER NULL,       -- redeem and its give back
    CashierId    VARCHAR(20)      NULL,
    UserId       INT              NULL,       -- back office user (TxnType 5)
    Remark       NVARCHAR(200)    NULL,
    TxnAt        DATETIME         NOT NULL CONSTRAINT DF_z_tb_LoyaltyTxn_TxnAt DEFAULT (GETDATE()),
    CONSTRAINT FK_z_tb_LoyaltyTxn_Member FOREIGN KEY (MemberId) REFERENCES dbo.z_tb_LoyaltyMember (MemberId)
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_z_tb_LoyaltyTxn_Member')
    CREATE INDEX IX_z_tb_LoyaltyTxn_Member ON dbo.z_tb_LoyaltyTxn (MemberId, TxnId);
GO
-- one redeem per key, one give back per key, one earn / take back per bill (a resend changes nothing)
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_z_tb_LoyaltyTxn_Redeem')
    CREATE UNIQUE INDEX UX_z_tb_LoyaltyTxn_Redeem ON dbo.z_tb_LoyaltyTxn (RedeemKey, TxnType) WHERE RedeemKey IS NOT NULL;
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_z_tb_LoyaltyTxn_Bill')
    CREATE UNIQUE INDEX UX_z_tb_LoyaltyTxn_Bill ON dbo.z_tb_LoyaltyTxn (InvoiceNo, TxnType) WHERE InvoiceNo IS NOT NULL AND TxnType IN (1, 4);
GO

-- 2. settings (label, help, default set again on every run; the values are kept) -------------------------------
-- 'number': digits with at most one '.', 0 or more (z_fn_SettingValueOk)
DECLARE @s TABLE (SettingKey VARCHAR(50), GroupName NVARCHAR(30), Label NVARCHAR(100), Descrip NVARCHAR(400), Scope INT,
                  ValueType VARCHAR(10), Options NVARCHAR(400), DefaultValue NVARCHAR(200), SortOrder INT);
INSERT @s VALUES
 ('Loyalty.Enabled', N'Loyalty', N'Loyalty points',
  N'On: the cashier can put a member (phone number) on a bill - the bill earns points, and points can pay a bill. Off: every bill is a normal bill.',
  1, 'bool', NULL, N'0', 100),
 ('Loyalty.EarnAmount', N'Loyalty', N'Rupees for 1 point',
  N'1 point for every this many rupees of the bill after discounts (the part paid with points earns nothing). E.g. 100: a Rs 5,050 bill earns 50 points.',
  1, 'number', NULL, N'100', 110),
 ('Loyalty.RedeemMode', N'Loyalty', N'How points are used',
  N'Pay with points: points pay part or all of the bill (1 point = the value below). Discount: a set number of points gives a % off the bill (one step per bill). Points are never paid out as cash.',
  1, 'choice', N'1=Pay with points|2=Discount % for points', N'1', 115),
 ('Loyalty.PointValue', N'Loyalty', N'Value of 1 point (Rs)',
  N'Pay with points: what 1 point pays on a bill, in rupees.',
  1, 'number', NULL, N'1', 120),
 ('Loyalty.DiscountPoints', N'Loyalty', N'Discount: points used',
  N'Discount: the points one discount uses, e.g. 100.',
  1, 'number', NULL, N'100', 122),
 ('Loyalty.DiscountPercent', N'Loyalty', N'Discount: % off the bill',
  N'Discount: the % off the bill (after the other discounts) for those points, e.g. 5. One discount per bill.',
  1, 'number', NULL, N'5', 124),
 ('Loyalty.MinRedeem', N'Loyalty', N'Points needed before redeeming',
  N'A member can use points only when the balance has reached this many points (0 = any time).',
  1, 'number', NULL, N'1000', 130),
 ('Loyalty.PrintPoints', N'Loyalty', N'Print points on the bill',
  N'On: the bill shows the member, the points earned / used and the balance. Off: no points on the bill (a part paid with points still shows as POINTS).',
  1, 'bool', NULL, N'0', 140);

UPDATE t SET GroupName = s.GroupName, Label = s.Label, Descrip = s.Descrip, Scope = s.Scope, ValueType = s.ValueType,
             Options = s.Options, DefaultValue = s.DefaultValue, SortOrder = s.SortOrder
FROM dbo.z_tb_Setting t JOIN @s s ON s.SettingKey = t.SettingKey;

INSERT dbo.z_tb_Setting (SettingKey, GroupName, Label, Descrip, Scope, ValueType, Options, DefaultValue, SortOrder)
SELECT SettingKey, GroupName, Label, Descrip, Scope, ValueType, Options, DefaultValue, SortOrder
FROM @s s WHERE NOT EXISTS (SELECT 1 FROM dbo.z_tb_Setting t WHERE t.SettingKey = s.SettingKey);
GO

-- 1 when @Value is allowed for the setting: bool '0' / '1', choice one of its Options, number 0 or more
ALTER FUNCTION dbo.z_fn_SettingValueOk (@SettingKey VARCHAR(50), @Value NVARCHAR(200))
RETURNS BIT
AS
BEGIN
    DECLARE @ok BIT; SET @ok = 0;
    SELECT @ok = CASE WHEN ValueType = 'bool' AND @Value IN (N'0', N'1') THEN 1
                      WHEN ValueType = 'choice' AND @Value <> N'' AND CHARINDEX(N'|' + @Value + N'=', N'|' + ISNULL(Options, N'')) > 0 THEN 1
                      WHEN ValueType = 'number' AND @Value LIKE N'%[0-9]%' AND @Value NOT LIKE N'%[^0-9.]%'
                           AND LEN(@Value) - LEN(REPLACE(@Value, N'.', N'')) <= 1 AND LEN(@Value) <= 12
                           AND LEFT(@Value, 1) <> N'.' AND RIGHT(@Value, 1) <> N'.' THEN 1
                      ELSE 0 END
    FROM dbo.z_tb_Setting WHERE SettingKey = @SettingKey;
    RETURN @ok;
END
GO

-- 3. procedures --------------------------------------------------------------
IF OBJECT_ID(N'dbo.z_sp_LoyaltySettings', 'P')     IS NOT NULL DROP PROCEDURE dbo.z_sp_LoyaltySettings;
IF OBJECT_ID(N'dbo.z_sp_LoyaltyGetMember', 'P')    IS NOT NULL DROP PROCEDURE dbo.z_sp_LoyaltyGetMember;
IF OBJECT_ID(N'dbo.z_sp_LoyaltyAddMember', 'P')    IS NOT NULL DROP PROCEDURE dbo.z_sp_LoyaltyAddMember;
IF OBJECT_ID(N'dbo.z_sp_LoyaltyRedeem', 'P')       IS NOT NULL DROP PROCEDURE dbo.z_sp_LoyaltyRedeem;
IF OBJECT_ID(N'dbo.z_sp_LoyaltyRedeemCancel', 'P') IS NOT NULL DROP PROCEDURE dbo.z_sp_LoyaltyRedeemCancel;
IF OBJECT_ID(N'dbo.z_sp_LoyaltySyncBills', 'P')    IS NOT NULL DROP PROCEDURE dbo.z_sp_LoyaltySyncBills;
IF OBJECT_ID(N'dbo.z_sp_LoyaltyMembers', 'P')      IS NOT NULL DROP PROCEDURE dbo.z_sp_LoyaltyMembers;
IF OBJECT_ID(N'dbo.z_sp_LoyaltyMemberTxns', 'P')   IS NOT NULL DROP PROCEDURE dbo.z_sp_LoyaltyMemberTxns;
IF OBJECT_ID(N'dbo.z_sp_LoyaltyUpdateMember', 'P') IS NOT NULL DROP PROCEDURE dbo.z_sp_LoyaltyUpdateMember;
IF OBJECT_ID(N'dbo.z_sp_LoyaltyAdjust', 'P')       IS NOT NULL DROP PROCEDURE dbo.z_sp_LoyaltyAdjust;
IF TYPE_ID(N'dbo.z_tt_LoyaltyBill') IS NOT NULL DROP TYPE dbo.z_tt_LoyaltyBill;
GO
-- a bill with a member, as the till saved it (api/Loyalty/Bills)
CREATE TYPE dbo.z_tt_LoyaltyBill AS TABLE (
    InvoiceNo      VARCHAR(30)      NOT NULL PRIMARY KEY,
    Phone          VARCHAR(15)      NOT NULL,
    InvType        INT              NOT NULL,   -- 1 sale, 2 refund
    Status         INT              NOT NULL,   -- the bill's: 1 completed, 9 voided
    BillAmount     DECIMAL(18,2)    NOT NULL,   -- the amount the points were worked out on
    PointsEarned   INT              NOT NULL,   -- + earned (sale), - taken back (refund)
    PointsRedeemed INT              NOT NULL,
    RedeemAmount   DECIMAL(18,2)    NOT NULL,
    RedeemKey      UNIQUEIDENTIFIER NULL,
    CashierId      VARCHAR(20)      NULL,
    InvDate        DATETIME         NOT NULL
);
GO

-- the loyalty settings as numbers (the general values; loyalty has no per-user settings)
CREATE PROCEDURE dbo.z_sp_LoyaltySettings
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @v TABLE (SettingKey VARCHAR(50) PRIMARY KEY, Value NVARCHAR(200));
    INSERT @v SELECT SettingKey, COALESCE(Value, DefaultValue) FROM dbo.z_tb_Setting WHERE SettingKey LIKE 'Loyalty.%';
    SELECT CAST(CASE WHEN (SELECT Value FROM @v WHERE SettingKey = 'Loyalty.Enabled') = N'1' THEN 1 ELSE 0 END AS BIT) AS Enabled,
           CAST(ISNULL((SELECT Value FROM @v WHERE SettingKey = 'Loyalty.EarnAmount'), N'0') AS DECIMAL(18,2)) AS EarnAmount,
           CAST(ISNULL((SELECT Value FROM @v WHERE SettingKey = 'Loyalty.PointValue'), N'0') AS DECIMAL(18,2)) AS PointValue,
           CAST(CAST(ISNULL((SELECT Value FROM @v WHERE SettingKey = 'Loyalty.MinRedeem'), N'0') AS DECIMAL(18,2)) AS INT) AS MinRedeem,
           CAST(CASE WHEN (SELECT Value FROM @v WHERE SettingKey = 'Loyalty.PrintPoints') = N'1' THEN 1 ELSE 0 END AS BIT) AS PrintPoints,
           CASE WHEN (SELECT Value FROM @v WHERE SettingKey = 'Loyalty.RedeemMode') = N'2' THEN 2 ELSE 1 END AS RedeemMode,
           CAST(CAST(ISNULL((SELECT Value FROM @v WHERE SettingKey = 'Loyalty.DiscountPoints'), N'0') AS DECIMAL(18,2)) AS INT) AS DiscountPoints,
           CAST(ISNULL((SELECT Value FROM @v WHERE SettingKey = 'Loyalty.DiscountPercent'), N'0') AS DECIMAL(9,2)) AS DiscountPercent;
END
GO

-- one member by phone (no row = not a member)
CREATE PROCEDURE dbo.z_sp_LoyaltyGetMember
    @Phone VARCHAR(15)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT MemberId, Phone, Name, Points, TotalEarned, TotalRedeemed, Status, LastBillAt, CreatedAt
    FROM dbo.z_tb_LoyaltyMember WHERE Phone = @Phone;
END
GO

-- a new member (till Menu > Add loyalty member, or the back office). The phone must be new.
CREATE PROCEDURE dbo.z_sp_LoyaltyAddMember
    @Phone      VARCHAR(15),
    @Name       NVARCHAR(100),
    @TerminalId INT = NULL,
    @CreatedBy  VARCHAR(50) = NULL
AS
BEGIN
    DECLARE @z_tc INT; SET @z_tc = @@TRANCOUNT;   -- SQL 2008 R2 error handling (RAISERROR in TRY/CATCH)
    BEGIN TRY
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @Old NVARCHAR(100), @Id INT;
    SET @Phone = LTRIM(RTRIM(@Phone));
    SET @Name = LTRIM(RTRIM(@Name));
    IF @Phone IS NULL OR @Phone NOT LIKE '0%' OR @Phone LIKE '%[^0-9]%' OR LEN(@Phone) <> 10
        RAISERROR(N'%s', 16, 1, N'Enter the phone number as 10 digits, e.g. 0771234567.');
    IF ISNULL(@Name, N'') = N''
        RAISERROR(N'%s', 16, 1, N'Enter the member''s name.');

    SELECT @Old = Name FROM dbo.z_tb_LoyaltyMember WITH (UPDLOCK, HOLDLOCK) WHERE Phone = @Phone;
    IF @Old IS NOT NULL
    BEGIN
        DECLARE @Msg NVARCHAR(300); SET @Msg = N'This phone number is already a member: ' + @Old + N'.';
        RAISERROR(N'%s', 16, 1, @Msg);
    END
    INSERT dbo.z_tb_LoyaltyMember (Phone, Name, CreatedTerminalId, CreatedBy) VALUES (@Phone, @Name, @TerminalId, @CreatedBy);
    SET @Id = SCOPE_IDENTITY();

    SELECT MemberId, Phone, Name, Points, TotalEarned, TotalRedeemed, Status, LastBillAt, CreatedAt
    FROM dbo.z_tb_LoyaltyMember WHERE MemberId = @Id;
    END TRY
    BEGIN CATCH
        DECLARE @z_msg NVARCHAR(2048); SET @z_msg = ERROR_MESSAGE();
        IF @z_tc = 0 AND XACT_STATE() <> 0 ROLLBACK;
        RAISERROR(N'%s', 16, 1, @z_msg);
        RETURN 1;
    END CATCH
END
GO

-- Points used on a bill: taken off NOW, before the till saves the bill. The same RedeemKey again changes nothing
-- (a retry). Loyalty.RedeemMode 1 (pay with points): @Amount = at most @Points x PointValue; 2 (discount): @Points =
-- Loyalty.DiscountPoints, @Amount = the till's % of the bill. Both: only when the balance has reached MinRedeem.
-- -> the member after it.
CREATE PROCEDURE dbo.z_sp_LoyaltyRedeem
    @RedeemKey  UNIQUEIDENTIFIER,
    @Phone      VARCHAR(15),
    @Points     INT,
    @TerminalId INT,
    @CashierId  VARCHAR(20) = NULL,
    @Amount     DECIMAL(18,2) = NULL   -- rupees the points pay on the bill (NULL = Points x PointValue)
AS
BEGIN
    DECLARE @z_tc INT; SET @z_tc = @@TRANCOUNT;
    BEGIN TRY
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @Enabled BIT, @PointValue DECIMAL(18,2), @MinRedeem INT, @Mode INT, @DiscPoints INT, @MemberId INT, @Status INT,
            @Balance INT, @Msg NVARCHAR(300);
    DECLARE @Cfg TABLE (Enabled BIT, EarnAmount DECIMAL(18,2), PointValue DECIMAL(18,2), MinRedeem INT, PrintPoints BIT,
                        RedeemMode INT, DiscountPoints INT, DiscountPercent DECIMAL(9,2));
    INSERT @Cfg EXEC dbo.z_sp_LoyaltySettings;
    SELECT @Enabled = Enabled, @PointValue = PointValue, @MinRedeem = MinRedeem, @Mode = RedeemMode, @DiscPoints = DiscountPoints
    FROM @Cfg;

    IF @Enabled = 0
        RAISERROR(N'%s', 16, 1, N'Loyalty points are switched off on the back office.');
    IF ISNULL(@Points, 0) <= 0
        RAISERROR(N'%s', 16, 1, N'Enter the points to use (more than 0).');
    IF @Mode = 1 AND ISNULL(@PointValue, 0) <= 0
        RAISERROR(N'%s', 16, 1, N'The value of 1 point is not set on the back office.');
    IF @Mode = 1 AND @Amount > ROUND(@Points * @PointValue, 2)
        RAISERROR(N'%s', 16, 1, N'The points pay more than they are worth - enter the points again.');
    IF @Mode = 2 AND (ISNULL(@DiscPoints, 0) <= 0 OR @Points <> @DiscPoints)
    BEGIN
        SET @Msg = N'A points discount uses ' + CAST(ISNULL(@DiscPoints, 0) AS NVARCHAR(12)) + N' points - the settings changed, press Points again.';
        RAISERROR(N'%s', 16, 1, @Msg);
    END
    IF @Mode = 2 AND (@Amount IS NULL OR @Amount <= 0)
        RAISERROR(N'%s', 16, 1, N'The points discount amount is missing.');

    BEGIN TRAN;
        SELECT @MemberId = MemberId, @Status = Status, @Balance = Points
        FROM dbo.z_tb_LoyaltyMember WITH (UPDLOCK, HOLDLOCK) WHERE Phone = @Phone;
        IF @MemberId IS NULL
            RAISERROR(N'%s', 16, 1, N'This phone number is not a member.');

        IF NOT EXISTS (SELECT 1 FROM dbo.z_tb_LoyaltyTxn WHERE RedeemKey = @RedeemKey AND TxnType = 2)
        BEGIN
            IF @Status <> 1
                RAISERROR(N'%s', 16, 1, N'This member is blocked on the back office - points can''t be used.');
            IF @Balance < @MinRedeem
            BEGIN
                SET @Msg = N'Points can be used from ' + CAST(@MinRedeem AS NVARCHAR(12)) + N' points - the member has '
                         + CAST(@Balance AS NVARCHAR(12)) + N'.';
                RAISERROR(N'%s', 16, 1, @Msg);
            END
            IF @Points > @Balance
            BEGIN
                SET @Msg = N'The member has only ' + CAST(@Balance AS NVARCHAR(12)) + N' points.';
                RAISERROR(N'%s', 16, 1, @Msg);
            END

            UPDATE dbo.z_tb_LoyaltyMember SET Points = Points - @Points, TotalRedeemed = TotalRedeemed + @Points
            WHERE MemberId = @MemberId;
            INSERT dbo.z_tb_LoyaltyTxn (MemberId, TxnType, Points, BalanceAfter, TerminalId, BillAmount, RedeemKey, CashierId)
            VALUES (@MemberId, 2, -@Points, @Balance - @Points, @TerminalId, ISNULL(@Amount, ROUND(@Points * @PointValue, 2)), @RedeemKey,
                    @CashierId);
        END
    COMMIT;

    SELECT MemberId, Phone, Name, Points, TotalEarned, TotalRedeemed, Status, LastBillAt, CreatedAt
    FROM dbo.z_tb_LoyaltyMember WHERE MemberId = @MemberId;
    END TRY
    BEGIN CATCH
        DECLARE @z_msg NVARCHAR(2048); SET @z_msg = ERROR_MESSAGE();
        IF @z_tc = 0 AND XACT_STATE() <> 0 ROLLBACK;
        RAISERROR(N'%s', 16, 1, @z_msg);
        RETURN 1;
    END CATCH
END
GO

-- The bill the points were for was not saved (or was voided): the points go back. Only a redeem not yet on a bill;
-- the same key again changes nothing. -> Returned 1 / 0
CREATE PROCEDURE dbo.z_sp_LoyaltyRedeemCancel
    @RedeemKey UNIQUEIDENTIFIER,
    @Remark    NVARCHAR(200) = NULL,
    @AnyState  BIT = 0            -- 1 = also a redeem already on a bill (the bill was voided)
AS
BEGIN
    DECLARE @z_tc INT; SET @z_tc = @@TRANCOUNT;
    BEGIN TRY
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @MemberId INT, @Points INT, @Balance INT, @TerminalId INT, @InvoiceNo VARCHAR(30), @Amount DECIMAL(18,2), @Done BIT;
    SET @Done = 0;
    BEGIN TRAN;
        SELECT @MemberId = t.MemberId, @Points = -t.Points, @TerminalId = t.TerminalId, @InvoiceNo = t.InvoiceNo, @Amount = t.BillAmount
        FROM dbo.z_tb_LoyaltyTxn t WITH (UPDLOCK, HOLDLOCK)
        WHERE t.RedeemKey = @RedeemKey AND t.TxnType = 2;

        IF @MemberId IS NOT NULL AND (@InvoiceNo IS NULL OR @AnyState = 1)
           AND NOT EXISTS (SELECT 1 FROM dbo.z_tb_LoyaltyTxn WHERE RedeemKey = @RedeemKey AND TxnType = 3)
        BEGIN
            UPDATE dbo.z_tb_LoyaltyMember WITH (UPDLOCK)
            SET @Balance = Points = Points + @Points, TotalRedeemed = TotalRedeemed - @Points
            WHERE MemberId = @MemberId;
            INSERT dbo.z_tb_LoyaltyTxn (MemberId, TxnType, Points, BalanceAfter, TerminalId, InvoiceNo, BillAmount, RedeemKey, Remark)
            VALUES (@MemberId, 3, @Points, @Balance, @TerminalId, @InvoiceNo, @Amount, @RedeemKey,
                    ISNULL(@Remark, N'Bill not saved - points given back'));
            SET @Done = 1;
        END
    COMMIT;
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

-- Bills with a member, uploaded by a till: earn (sale) / take back (refund), and the redeem linked to its bill
-- (a voided bill gives its redeem back). A phone that is not a member is skipped. A resend changes nothing.
-- -> the InvoiceNo of every row (all are done)
CREATE PROCEDURE dbo.z_sp_LoyaltySyncBills
    @TerminalId INT,
    @Bills      dbo.z_tt_LoyaltyBill READONLY
AS
BEGIN
    DECLARE @z_tc INT; SET @z_tc = @@TRANCOUNT;
    BEGIN TRY
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @No VARCHAR(30), @Phone VARCHAR(15), @Status INT, @Amount DECIMAL(18,2), @Earned INT, @Key UNIQUEIDENTIFIER,
            @Cashier VARCHAR(20), @InvDate DATETIME, @MemberId INT, @Balance INT, @Take INT, @TxnType INT;

    DECLARE c CURSOR LOCAL FAST_FORWARD FOR
        SELECT InvoiceNo, Phone, Status, BillAmount, PointsEarned, RedeemKey, CashierId, InvDate FROM @Bills ORDER BY InvDate, InvoiceNo;
    OPEN c;
    FETCH NEXT FROM c INTO @No, @Phone, @Status, @Amount, @Earned, @Key, @Cashier, @InvDate;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        BEGIN TRAN;
            SET @MemberId = NULL;
            SELECT @MemberId = MemberId, @Balance = Points
            FROM dbo.z_tb_LoyaltyMember WITH (UPDLOCK, HOLDLOCK) WHERE Phone = @Phone;

            IF @MemberId IS NOT NULL
            BEGIN
                -- the redeem made before the bill was saved: on this bill now (voided bill: points back)
                IF @Key IS NOT NULL
                BEGIN
                    UPDATE dbo.z_tb_LoyaltyTxn SET InvoiceNo = @No
                    WHERE RedeemKey = @Key AND TxnType IN (2, 3) AND InvoiceNo IS NULL;
                    IF @Status = 9
                        EXEC dbo.z_sp_LoyaltyRedeemCancel @RedeemKey = @Key, @Remark = N'Bill voided - points given back', @AnyState = 1;
                END

                SET @TxnType = CASE WHEN @Earned > 0 THEN 1 WHEN @Earned < 0 THEN 4 END;
                IF @Status <> 9 AND @TxnType IS NOT NULL
                   AND NOT EXISTS (SELECT 1 FROM dbo.z_tb_LoyaltyTxn WHERE InvoiceNo = @No AND TxnType = @TxnType)
                BEGIN
                    SELECT @Balance = Points FROM dbo.z_tb_LoyaltyMember WHERE MemberId = @MemberId;
                    -- a refund takes back at most what the member has (never below 0)
                    SET @Take = CASE WHEN @Earned > 0 THEN @Earned ELSE -CASE WHEN -@Earned > @Balance THEN @Balance ELSE -@Earned END END;
                    UPDATE dbo.z_tb_LoyaltyMember
                    SET Points = Points + @Take,
                        TotalEarned = TotalEarned + @Take,
                        LastBillAt = CASE WHEN LastBillAt IS NULL OR LastBillAt < @InvDate THEN @InvDate ELSE LastBillAt END
                    WHERE MemberId = @MemberId;
                    INSERT dbo.z_tb_LoyaltyTxn (MemberId, TxnType, Points, BalanceAfter, TerminalId, InvoiceNo, BillAmount, CashierId, TxnAt,
                                                Remark)
                    VALUES (@MemberId, @TxnType, @Take, @Balance + @Take, @TerminalId, @No, @Amount, @Cashier, @InvDate,
                            CASE WHEN @TxnType = 4 AND @Take <> @Earned THEN N'Refund: only the points left were taken back' END);
                END
                ELSE IF @Status <> 9
                    UPDATE dbo.z_tb_LoyaltyMember
                    SET LastBillAt = CASE WHEN LastBillAt IS NULL OR LastBillAt < @InvDate THEN @InvDate ELSE LastBillAt END
                    WHERE MemberId = @MemberId;
            END
        COMMIT;
        FETCH NEXT FROM c INTO @No, @Phone, @Status, @Amount, @Earned, @Key, @Cashier, @InvDate;
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

-- Loyalty page: members by phone or name (empty text = the latest), top N
CREATE PROCEDURE dbo.z_sp_LoyaltyMembers
    @Text NVARCHAR(100) = NULL,
    @Top  INT = 200
AS
BEGIN
    SET NOCOUNT ON;
    SET @Text = NULLIF(LTRIM(RTRIM(@Text)), N'');
    SELECT TOP (@Top) MemberId, Phone, Name, Points, TotalEarned, TotalRedeemed, Status, LastBillAt, CreatedAt,
           CreatedTerminalId, CreatedBy
    FROM dbo.z_tb_LoyaltyMember
    WHERE @Text IS NULL OR Phone LIKE '%' + @Text + '%' OR Name LIKE N'%' + @Text + N'%'
    ORDER BY CASE WHEN @Text IS NULL THEN 0 ELSE 1 END, ISNULL(LastBillAt, CreatedAt) DESC, MemberId DESC;

    -- the totals of all members
    SELECT COUNT(*) AS Members, ISNULL(SUM(CAST(Points AS BIGINT)), 0) AS PointsOutstanding,
           SUM(CASE WHEN Status = 1 THEN 1 ELSE 0 END) AS Active
    FROM dbo.z_tb_LoyaltyMember;
END
GO

-- a member's points history, newest first
CREATE PROCEDURE dbo.z_sp_LoyaltyMemberTxns
    @MemberId INT,
    @Top      INT = 500
AS
BEGIN
    SET NOCOUNT ON;
    SELECT TOP (@Top) t.TxnId, t.TxnType, t.Points, t.BalanceAfter, t.TerminalId, tm.TerminalCode, t.InvoiceNo, t.BillAmount,
           t.CashierId, t.UserId, u.UserName, t.Remark, t.TxnAt
    FROM dbo.z_tb_LoyaltyTxn t
    LEFT JOIN dbo.z_tb_Terminal tm ON tm.TerminalId = t.TerminalId
    LEFT JOIN dbo.z_tb_User u      ON u.UserId = t.UserId
    WHERE t.MemberId = @MemberId
    ORDER BY t.TxnId DESC;
END
GO

-- name / phone / blocked on the Loyalty page
CREATE PROCEDURE dbo.z_sp_LoyaltyUpdateMember
    @MemberId INT,
    @Phone    VARCHAR(15),
    @Name     NVARCHAR(100),
    @Status   INT,
    @UserId   INT = NULL
AS
BEGIN
    DECLARE @z_tc INT; SET @z_tc = @@TRANCOUNT;
    BEGIN TRY
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @Phone = LTRIM(RTRIM(@Phone));
    SET @Name = LTRIM(RTRIM(@Name));
    IF @Phone IS NULL OR @Phone NOT LIKE '0%' OR @Phone LIKE '%[^0-9]%' OR LEN(@Phone) <> 10
        RAISERROR(N'%s', 16, 1, N'Enter the phone number as 10 digits, e.g. 0771234567.');
    IF ISNULL(@Name, N'') = N''
        RAISERROR(N'%s', 16, 1, N'Enter the member''s name.');
    IF @Status NOT IN (0, 1)
        RAISERROR(N'%s', 16, 1, N'Status must be 1 (active) or 0 (blocked).');
    IF NOT EXISTS (SELECT 1 FROM dbo.z_tb_LoyaltyMember WHERE MemberId = @MemberId)
        RAISERROR(N'%s', 16, 1, N'Member not found.');
    IF EXISTS (SELECT 1 FROM dbo.z_tb_LoyaltyMember WHERE Phone = @Phone AND MemberId <> @MemberId)
        RAISERROR(N'%s', 16, 1, N'Another member has this phone number.');

    UPDATE dbo.z_tb_LoyaltyMember
    SET Phone = @Phone, Name = @Name, Status = @Status, UpdatedAt = GETDATE(), UpdatedBy = @UserId
    WHERE MemberId = @MemberId;
    END TRY
    BEGIN CATCH
        DECLARE @z_msg NVARCHAR(2048); SET @z_msg = ERROR_MESSAGE();
        IF @z_tc = 0 AND XACT_STATE() <> 0 ROLLBACK;
        RAISERROR(N'%s', 16, 1, @z_msg);
        RETURN 1;
    END CATCH
END
GO

-- points added (+) or taken off (-) by hand, with the reason. Never below 0.
CREATE PROCEDURE dbo.z_sp_LoyaltyAdjust
    @MemberId INT,
    @Points   INT,
    @Remark   NVARCHAR(200),
    @UserId   INT = NULL
AS
BEGIN
    DECLARE @z_tc INT; SET @z_tc = @@TRANCOUNT;
    BEGIN TRY
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @Balance INT;
    SET @Remark = NULLIF(LTRIM(RTRIM(@Remark)), N'');
    IF ISNULL(@Points, 0) = 0
        RAISERROR(N'%s', 16, 1, N'Enter the points to add (+) or take off (-).');
    IF @Remark IS NULL
        RAISERROR(N'%s', 16, 1, N'Enter the reason.');
    BEGIN TRAN;
        SELECT @Balance = Points FROM dbo.z_tb_LoyaltyMember WITH (UPDLOCK, HOLDLOCK) WHERE MemberId = @MemberId;
        IF @Balance IS NULL
            RAISERROR(N'%s', 16, 1, N'Member not found.');
        IF @Balance + @Points < 0
            RAISERROR(N'%s', 16, 1, N'The member does not have that many points.');
        UPDATE dbo.z_tb_LoyaltyMember
        SET Points = Points + @Points, TotalEarned = TotalEarned + @Points, UpdatedAt = GETDATE(), UpdatedBy = @UserId
        WHERE MemberId = @MemberId;
        INSERT dbo.z_tb_LoyaltyTxn (MemberId, TxnType, Points, BalanceAfter, UserId, Remark)
        VALUES (@MemberId, 5, @Points, @Balance + @Points, @UserId, @Remark);
    COMMIT;
    SELECT @Balance + @Points AS Points;
    END TRY
    BEGIN CATCH
        DECLARE @z_msg NVARCHAR(2048); SET @z_msg = ERROR_MESSAGE();
        IF @z_tc = 0 AND XACT_STATE() <> 0 ROLLBACK;
        RAISERROR(N'%s', 16, 1, @z_msg);
        RETURN 1;
    END CATCH
END
GO
