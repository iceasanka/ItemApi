/* =============================================================================
   U050_BackOffice_Printers.sql   (2026-11-05)
   Update for a back office db (easyway) that is ALREADY deployed. SQL Server 2008 R2 and newer. Safe to run again.

   What changes (the printers move from ItemApi appsettings.json to Settings > Printers):
     - z_tb_Setting rows (group "Printers"): Printer.Bill (thermal / bill printer: Cash Management print + cash to bank,
       return slips, price labels), Printer.BillMode (Windows driver / ESC/POS), Printer.BillWidth (80 / 58 mm),
       Printer.General (normal printer: cheques), Printer.Sticker (Zebra: barcode labels). None chosen at first.
     - z_fn_SettingValueOk knows the new value type 'printer' (a printer name, 1 to 100 letters).
   Needs U023 (settings). Same as the full script: 30_BackOffice_Printers.sql.

   Run:  sqlcmd -S <server> -d easyway -E -I -b -i U050_BackOffice_Printers.sql
   Then: the new ItemApi and the back office UI, then Settings > Printers: choose the three printers (Test print).
         Until then nothing prints (the page says to choose the printer).
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
IF OBJECT_ID(N'dbo.z_tb_Setting', 'U') IS NULL OR OBJECT_ID(N'dbo.z_sp_SetSetting', 'P') IS NULL
BEGIN
    RAISERROR('The settings (U023 / 24_BackOffice_Settings.sql) are not in this database - nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
GO

-- 1. the value check knows 'printer': a Windows printer name, 1 to 100 letters (ItemApi checks it is installed)
IF OBJECT_ID(N'dbo.z_fn_SettingValueOk', 'FN') IS NOT NULL DROP FUNCTION dbo.z_fn_SettingValueOk;
GO
-- 1 when @Value is allowed for the setting: bool '0' / '1', choice one of its Options, number 0 or more (U038 loyalty),
-- printer a name of 1 to 100 letters (U050)
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
                      ELSE 0 END
    FROM dbo.z_tb_Setting WHERE SettingKey = @SettingKey;
    RETURN @ok;
END
GO

-- 2. the printers (label, help, choices and default set again on every run; the chosen values are kept).
--    No printer is chosen at first: choose them on Settings > Printers after the new ItemApi is deployed.
DECLARE @s TABLE (SettingKey VARCHAR(50), GroupName NVARCHAR(30), Label NVARCHAR(100), Descrip NVARCHAR(400), Scope INT,
                  ValueType VARCHAR(10), Options NVARCHAR(400), DefaultValue NVARCHAR(200), SortOrder INT);
INSERT @s VALUES
 ('Printer.Bill', N'Printers', N'Bill printer (thermal)',
  N'The thermal / receipt printer: Cash Management print and the cash to bank (settlement) slip, return item slips, price labels (when the label layout has no printer of its own). E.g. PegasusPR8003, or VirtualPOS_9100 to test.',
  1, 'printer', NULL, N'', 10),
 ('Printer.BillMode', N'Printers', N'Bill printer: how to print',
  N'Windows driver: a normal print through the printer''s own driver (works on every printer). ESC/POS: receipt printer commands sent straight to the printer (only for a printer that takes them).',
  1, 'choice', N'driver=Windows driver (normal)|escpos=ESC/POS commands', N'driver', 20),
 ('Printer.BillWidth', N'Printers', N'Bill printer: paper',
  N'The width of the bill printer''s paper roll.',
  1, 'choice', N'48=80 mm (48 characters a line)|32=58 mm (32 characters a line)', N'48', 30),
 ('Printer.General', N'Printers', N'General printer',
  N'A normal printer (e.g. the HP): cheques (Cheque Writer). Set the cheque layout on Cheque Writer > Cheque layout with a test print.',
  1, 'printer', NULL, N'', 40),
 ('Printer.Sticker', N'Printers', N'Sticker printer',
  N'The barcode sticker printer (Zebra): barcode labels, when the label layout has no printer of its own.',
  1, 'printer', NULL, N'', 50);

UPDATE t SET GroupName = s.GroupName, Label = s.Label, Descrip = s.Descrip, Scope = s.Scope, ValueType = s.ValueType,
             Options = s.Options, DefaultValue = s.DefaultValue, SortOrder = s.SortOrder
FROM dbo.z_tb_Setting t JOIN @s s ON s.SettingKey = t.SettingKey;

INSERT dbo.z_tb_Setting (SettingKey, GroupName, Label, Descrip, Scope, ValueType, Options, DefaultValue, SortOrder)
SELECT SettingKey, GroupName, Label, Descrip, Scope, ValueType, Options, DefaultValue, SortOrder
FROM @s s WHERE NOT EXISTS (SELECT 1 FROM dbo.z_tb_Setting t WHERE t.SettingKey = s.SettingKey);
GO

SET NOEXEC OFF;
GO
