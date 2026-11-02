/* =============================================================================
   U038_Till_Loyalty.sql   (2026-11-02)
   Update for a till db (z_pos_fnt_db) that is ALREADY deployed. SQL Server 2008 R2 and newer.
   Safe to run again. One new, empty table and two new columns; bills, Z reports and logs are not changed.

   What changes (customer loyalty points, Docs/StockSystem.md 6.33):
     - table zf_tb_LoyaltyBill: the member (phone) of a bill, the points it earned / used (sent up with
       POST api/Loyalty/Bills); zf_tb_SuspendedBill.LoyaltyPhone / LoyaltyName (the member stays on a suspended bill)
     - procedures zf_sp_SaveLoyaltyBill (in the bill's transaction), zf_sp_GetLoyaltyBill, zf_sp_GetUnsyncedLoyaltyBills,
       zf_sp_MarkLoyaltyBillsSynced, zf_sp_SetSuspendedLoyalty, zf_sp_GetSuspendedLoyalty
     - points used on a bill are its payment PayType 8 (POINTS); zf_sp_SaveInvoice is not changed
   Same change in the full script: 02_FrontCashier_zf.sql (last section).

   Order: U038_BackOffice_Loyalty.sql + the new ItemApi first, then on each till:
     1. sqlcmd -S .\SQLEXPRESS -d z_pos_fnt_db -E -I -b -i U038_Till_Loyalty.sql
     2. install the new TillService and the new billing page (the old ones keep working after the script)
   Loyalty stays off until it is switched on on the back office (Loyalty page).
   ============================================================================= */
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
IF OBJECT_ID(N'dbo.zf_tb_Invoice', 'U') IS NULL OR OBJECT_ID(N'dbo.zf_tb_SuspendedBill', 'U') IS NULL
   OR OBJECT_ID(N'dbo.zf_tb_Setting', 'U') IS NULL OR TYPE_ID(N'dbo.zf_tt_InvoiceNo') IS NULL
BEGIN
    RAISERROR('This is not a till database with U023 (zf_tb_Invoice / zf_tb_SuspendedBill / zf_tb_Setting not found) - nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
GO
/* ---------------------------------------------------------------------------
   Loyalty points (2026-11-02, Docs/StockSystem.md 6.33, U038)
   The cashier puts a member (phone number) on a bill. The back office keeps the members and the balance; this till
   keeps, per bill with a member, the points it earned / used, and sends them up (POST api/Loyalty/Bills).
   Points used on a bill are taken off on the back office BEFORE the bill is saved (TillService); they are a payment
   of the bill: zf_tb_InvoicePayment PayType 8 (POINTS).
   Settings come down with the others (zf_tb_Setting): Loyalty.Enabled, Loyalty.EarnAmount, ...
   Self-contained section: its own procs are dropped and recreated here.
   --------------------------------------------------------------------------- */
-- 1. tables
IF OBJECT_ID(N'dbo.zf_tb_LoyaltyBill', 'U') IS NULL
CREATE TABLE dbo.zf_tb_LoyaltyBill (
    InvoiceNo      VARCHAR(30)      NOT NULL CONSTRAINT PK_zf_tb_LoyaltyBill PRIMARY KEY,
    Phone          VARCHAR(15)      NOT NULL,
    MemberName     NVARCHAR(100)    NULL,
    InvType        INT              NOT NULL,   -- 1 sale, 2 refund
    BillAmount     DECIMAL(18,2)    NOT NULL,   -- what the points were worked out on (sale: net less the points part)
    PointsEarned   INT              NOT NULL,   -- + earned (sale), - taken back (refund)
    PointsRedeemed INT              NOT NULL,   -- used to pay this bill
    RedeemAmount   DECIMAL(18,2)    NOT NULL,   -- rupees they paid (= the PayType 8 payment)
    RedeemKey      UNIQUEIDENTIFIER NULL,       -- the back office redeem (z_tb_LoyaltyTxn.RedeemKey)
    BalanceBefore  INT              NULL,       -- the member's points when the bill was paid (NULL = not known, offline)
    CreatedAt      DATETIME         NOT NULL CONSTRAINT DF_zf_tb_LoyaltyBill_CreatedAt DEFAULT (GETDATE()),
    Synced         BIT              NOT NULL CONSTRAINT DF_zf_tb_LoyaltyBill_Synced DEFAULT (0),
    SyncedAt       DATETIME         NULL
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_zf_tb_LoyaltyBill_Synced')
    CREATE INDEX IX_zf_tb_LoyaltyBill_Synced ON dbo.zf_tb_LoyaltyBill (Synced, CreatedAt);
GO
-- the member stays on a suspended bill
IF COL_LENGTH('dbo.zf_tb_SuspendedBill', 'LoyaltyPhone') IS NULL
    ALTER TABLE dbo.zf_tb_SuspendedBill ADD LoyaltyPhone VARCHAR(15) NULL, LoyaltyName NVARCHAR(100) NULL;
GO

-- 2. procedures
IF OBJECT_ID(N'dbo.zf_sp_SaveLoyaltyBill', 'P')         IS NOT NULL DROP PROCEDURE dbo.zf_sp_SaveLoyaltyBill;
IF OBJECT_ID(N'dbo.zf_sp_GetLoyaltyBill', 'P')          IS NOT NULL DROP PROCEDURE dbo.zf_sp_GetLoyaltyBill;
IF OBJECT_ID(N'dbo.zf_sp_GetUnsyncedLoyaltyBills', 'P') IS NOT NULL DROP PROCEDURE dbo.zf_sp_GetUnsyncedLoyaltyBills;
IF OBJECT_ID(N'dbo.zf_sp_MarkLoyaltyBillsSynced', 'P')  IS NOT NULL DROP PROCEDURE dbo.zf_sp_MarkLoyaltyBillsSynced;
IF OBJECT_ID(N'dbo.zf_sp_SetSuspendedLoyalty', 'P')     IS NOT NULL DROP PROCEDURE dbo.zf_sp_SetSuspendedLoyalty;
IF OBJECT_ID(N'dbo.zf_sp_GetSuspendedLoyalty', 'P')     IS NOT NULL DROP PROCEDURE dbo.zf_sp_GetSuspendedLoyalty;
GO

-- The member of a bill just saved (TillService, in the bill's transaction). Points earned = FLOOR(the net less the
-- part paid with points / Loyalty.EarnAmount); a refund bill takes them back (minus). A refund of a bill without a
-- phone gets the phone of the bill refunded. Loyalty off -> nothing earned (a redeem made before is still kept).
-- No phone -> nothing. Saved again -> unchanged. -> the row
CREATE PROCEDURE dbo.zf_sp_SaveLoyaltyBill
    @InvoiceNo      VARCHAR(30),
    @Phone          VARCHAR(15) = NULL,
    @MemberName     NVARCHAR(100) = NULL,
    @PointsRedeemed INT = 0,
    @RedeemAmount   DECIMAL(18,2) = 0,
    @RedeemKey      UNIQUEIDENTIFIER = NULL,
    @BalanceBefore  INT = NULL
AS
BEGIN
    DECLARE @z_tc INT; SET @z_tc = @@TRANCOUNT;   -- SQL 2008 R2 error handling (RAISERROR in TRY/CATCH)
    BEGIN TRY
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @InvType INT, @Net DECIMAL(18,2), @Ref VARCHAR(30), @Paid DECIMAL(18,2), @Base DECIMAL(18,2), @Earn DECIMAL(18,2),
            @On BIT, @Points INT;

    SELECT @InvType = InvType, @Net = NetAmount, @Ref = RefInvoiceNo FROM dbo.zf_tb_Invoice WHERE InvoiceNo = @InvoiceNo;
    IF @InvType IS NULL
        RAISERROR(N'%s', 16, 1, N'Bill not found on this till.');

    SET @Phone = NULLIF(LTRIM(RTRIM(@Phone)), '');
    IF @Phone IS NULL AND @InvType = 2 AND @Ref IS NOT NULL
        SELECT @Phone = Phone, @MemberName = ISNULL(@MemberName, MemberName) FROM dbo.zf_tb_LoyaltyBill WHERE InvoiceNo = @Ref;

    IF @Phone IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.zf_tb_LoyaltyBill WHERE InvoiceNo = @InvoiceNo)
    BEGIN
        SET @On = CASE WHEN EXISTS (SELECT 1 FROM dbo.zf_tb_Setting WHERE SettingKey = 'Loyalty.Enabled' AND Value = N'1') THEN 1 ELSE 0 END;
        SELECT @Earn = CASE WHEN Value LIKE N'%[0-9]%' AND Value NOT LIKE N'%[^0-9.]%' THEN CAST(Value AS DECIMAL(18,2)) END
        FROM dbo.zf_tb_Setting WHERE SettingKey = 'Loyalty.EarnAmount';

        SELECT @Paid = ISNULL(SUM(Amount), 0) FROM dbo.zf_tb_InvoicePayment WHERE InvoiceNo = @InvoiceNo AND PayType = 8;
        SET @Base = CASE WHEN @InvType = 2 THEN @Net ELSE @Net - @Paid END;
        SET @Points = CASE WHEN @On = 1 AND @Earn > 0 AND @Base > 0 THEN FLOOR(@Base / @Earn) ELSE 0 END;
        IF @InvType = 2 SET @Points = -@Points;

        INSERT dbo.zf_tb_LoyaltyBill (InvoiceNo, Phone, MemberName, InvType, BillAmount, PointsEarned, PointsRedeemed, RedeemAmount,
                                      RedeemKey, BalanceBefore)
        VALUES (@InvoiceNo, @Phone, NULLIF(LTRIM(RTRIM(@MemberName)), N''), @InvType, CASE WHEN @Base > 0 THEN @Base ELSE 0 END,
                @Points, ISNULL(@PointsRedeemed, 0), ISNULL(@RedeemAmount, 0), @RedeemKey, @BalanceBefore);
    END

    SELECT InvoiceNo, Phone, MemberName, InvType, BillAmount, PointsEarned, PointsRedeemed, RedeemAmount, RedeemKey, BalanceBefore
    FROM dbo.zf_tb_LoyaltyBill WHERE InvoiceNo = @InvoiceNo;
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

-- the member of one bill (receipt, bill copy); no row = no member
CREATE PROCEDURE dbo.zf_sp_GetLoyaltyBill
    @InvoiceNo VARCHAR(30)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT InvoiceNo, Phone, MemberName, InvType, BillAmount, PointsEarned, PointsRedeemed, RedeemAmount, RedeemKey, BalanceBefore
    FROM dbo.zf_tb_LoyaltyBill WHERE InvoiceNo = @InvoiceNo;
END
GO

-- not sent up yet, oldest first (with the bill's Status: a voided bill gives its redeem back)
CREATE PROCEDURE dbo.zf_sp_GetUnsyncedLoyaltyBills
    @Top INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    SELECT TOP (@Top) l.InvoiceNo, l.Phone, l.InvType, i.Status, l.BillAmount, l.PointsEarned, l.PointsRedeemed, l.RedeemAmount,
           l.RedeemKey, i.CashierId, i.InvDate
    FROM dbo.zf_tb_LoyaltyBill l
    JOIN dbo.zf_tb_Invoice i ON i.InvoiceNo = l.InvoiceNo
    WHERE l.Synced = 0
    ORDER BY l.CreatedAt, l.InvoiceNo;
END
GO

CREATE PROCEDURE dbo.zf_sp_MarkLoyaltyBillsSynced
    @InvoiceNos dbo.zf_tt_InvoiceNo READONLY
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE l SET Synced = 1, SyncedAt = GETDATE()
    FROM dbo.zf_tb_LoyaltyBill l JOIN @InvoiceNos n ON n.InvoiceNo = l.InvoiceNo;
END
GO

-- the member of a bill being suspended (TillService, in the suspend's transaction)
CREATE PROCEDURE dbo.zf_sp_SetSuspendedLoyalty
    @SuspendId INT,
    @Phone     VARCHAR(15),
    @Name      NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.zf_tb_SuspendedBill SET LoyaltyPhone = NULLIF(LTRIM(RTRIM(@Phone)), ''), LoyaltyName = NULLIF(LTRIM(RTRIM(@Name)), N'')
    WHERE SuspendId = @SuspendId;
END
GO

CREATE PROCEDURE dbo.zf_sp_GetSuspendedLoyalty
    @SuspendId INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT LoyaltyPhone, LoyaltyName FROM dbo.zf_tb_SuspendedBill WHERE SuspendId = @SuspendId;
END
GO

PRINT 'U038_Till_Loyalty done.';
GO
