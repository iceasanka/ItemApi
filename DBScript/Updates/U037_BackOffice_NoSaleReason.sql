/* =============================================================================
   U037_BackOffice_NoSaleReason.sql   (2026-11-02)
   Update for a back office db (easyway) that is ALREADY deployed. SQL Server 2008 R2 and newer.
   Safe to run again. Needs U023 (settings). No table change; values set by an admin are kept.

   What changes:
     - setting Till.NoSaleReason (per user, bool, default On = as before): On, No Sale on the till asks the reason
       before the drawer opens; Off, the drawer opens straight away (still logged in the drawer log, no reason).
       Set for everyone or for one user on Settings > System settings, any time; the tills pick it up with the
       next settings download.
   Same change in the full script: 24_BackOffice_Settings.sql.

   Run:  sqlcmd -S <server> -d easyway -E -I -b -i U037_BackOffice_NoSaleReason.sql
   Then: the new billing page on each till (no ItemApi / TillService / till db change).
   ============================================================================= */
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
IF OBJECT_ID(N'dbo.z_tb_Setting', 'U') IS NULL
BEGIN
    RAISERROR('This is not a back office database with U023 (z_tb_Setting not found) - nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
GO

DECLARE @s TABLE (SettingKey VARCHAR(50), GroupName NVARCHAR(30), Label NVARCHAR(100), Descrip NVARCHAR(400), Scope INT,
                  ValueType VARCHAR(10), Options NVARCHAR(400), DefaultValue NVARCHAR(200), SortOrder INT);
INSERT @s VALUES
 ('Till.NoSaleReason', N'Till', N'No Sale: ask the reason',
  N'On: No Sale asks why the drawer is opened (Change, ...) before it opens. Off: No Sale opens the drawer straight away (still logged, with no reason).',
  2, 'bool', NULL, N'1', 30);

UPDATE t SET GroupName = s.GroupName, Label = s.Label, Descrip = s.Descrip, Scope = s.Scope, ValueType = s.ValueType,
             Options = s.Options, DefaultValue = s.DefaultValue, SortOrder = s.SortOrder
FROM dbo.z_tb_Setting t JOIN @s s ON s.SettingKey = t.SettingKey;

INSERT dbo.z_tb_Setting (SettingKey, GroupName, Label, Descrip, Scope, ValueType, Options, DefaultValue, SortOrder)
SELECT SettingKey, GroupName, Label, Descrip, Scope, ValueType, Options, DefaultValue, SortOrder
FROM @s s WHERE NOT EXISTS (SELECT 1 FROM dbo.z_tb_Setting t WHERE t.SettingKey = s.SettingKey);
GO

PRINT 'U037_BackOffice_NoSaleReason done.';
GO
