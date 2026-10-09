/* =============================================================================
   07_BackOffice_Users.sql
   Run on: back office db (easyway), AFTER 01_BackOffice_Stock.sql. Prefix z_. Re-runnable.
   Users and sign-in for the back office web app AND the cashier tills. Docs/StockSystem.md §6.12.
   API: api/Auth (AuthController), api/Users (UsersController), api/Sync/Cashiers (tills).

   One user list, kept here. Role decides where a user can sign in:
     1 Admin       back office + manage users + tills
     2 Back office back office only
     3 Cashier     tills only
   Status 1 active, 0 disabled (users are never deleted — bills keep the cashier's LoginName as CashierId).
   PasswordHash = "PBKDF2$<iterations>$<salt>$<hash>" (SHA-256), made by ItemApi (Common/PasswordHasher.cs). SQL never
   sees a password. The first admin is made from the sign-in page (api/Auth/Setup) — only while there is no admin.
   Tills download Admin + Cashier users (with the hash) so a cashier can sign in while the till is offline.
   easyway is at compatibility level 100 (SQL 2008): no IIF / FORMAT / CONCAT.
   ============================================================================= */
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.z_tb_Role', 'U') IS NULL
CREATE TABLE dbo.z_tb_Role (
    RoleId    INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    RoleName  VARCHAR(50) NOT NULL,
    Status    INT         NOT NULL DEFAULT 1
);
GO

SET IDENTITY_INSERT dbo.z_tb_Role ON;
IF NOT EXISTS (SELECT 1 FROM dbo.z_tb_Role WHERE RoleId = 1) INSERT dbo.z_tb_Role (RoleId, RoleName, Status) VALUES (1, 'Admin', 1);
IF NOT EXISTS (SELECT 1 FROM dbo.z_tb_Role WHERE RoleId = 2) INSERT dbo.z_tb_Role (RoleId, RoleName, Status) VALUES (2, 'Back office', 1);
IF NOT EXISTS (SELECT 1 FROM dbo.z_tb_Role WHERE RoleId = 3) INSERT dbo.z_tb_Role (RoleId, RoleName, Status) VALUES (3, 'Cashier', 1);
SET IDENTITY_INSERT dbo.z_tb_Role OFF;
GO

-- Same shape as the z_tb_User already on easyway (made before this script), plus the sign-in columns below.
-- UserCode is unique, so it is always filled (= LoginName).
IF OBJECT_ID('dbo.z_tb_User', 'U') IS NULL
CREATE TABLE dbo.z_tb_User (
    UserId        INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    UserCode      VARCHAR(20)  NULL UNIQUE,
    UserName      VARCHAR(100) NULL,
    LoginName     VARCHAR(50)  NULL UNIQUE,
    PasswordHash  VARCHAR(255) NULL,
    Email         VARCHAR(150) NULL,
    Phone         VARCHAR(20)  NULL,
    RoleId        INT          NULL,
    Status        INT          NULL,
    CreatedDate   DATETIME     NULL,
    CreatedBy     INT          NULL,
    UpdatedDate   DATETIME     NULL,
    UpdatedBy     INT          NULL
);
GO

IF COL_LENGTH('dbo.z_tb_User', 'LastLoginAt') IS NULL
    ALTER TABLE dbo.z_tb_User ADD LastLoginAt DATETIME NULL;
IF COL_LENGTH('dbo.z_tb_User', 'FailedLogins') IS NULL
    ALTER TABLE dbo.z_tb_User ADD FailedLogins INT NOT NULL CONSTRAINT DF_z_tb_User_FailedLogins DEFAULT (0);
IF COL_LENGTH('dbo.z_tb_User', 'LockedUntil') IS NULL
    ALTER TABLE dbo.z_tb_User ADD LockedUntil DATETIME NULL;   -- 5 wrong passwords → locked 5 minutes
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_z_tb_User_UpdatedDate')
    CREATE INDEX IX_z_tb_User_UpdatedDate ON dbo.z_tb_User (UpdatedDate);
GO

IF OBJECT_ID('dbo.z_sp_GetCashiersForSync', 'P') IS NOT NULL DROP PROCEDURE dbo.z_sp_GetCashiersForSync;
GO

-- Users for a till's offline sign-in, changed since @Since (NULL = all). Every changed user comes down, so a user who
-- is disabled or moved to "Back office" stops working on the till too (CanUseTill 0, no hash sent).
CREATE PROCEDURE dbo.z_sp_GetCashiersForSync
    @TerminalId INT,
    @Since      DATETIME = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.z_tb_Terminal WHERE TerminalId = @TerminalId AND Status = 1)
        THROW 50021, 'Terminal is not registered or is disabled.', 1;

    SELECT u.UserId, u.LoginName, u.UserName, u.RoleId,
           CAST(CASE WHEN u.Status = 1 AND u.RoleId IN (1, 3) THEN 1 ELSE 0 END AS BIT) AS CanUseTill,
           CASE WHEN u.Status = 1 AND u.RoleId IN (1, 3) THEN u.PasswordHash END       AS PasswordHash,
           u.UpdatedDate
    FROM dbo.z_tb_User u
    WHERE u.LoginName IS NOT NULL
      AND (@Since IS NULL OR u.UpdatedDate > @Since);
END
GO
