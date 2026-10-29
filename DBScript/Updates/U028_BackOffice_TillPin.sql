/* =============================================================================
   U028_BackOffice_TillPin.sql   (2026-10-29)
   Update for the back office db (easyway) that is ALREADY deployed. SQL Server 2008 R2 and newer.
   Safe to run again. No data is changed (two new columns; every user keeps being asked the PIN).

   What changes (supervisor PIN from the users, Docs/StockSystem.md 6.12):
     - z_tb_User.TillPinHash: the user's supervisor PIN (cashier admin). Set on the Users page, kept as a PBKDF2 hash
       made by ItemApi (like the password); SQL never sees a PIN. NULL = this user can't approve at the till.
     - z_tb_User.TillAskPin: 1 = the till asks the supervisor PIN when this user is signed in (refund, discount,
       wholesale ...), 0 = it does not ask (the till lets the action through). New and old users: 1.
     - z_sp_GetCashiersForSync also sends TillPinHash (active Admin / Cashier users only) and TillAskPin, so the
       tills check the PIN against the cashier admins instead of Till:SupervisorPin in appsettings.
   Same change in the full script: 07_BackOffice_Users.sql.

   Order: this script, then the new ItemApi (the old ItemApi keeps working after it), then the back office UI
   (Users page). Then on each till U028_Till_TillPin.sql and the new TillService / billing page.
   ============================================================================= */
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
IF OBJECT_ID(N'dbo.z_tb_User', 'U') IS NULL OR OBJECT_ID(N'dbo.z_tb_Terminal', 'U') IS NULL
BEGIN
    RAISERROR('This is not the back office database (z_tb_User / z_tb_Terminal not found) - nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
GO

-- 1. columns
IF COL_LENGTH('dbo.z_tb_User', 'TillPinHash') IS NULL
    ALTER TABLE dbo.z_tb_User ADD TillPinHash VARCHAR(255) NULL;
IF COL_LENGTH('dbo.z_tb_User', 'TillAskPin') IS NULL
    ALTER TABLE dbo.z_tb_User ADD TillAskPin BIT NOT NULL CONSTRAINT DF_z_tb_User_TillAskPin DEFAULT (1);
GO

-- 2. till download
IF OBJECT_ID('dbo.z_sp_GetCashiersForSync', 'P') IS NOT NULL DROP PROCEDURE dbo.z_sp_GetCashiersForSync;
GO
-- Users for a till's offline sign-in, changed since @Since (NULL = all). Every changed user comes down, so a user who
-- is disabled or moved to "Back office" stops working on the till too (CanUseTill 0, no hash / PIN sent).
CREATE PROCEDURE dbo.z_sp_GetCashiersForSync
    @TerminalId INT,
    @Since      DATETIME = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.z_tb_Terminal WHERE TerminalId = @TerminalId AND Status = 1)
    BEGIN
        RAISERROR(N'%s', 16, 1, N'Terminal is not registered or is disabled.');
        RETURN 1;
    END

    SELECT u.UserId, u.LoginName, u.UserName, u.RoleId,
           CAST(CASE WHEN u.Status = 1 AND u.RoleId IN (1, 3) THEN 1 ELSE 0 END AS BIT) AS CanUseTill,
           CASE WHEN u.Status = 1 AND u.RoleId IN (1, 3) THEN u.PasswordHash END       AS PasswordHash,
           u.UpdatedDate,
           CASE WHEN u.Status = 1 AND u.RoleId IN (1, 3) THEN u.TillPinHash END        AS TillPinHash,
           u.TillAskPin
    FROM dbo.z_tb_User u
    WHERE u.LoginName IS NOT NULL
      AND (@Since IS NULL OR u.UpdatedDate > @Since);
END
GO

PRINT 'U028_BackOffice_TillPin done.';
GO
