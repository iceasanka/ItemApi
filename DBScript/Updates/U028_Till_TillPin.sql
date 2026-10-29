/* =============================================================================
   U028_Till_TillPin.sql   (2026-10-29)
   Update for a till db (z_pos_fnt_db) that is ALREADY deployed. SQL Server 2008 R2 and newer.
   Safe to run again. Bills, Z reports and logs are not changed (two new columns on the cashier list).

   What changes (supervisor PIN from the users, Docs/StockSystem.md 6.12):
     - zf_tb_Cashier.PinHash: the supervisor PIN of a cashier admin (Users page on the back office, a PBKDF2 hash;
       SQL never sees a PIN). TillService checks the PIN typed at the till against every till user with one, instead
       of Till:SupervisorPin in appsettings (that one is used only while no user on the till has a PIN).
     - zf_tb_Cashier.AskPin: 0 = the till does not ask the PIN while this user is signed in. Old rows: 1.
     - type zf_tt_CashierPin, zf_sp_UpsertCashiers gets @Pins (left out by the old TillService = PINs unchanged),
       zf_sp_GetCashier also returns AskPin, new zf_sp_GetSupervisorPins.
     - LastCashierSyncAt is cleared, so the next download brings every user again (with the PINs).
   Same change in the full script: 02_FrontCashier_zf.sql.

   Order: U028_BackOffice_TillPin.sql + the new ItemApi first, then on each till:
     1. sqlcmd -S .\SQLEXPRESS -d z_pos_fnt_db -E -I -b -i U028_Till_TillPin.sql
     2. install the new TillService and the new billing page (the old ones keep working after the script, with
        Till:SupervisorPin)
   ============================================================================= */
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
IF OBJECT_ID(N'dbo.zf_tb_InvoiceItem', 'U') IS NULL OR OBJECT_ID(N'dbo.zf_tb_ZReport', 'U') IS NULL
   OR OBJECT_ID(N'dbo.zf_tb_Config', 'U') IS NULL
BEGIN
    RAISERROR('This is not a till database (zf_tb_InvoiceItem / zf_tb_ZReport / zf_tb_Config not found) - nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
GO
IF OBJECT_ID(N'dbo.zf_tb_Cashier', 'U') IS NULL OR TYPE_ID(N'dbo.zf_tt_Cashier') IS NULL
BEGIN
    RAISERROR('This till db has no cashier sign-in yet (zf_tb_Cashier) - run 02_FrontCashier_zf.sql first. Nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
GO

-- 1. columns
IF COL_LENGTH('dbo.zf_tb_Cashier', 'PinHash') IS NULL
    ALTER TABLE dbo.zf_tb_Cashier ADD PinHash VARCHAR(255) NULL;
IF COL_LENGTH('dbo.zf_tb_Cashier', 'AskPin') IS NULL
    ALTER TABLE dbo.zf_tb_Cashier ADD AskPin BIT NOT NULL CONSTRAINT DF_zf_tb_Cashier_AskPin DEFAULT (1);
GO

-- 2. type (dropped with its proc)
IF OBJECT_ID(N'dbo.zf_sp_UpsertCashiers', 'P')    IS NOT NULL DROP PROCEDURE dbo.zf_sp_UpsertCashiers;
IF OBJECT_ID(N'dbo.zf_sp_GetCashier', 'P')        IS NOT NULL DROP PROCEDURE dbo.zf_sp_GetCashier;
IF OBJECT_ID(N'dbo.zf_sp_GetSupervisorPins', 'P') IS NOT NULL DROP PROCEDURE dbo.zf_sp_GetSupervisorPins;
GO
IF TYPE_ID(N'dbo.zf_tt_CashierPin') IS NOT NULL DROP TYPE dbo.zf_tt_CashierPin;
GO
CREATE TYPE dbo.zf_tt_CashierPin AS TABLE (
    UserId   INT          NOT NULL PRIMARY KEY,
    PinHash  VARCHAR(255) NULL,
    AskPin   BIT          NOT NULL
);
GO

-- 3. procedures (same as 02_FrontCashier_zf.sql)
-- @Pins: the PIN and AskPin of the downloaded users (the old TillService does not send it - then they stay as they
-- are). A user who may not use the till keeps no hash and no PIN.
CREATE PROCEDURE dbo.zf_sp_UpsertCashiers
    @Rows        dbo.zf_tt_Cashier READONLY,
    @ServerTime  DATETIME,
    @Pins        dbo.zf_tt_CashierPin READONLY
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRAN;
        -- a login name that moved to another user id (rare) - drop the old row first so the unique index holds
        DELETE t FROM dbo.zf_tb_Cashier t
        JOIN @Rows s ON s.LoginName = t.LoginName AND s.UserId <> t.UserId;

        UPDATE t SET LoginName = s.LoginName, UserName = s.UserName, RoleId = s.RoleId, CanUseTill = s.CanUseTill,
                     PasswordHash = CASE WHEN s.CanUseTill = 1 THEN s.PasswordHash END, UpdatedDate = s.UpdatedDate
        FROM dbo.zf_tb_Cashier t JOIN @Rows s ON s.UserId = t.UserId;

        INSERT dbo.zf_tb_Cashier (UserId, LoginName, UserName, RoleId, CanUseTill, PasswordHash, UpdatedDate)
        SELECT s.UserId, s.LoginName, s.UserName, s.RoleId, s.CanUseTill,
               CASE WHEN s.CanUseTill = 1 THEN s.PasswordHash END, s.UpdatedDate
        FROM @Rows s
        WHERE NOT EXISTS (SELECT 1 FROM dbo.zf_tb_Cashier t WHERE t.UserId = s.UserId);

        UPDATE t SET PinHash = p.PinHash, AskPin = p.AskPin
        FROM dbo.zf_tb_Cashier t JOIN @Pins p ON p.UserId = t.UserId;

        UPDATE t SET PinHash = NULL
        FROM dbo.zf_tb_Cashier t JOIN @Rows s ON s.UserId = t.UserId
        WHERE t.CanUseTill = 0 AND t.PinHash IS NOT NULL;

        UPDATE dbo.zf_tb_Config SET LastCashierSyncAt = @ServerTime WHERE Id = 1;
    COMMIT;
END
GO

-- One user by login name (any case), for sign-in. Second result set: how many users may sign in on this till
-- (0 = the cashier list was never downloaded - connect to the back office and press Reload).
CREATE PROCEDURE dbo.zf_sp_GetCashier
    @LoginName VARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT UserId, LoginName, UserName, RoleId, CanUseTill, PasswordHash, AskPin
    FROM dbo.zf_tb_Cashier WHERE LoginName = LTRIM(RTRIM(@LoginName));

    SELECT COUNT(*) AS TillUsers FROM dbo.zf_tb_Cashier WHERE CanUseTill = 1;
END
GO

-- The cashier admins: till users with a supervisor PIN (TillService checks the PIN typed against these hashes).
CREATE PROCEDURE dbo.zf_sp_GetSupervisorPins
AS
BEGIN
    SET NOCOUNT ON;
    SELECT UserId, LoginName, PinHash
    FROM dbo.zf_tb_Cashier
    WHERE CanUseTill = 1 AND PinHash IS NOT NULL;
END
GO

-- 4. the next cashier download brings every user (with the PINs set before this script)
UPDATE dbo.zf_tb_Config SET LastCashierSyncAt = NULL WHERE Id = 1;
GO

PRINT 'U028_Till_TillPin done.';
GO
