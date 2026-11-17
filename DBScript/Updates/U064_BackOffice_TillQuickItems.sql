/* =============================================================================
   U064_BackOffice_TillQuickItems.sql   (2026-11-17)
   Update for a back office db (easyway) that is ALREADY deployed. SQL Server 2008 R2 and newer.
   Safe to run again. Needs U023 (settings) and U051. No table change; values set by an admin are kept.

   What changes (quick item buttons on the till, for all tills):
     - setting Till.QuickItems (general, value type 'list', default none): the item buttons next to Menu on every
       till - one a ref code, "code=text on the button|code=text|..." (at most 200 letters, 8 buttons). A click on
       the till adds the item as if its code was scanned (shopping bags Rs 5 / 3 / 2 ...). Set on Settings > Till
       (Quick item buttons); the tills pick it up with the next settings download (5 minutes, or Reload).
     - z_fn_SettingValueOk knows the value type 'list' (0 to 200 letters; the page builds the list).
   Same change in the full script: 42_BackOffice_TillQuickItems.sql.

   Run:  sqlcmd -S <server> -d easyway -E -I -b -i U064_BackOffice_TillQuickItems.sql
   Then: the new back office / billing pages (no ItemApi / TillService / till db change - the till takes every
         setting it is sent).
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

-- 1. the value check knows 'list' (U064)
IF OBJECT_ID(N'dbo.z_fn_SettingValueOk', 'FN') IS NOT NULL DROP FUNCTION dbo.z_fn_SettingValueOk;
GO
-- 1 when @Value is allowed for the setting: bool '0' / '1', choice one of its Options, number 0 or more (U038 loyalty),
-- printer a name of 1 to 100 letters (U050), folder a path of 3 to 200 letters (U051, ItemApi checks the form),
-- list a text of up to 200 letters built by its own editor on the Settings page (U064)
CREATE FUNCTION dbo.z_fn_SettingValueOk (@SettingKey VARCHAR(50), @Value NVARCHAR(200))
RETURNS BIT
AS
BEGIN
    DECLARE @ok BIT; SET @ok = 0;
    SELECT @ok = CASE WHEN ValueType = 'bool' AND @Value IN (N'0', N'1') THEN 1
                      WHEN ValueType = 'choice' AND @Value <> N'' AND CHARINDEX(N'|' + @Value + N'=', N'|' + ISNULL(Options, N'')) > 0 THEN 1
                      WHEN ValueType = 'number' AND @Value LIKE N'%[0-9]%' AND @Value NOT LIKE N'%[^0-9.]%'
                           AND LEN(@Value) - LEN(REPLACE(@Value, N'.', N'')) <= 1 AND LEN(@Value) <= 12
                           AND LEFT(@Value, 1) <> N'.' AND RIGHT(@Value, 1) <> N'.' THEN 1
                      WHEN ValueType = 'printer' AND LEN(LTRIM(RTRIM(@Value))) BETWEEN 1 AND 100 THEN 1
                      WHEN ValueType = 'folder' AND LEN(LTRIM(RTRIM(@Value))) BETWEEN 3 AND 200 THEN 1
                      WHEN ValueType = 'list' AND @Value IS NOT NULL AND LEN(@Value) <= 200 THEN 1
                      ELSE 0 END
    FROM dbo.z_tb_Setting WHERE SettingKey = @SettingKey;
    RETURN @ok;
END
GO

-- 2. the setting (label, help and default set again on every run; the chosen value is kept)
DECLARE @s TABLE (SettingKey VARCHAR(50), GroupName NVARCHAR(30), Label NVARCHAR(100), Descrip NVARCHAR(400), Scope INT,
                  ValueType VARCHAR(10), Options NVARCHAR(400), DefaultValue NVARCHAR(200), SortOrder INT);
INSERT @s VALUES
 ('Till.QuickItems', N'Till', N'Quick item buttons',
  N'Buttons next to Menu on every till, one item each by its ref code (e.g. shopping bags). A click adds the item as if its code was scanned; type 3* first for 3.',
  1, 'list', NULL, N'', 40);

UPDATE t SET GroupName = s.GroupName, Label = s.Label, Descrip = s.Descrip, Scope = s.Scope, ValueType = s.ValueType,
             Options = s.Options, DefaultValue = s.DefaultValue, SortOrder = s.SortOrder
FROM dbo.z_tb_Setting t JOIN @s s ON s.SettingKey = t.SettingKey;

INSERT dbo.z_tb_Setting (SettingKey, GroupName, Label, Descrip, Scope, ValueType, Options, DefaultValue, SortOrder)
SELECT SettingKey, GroupName, Label, Descrip, Scope, ValueType, Options, DefaultValue, SortOrder
FROM @s s WHERE NOT EXISTS (SELECT 1 FROM dbo.z_tb_Setting t WHERE t.SettingKey = s.SettingKey);
GO

SET NOEXEC OFF;
GO
PRINT 'U064_BackOffice_TillQuickItems done: Till.QuickItems, value type list.';
GO
