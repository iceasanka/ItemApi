/* =============================================================================
   U023_BackOffice_Settings.sql   (2026-10-27)
   Update for a back office db (easyway) that is ALREADY deployed. SQL Server 2008 R2 and newer.
   Safe to run again. No data is changed (two new tables; the two settings are added with their defaults, so
   nothing works differently until an admin changes them).

   What changes (Settings page, Docs/StockSystem.md 6.28):
     - table z_tb_Setting: the list of settings (label, group, type, choices, default) and the general value
     - table z_tb_UserSetting: a user's own value of a per-user setting (no row = the general value)
     - settings: Till.BillDiscSkipItemDisc (general, off) - the bill discount leaves out items with an item discount;
       Till.ProfitView (per user, "Shown, PIN needed") - the profit button on the till: hidden / PIN / no PIN
     - function z_fn_SettingValueOk, procedures z_sp_GetSettings, z_sp_SetSetting, z_sp_GetUserSettingValues,
       z_sp_SetUserSetting (api/Settings), z_sp_GetSettingsForSync (api/Sync/Settings, for the tills)
   Same change in the full script: 24_BackOffice_Settings.sql.

   Run:  sqlcmd -S <server> -d easyway -E -I -b -i U023_BackOffice_Settings.sql
   Then: the new ItemApi and back office UI (Settings page), then U023_Till_Settings.sql, the new TillService and the
         new billing page on each till.
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

-- 1. tables
-- Scope 1 = general only, 2 = general + a user's own value. ValueType 'bool' ('0' / '1') or 'choice'
-- (Options = '<value>=<label>|<value>=<label>...').
IF OBJECT_ID('dbo.z_tb_Setting', 'U') IS NULL
CREATE TABLE dbo.z_tb_Setting (
    SettingKey   VARCHAR(50)   NOT NULL CONSTRAINT PK_z_tb_Setting PRIMARY KEY,
    GroupName    NVARCHAR(30)  NOT NULL,       -- Till, Back office
    Label        NVARCHAR(100) NOT NULL,
    Descrip      NVARCHAR(400) NULL,
    Scope        INT           NOT NULL,
    ValueType    VARCHAR(10)   NOT NULL,
    Options      NVARCHAR(400) NULL,
    DefaultValue NVARCHAR(200) NOT NULL,
    Value        NVARCHAR(200) NULL,           -- the general value; NULL = DefaultValue
    SortOrder    INT           NOT NULL CONSTRAINT DF_z_tb_Setting_SortOrder DEFAULT (0),
    UpdatedAt    DATETIME      NULL,
    UpdatedBy    INT           NULL            -- z_tb_User.UserId
);
GO
IF OBJECT_ID('dbo.z_tb_UserSetting', 'U') IS NULL
CREATE TABLE dbo.z_tb_UserSetting (
    UserId     INT           NOT NULL,
    SettingKey VARCHAR(50)   NOT NULL,
    Value      NVARCHAR(200) NOT NULL,
    UpdatedAt  DATETIME      NOT NULL CONSTRAINT DF_z_tb_UserSetting_UpdatedAt DEFAULT (GETDATE()),
    UpdatedBy  INT           NULL,
    CONSTRAINT PK_z_tb_UserSetting PRIMARY KEY (UserId, SettingKey)
);
GO

-- 2. the settings (label, help text, choices and default are set again on every run; the values are kept)
DECLARE @s TABLE (SettingKey VARCHAR(50), GroupName NVARCHAR(30), Label NVARCHAR(100), Descrip NVARCHAR(400), Scope INT,
                  ValueType VARCHAR(10), Options NVARCHAR(400), DefaultValue NVARCHAR(200), SortOrder INT);
INSERT @s VALUES
 ('Till.BillDiscSkipItemDisc', N'Till', N'Bill discount: leave out items with an item discount',
  N'On: the bill discount % is worked out only on the items without an item discount (like NoDiscount items). Off: on every item except NoDiscount items.',
  1, 'bool', NULL, N'0', 10),
 ('Till.ProfitView', N'Till', N'Profit button',
  N'Hidden: no profit button. Shown, PIN needed: a supervisor PIN opens the profit view. Shown, no PIN: it opens without the PIN (owners, supervisors).',
  2, 'choice', N'0=Hidden|1=Shown, PIN needed|2=Shown, no PIN', N'1', 20);

UPDATE t SET GroupName = s.GroupName, Label = s.Label, Descrip = s.Descrip, Scope = s.Scope, ValueType = s.ValueType,
             Options = s.Options, DefaultValue = s.DefaultValue, SortOrder = s.SortOrder
FROM dbo.z_tb_Setting t JOIN @s s ON s.SettingKey = t.SettingKey;

INSERT dbo.z_tb_Setting (SettingKey, GroupName, Label, Descrip, Scope, ValueType, Options, DefaultValue, SortOrder)
SELECT SettingKey, GroupName, Label, Descrip, Scope, ValueType, Options, DefaultValue, SortOrder
FROM @s s WHERE NOT EXISTS (SELECT 1 FROM dbo.z_tb_Setting t WHERE t.SettingKey = s.SettingKey);
GO

-- 3. procedures
IF OBJECT_ID(N'dbo.z_sp_GetSettings', 'P')         IS NOT NULL DROP PROCEDURE dbo.z_sp_GetSettings;
IF OBJECT_ID(N'dbo.z_sp_SetSetting', 'P')          IS NOT NULL DROP PROCEDURE dbo.z_sp_SetSetting;
IF OBJECT_ID(N'dbo.z_sp_GetUserSettingValues', 'P') IS NOT NULL DROP PROCEDURE dbo.z_sp_GetUserSettingValues;
IF OBJECT_ID(N'dbo.z_sp_SetUserSetting', 'P')      IS NOT NULL DROP PROCEDURE dbo.z_sp_SetUserSetting;
IF OBJECT_ID(N'dbo.z_sp_GetSettingsForSync', 'P')  IS NOT NULL DROP PROCEDURE dbo.z_sp_GetSettingsForSync;
IF OBJECT_ID(N'dbo.z_fn_SettingValueOk', 'FN')     IS NOT NULL DROP FUNCTION dbo.z_fn_SettingValueOk;
GO
-- 1 when @Value is allowed for the setting: bool '0' / '1', choice one of its Options
CREATE FUNCTION dbo.z_fn_SettingValueOk (@SettingKey VARCHAR(50), @Value NVARCHAR(200))
RETURNS BIT
AS
BEGIN
    DECLARE @ok BIT; SET @ok = 0;
    SELECT @ok = CASE WHEN ValueType = 'bool' AND @Value IN (N'0', N'1') THEN 1
                      WHEN ValueType = 'choice' AND @Value <> N'' AND CHARINDEX(N'|' + @Value + N'=', N'|' + ISNULL(Options, N'')) > 0 THEN 1
                      ELSE 0 END
    FROM dbo.z_tb_Setting WHERE SettingKey = @SettingKey;
    RETURN @ok;
END
GO
-- Every setting with its general value (EffectiveValue = Value, else DefaultValue) and how many users have their own.
CREATE PROCEDURE dbo.z_sp_GetSettings
AS
BEGIN
    SET NOCOUNT ON;
    SELECT s.SettingKey, s.GroupName, s.Label, s.Descrip, s.Scope, s.ValueType, s.Options, s.DefaultValue, s.Value,
           COALESCE(s.Value, s.DefaultValue) AS EffectiveValue, s.UpdatedAt, u.UserName AS UpdatedByName,
           (SELECT COUNT(*) FROM dbo.z_tb_UserSetting us WHERE us.SettingKey = s.SettingKey) AS UserValues
    FROM dbo.z_tb_Setting s
    LEFT JOIN dbo.z_tb_User u ON u.UserId = s.UpdatedBy
    ORDER BY s.GroupName, s.SortOrder, s.SettingKey;
END
GO
-- The general value. @Value NULL = back to the default.
CREATE PROCEDURE dbo.z_sp_SetSetting
    @SettingKey VARCHAR(50),
    @Value      NVARCHAR(200) = NULL,
    @UpdatedBy  INT = NULL
AS
BEGIN
    DECLARE @z_tc INT; SET @z_tc = @@TRANCOUNT;   -- SQL 2008 R2 error handling (RAISERROR in TRY/CATCH)
    BEGIN TRY
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM dbo.z_tb_Setting WHERE SettingKey = @SettingKey)
        RAISERROR(N'%s', 16, 1, N'Setting not found.');
    IF @Value IS NOT NULL AND dbo.z_fn_SettingValueOk(@SettingKey, @Value) = 0
        RAISERROR(N'%s', 16, 1, N'This value is not allowed for the setting.');

    UPDATE dbo.z_tb_Setting SET Value = @Value, UpdatedAt = GETDATE(), UpdatedBy = @UpdatedBy WHERE SettingKey = @SettingKey;
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
-- Users' own values (all users, or one): UserId, SettingKey, Value, UpdatedAt, UpdatedByName.
CREATE PROCEDURE dbo.z_sp_GetUserSettingValues
    @UserId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT us.UserId, us.SettingKey, us.Value, us.UpdatedAt, u.UserName AS UpdatedByName
    FROM dbo.z_tb_UserSetting us
    LEFT JOIN dbo.z_tb_User u ON u.UserId = us.UpdatedBy
    WHERE @UserId IS NULL OR us.UserId = @UserId
    ORDER BY us.UserId, us.SettingKey;
END
GO
-- A user's own value of a Scope 2 setting. @Value NULL = remove it (the user gets the general value again).
CREATE PROCEDURE dbo.z_sp_SetUserSetting
    @UserId     INT,
    @SettingKey VARCHAR(50),
    @Value      NVARCHAR(200) = NULL,
    @UpdatedBy  INT = NULL
AS
BEGIN
    DECLARE @z_tc INT; SET @z_tc = @@TRANCOUNT;   -- SQL 2008 R2 error handling (RAISERROR in TRY/CATCH)
    BEGIN TRY
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF NOT EXISTS (SELECT 1 FROM dbo.z_tb_User WHERE UserId = @UserId)
        RAISERROR(N'%s', 16, 1, N'User not found.');
    IF NOT EXISTS (SELECT 1 FROM dbo.z_tb_Setting WHERE SettingKey = @SettingKey)
        RAISERROR(N'%s', 16, 1, N'Setting not found.');
    IF NOT EXISTS (SELECT 1 FROM dbo.z_tb_Setting WHERE SettingKey = @SettingKey AND Scope = 2)
        RAISERROR(N'%s', 16, 1, N'This setting is for the whole system - it has no value per user.');
    IF @Value IS NOT NULL AND dbo.z_fn_SettingValueOk(@SettingKey, @Value) = 0
        RAISERROR(N'%s', 16, 1, N'This value is not allowed for the setting.');

    BEGIN TRAN;
        IF @Value IS NULL
            DELETE dbo.z_tb_UserSetting WHERE UserId = @UserId AND SettingKey = @SettingKey;
        ELSE
        BEGIN
            UPDATE dbo.z_tb_UserSetting WITH (UPDLOCK, HOLDLOCK)
            SET Value = @Value, UpdatedAt = GETDATE(), UpdatedBy = @UpdatedBy
            WHERE UserId = @UserId AND SettingKey = @SettingKey;
            IF @@ROWCOUNT = 0
                INSERT dbo.z_tb_UserSetting (UserId, SettingKey, Value, UpdatedBy) VALUES (@UserId, @SettingKey, @Value, @UpdatedBy);
        END
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
-- For a till (api/Sync/Settings): the general values (LoginName NULL), then each user's own values (by login name -
-- bills keep the login name as CashierId). The whole list every time; the till replaces its copy.
CREATE PROCEDURE dbo.z_sp_GetSettingsForSync
AS
BEGIN
    SET NOCOUNT ON;
    SELECT CAST(NULL AS VARCHAR(50)) AS LoginName, s.SettingKey, COALESCE(s.Value, s.DefaultValue) AS Value
    FROM dbo.z_tb_Setting s
    UNION ALL
    SELECT u.LoginName, us.SettingKey, us.Value
    FROM dbo.z_tb_UserSetting us
    JOIN dbo.z_tb_User u    ON u.UserId = us.UserId AND u.LoginName IS NOT NULL
    JOIN dbo.z_tb_Setting s ON s.SettingKey = us.SettingKey AND s.Scope = 2;
END
GO
PRINT 'U023_BackOffice_Settings done.';
GO
