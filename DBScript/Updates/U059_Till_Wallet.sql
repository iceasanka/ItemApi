/* =============================================================================
   U059_Till_Wallet.sql   (2026-11-11)
   Update for a till db (z_pos_fnt_db) that is ALREADY deployed. SQL Server 2008 R2 and newer.
   Safe to run again. One new, empty table and new procedures; bills, Z reports and zf_sp_SaveInvoice are not changed.

   Customer wallet (back office U059_BackOffice_Wallet.sql): with a loyalty member on the bill, change can be kept in the
   member's wallet and the wallet can pay part of a bill. On the bill it is ONE payment, PayType 9 (WALLET), signed:
   + paid from the wallet, - change kept (cash 90 + wallet -5 = a bill of 85, and 90 is what went in the drawer). So
   the Z, day end and cash count need no change. Wallet money is never paid out as cash.
     - table zf_tb_WalletBill: the member and the wallet part of a bill (sent up with POST api/Wallet/Bills to link the
       back office txn to the bill; a voided bill gives it back)
     - procedures zf_sp_SaveWalletBill (in the bill's transaction), zf_sp_GetWalletBill, zf_sp_GetUnsyncedWalletBills,
       zf_sp_MarkWalletBillsSynced
   The back office does the balance BEFORE the bill is saved (TillService, api/Wallet/Bill).
   Same change in the full script: 02_FrontCashier_zf.sql (last section).

   Order: U059_BackOffice_Wallet.sql + the new ItemApi first, then on each till:
     1. sqlcmd -S .\SQLEXPRESS -d z_pos_fnt_db -E -I -b -i U059_Till_Wallet.sql
     2. install the new TillService and the new billing page (the old ones keep working after the script)
   The wallet stays off until it is switched on on the back office (System Settings > Wallet).
   ============================================================================= */
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
IF OBJECT_ID(N'dbo.zf_tb_Invoice', 'U') IS NULL OR OBJECT_ID(N'dbo.zf_tb_InvoicePayment', 'U') IS NULL
   OR TYPE_ID(N'dbo.zf_tt_InvoiceNo') IS NULL
BEGIN
    RAISERROR('This is not a till database (zf_tb_Invoice / zf_tb_InvoicePayment / zf_tt_InvoiceNo not found) - nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
GO
/* ---------------------------------------------------------------------------
   Customer wallet (2026-11-11, U059)
   The wallet part of a bill is its PayType 9 (WALLET) payment: + paid from the member's wallet, - change kept in it.
   The back office keeps the balance and does it BEFORE the bill is saved (TillService, api/Wallet/Bill, key
   WalletKey); this till keeps, per bill, the key and the amount, and sends them up (POST api/Wallet/Bills).
   Settings come down with the others (zf_tb_Setting): Wallet.Enabled, Wallet.MaxKeep, Wallet.MaxBalance,
   Wallet.MinusLimit. Self-contained section: its own procs are dropped and recreated here.
   --------------------------------------------------------------------------- */
-- 1. tables
IF OBJECT_ID(N'dbo.zf_tb_WalletBill', 'U') IS NULL
CREATE TABLE dbo.zf_tb_WalletBill (
    InvoiceNo     VARCHAR(30)      NOT NULL CONSTRAINT PK_zf_tb_WalletBill PRIMARY KEY,
    Phone         VARCHAR(15)      NOT NULL,
    MemberName    NVARCHAR(100)    NULL,
    Amount        DECIMAL(18,2)    NOT NULL,   -- = the bill's PayType 9 payments: + paid from the wallet, - change kept
    WalletKey     UNIQUEIDENTIFIER NOT NULL,   -- the back office txn (z_tb_WalletTxn.WalletKey)
    BalanceBefore DECIMAL(18,2)    NULL,       -- the wallet before this bill (printed: balance after = before - Amount)
    CreatedAt     DATETIME         NOT NULL CONSTRAINT DF_zf_tb_WalletBill_CreatedAt DEFAULT (GETDATE()),
    Synced        BIT              NOT NULL CONSTRAINT DF_zf_tb_WalletBill_Synced DEFAULT (0),
    SyncedAt      DATETIME         NULL
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_zf_tb_WalletBill_Synced')
    CREATE INDEX IX_zf_tb_WalletBill_Synced ON dbo.zf_tb_WalletBill (Synced, CreatedAt);
GO

-- 2. procedures
IF OBJECT_ID(N'dbo.zf_sp_SaveWalletBill', 'P')         IS NOT NULL DROP PROCEDURE dbo.zf_sp_SaveWalletBill;
IF OBJECT_ID(N'dbo.zf_sp_GetWalletBill', 'P')          IS NOT NULL DROP PROCEDURE dbo.zf_sp_GetWalletBill;
IF OBJECT_ID(N'dbo.zf_sp_GetUnsyncedWalletBills', 'P') IS NOT NULL DROP PROCEDURE dbo.zf_sp_GetUnsyncedWalletBills;
IF OBJECT_ID(N'dbo.zf_sp_MarkWalletBillsSynced', 'P')  IS NOT NULL DROP PROCEDURE dbo.zf_sp_MarkWalletBillsSynced;
GO

-- The wallet part of a bill just saved (TillService, in the bill's transaction). Amount = the bill's PayType 9
-- payments; it must be the amount the back office did (@Amount) and not 0. Saved again -> unchanged. -> the row
CREATE PROCEDURE dbo.zf_sp_SaveWalletBill
    @InvoiceNo     VARCHAR(30),
    @Phone         VARCHAR(15),
    @MemberName    NVARCHAR(100) = NULL,
    @Amount        DECIMAL(18,2),
    @WalletKey     UNIQUEIDENTIFIER,
    @BalanceBefore DECIMAL(18,2) = NULL
AS
BEGIN
    DECLARE @z_tc INT; SET @z_tc = @@TRANCOUNT;   -- SQL 2008 R2 error handling (RAISERROR in TRY/CATCH)
    BEGIN TRY
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @Paid DECIMAL(18,2);
    IF NOT EXISTS (SELECT 1 FROM dbo.zf_tb_Invoice WHERE InvoiceNo = @InvoiceNo)
        RAISERROR(N'%s', 16, 1, N'Bill not found on this till.');
    SET @Phone = NULLIF(LTRIM(RTRIM(@Phone)), '');
    IF @Phone IS NULL OR @WalletKey IS NULL
        RAISERROR(N'%s', 16, 1, N'The wallet needs the member''s phone and the wallet key.');

    IF NOT EXISTS (SELECT 1 FROM dbo.zf_tb_WalletBill WHERE InvoiceNo = @InvoiceNo)
    BEGIN
        SELECT @Paid = ISNULL(SUM(Amount), 0) FROM dbo.zf_tb_InvoicePayment WHERE InvoiceNo = @InvoiceNo AND PayType = 9;
        IF @Paid = 0 OR @Paid <> @Amount
            RAISERROR(N'%s', 16, 1, N'The wallet payment of the bill does not match the wallet amount - pay again.');
        INSERT dbo.zf_tb_WalletBill (InvoiceNo, Phone, MemberName, Amount, WalletKey, BalanceBefore)
        VALUES (@InvoiceNo, @Phone, NULLIF(LTRIM(RTRIM(@MemberName)), N''), @Paid, @WalletKey, @BalanceBefore);
    END

    SELECT InvoiceNo, Phone, MemberName, Amount, WalletKey, BalanceBefore
    FROM dbo.zf_tb_WalletBill WHERE InvoiceNo = @InvoiceNo;
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

-- the wallet part of one bill (receipt, bill copy); no row = none
CREATE PROCEDURE dbo.zf_sp_GetWalletBill
    @InvoiceNo VARCHAR(30)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT InvoiceNo, Phone, MemberName, Amount, WalletKey, BalanceBefore
    FROM dbo.zf_tb_WalletBill WHERE InvoiceNo = @InvoiceNo;
END
GO

-- not sent up yet, oldest first (with the bill's Status: a voided bill gives its wallet part back)
CREATE PROCEDURE dbo.zf_sp_GetUnsyncedWalletBills
    @Top INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    SELECT TOP (@Top) w.InvoiceNo, w.WalletKey, i.Status
    FROM dbo.zf_tb_WalletBill w
    JOIN dbo.zf_tb_Invoice i ON i.InvoiceNo = w.InvoiceNo
    WHERE w.Synced = 0
    ORDER BY w.CreatedAt, w.InvoiceNo;
END
GO

CREATE PROCEDURE dbo.zf_sp_MarkWalletBillsSynced
    @InvoiceNos dbo.zf_tt_InvoiceNo READONLY
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE w SET Synced = 1, SyncedAt = GETDATE()
    FROM dbo.zf_tb_WalletBill w JOIN @InvoiceNos n ON n.InvoiceNo = w.InvoiceNo;
END
GO

SET NOEXEC OFF;
GO
PRINT 'U059_Till_Wallet done.';
GO
