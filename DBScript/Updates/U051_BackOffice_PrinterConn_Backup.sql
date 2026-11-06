/* =============================================================================
   U051_BackOffice_PrinterConn_Backup.sql   (2026-11-06)
   Update for a back office db (easyway) that is ALREADY deployed. SQL Server 2008 R2 and newer. Safe to run again.

   What changes:
     1. Settings > Printers: the bill and sticker printers can be a Windows printer, a COM port (Epson TM Virtual Port
        Driver / serial cable) or a network printer (ip:port), as on the till. New z_tb_Setting rows (group "Printers"):
        Printer.BillConn / BillPort / BillAddress / BillBaud and Printer.StickerConn / StickerPort / StickerAddress /
        StickerBaud. Not set = Windows printer (as before: nothing changes for a printer already chosen).
        Printer.BillWidth also gets "80 mm (42 characters)".
     2. Settings > Backup: a full backup of the back office database every day at 11 PM (while the server is on), one file per
        database overwritten every day (<folder>\easyway_daily.bak). New z_tb_Setting rows (group "Backup"):
        Backup.Enabled (on), Backup.Time (23:00), Backup.Folder (empty = D:\IRMBackup).
        New table z_tb_DbBackup: every backup try (ok / failed, file, size, who), kept 90 days.
     3. z_fn_SettingValueOk knows the value type 'folder' (a folder path, 3 to 200 letters).
   Needs U023 (settings) and U050 (printers). Same as the full script: 31_BackOffice_PrinterConn_Backup.sql.

   Run:  sqlcmd -S <server> -d easyway -E -I -b -i U051_BackOffice_PrinterConn_Backup.sql
   Then: the new ItemApi and the back office UI. The first backup is at 11 PM the same day (or Settings > Backup >
         Back up now). The ItemApi's SQL login needs the right to back up (db_backupoperator, or sysadmin), and the
         SQL Server service account needs write access to the backup folder.
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
   OR NOT EXISTS (SELECT 1 FROM dbo.z_tb_Setting WHERE SettingKey = 'Printer.Bill')
BEGIN
    RAISERROR('The settings (U023) and the printers (U050) are not in this database - run them first. Nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
GO

-- 1. the value check knows 'folder' (U051)
IF OBJECT_ID(N'dbo.z_fn_SettingValueOk', 'FN') IS NOT NULL DROP FUNCTION dbo.z_fn_SettingValueOk;
GO
-- 1 when @Value is allowed for the setting: bool '0' / '1', choice one of its Options, number 0 or more (U038 loyalty),
-- printer a name of 1 to 100 letters (U050), folder a path of 3 to 200 letters (U051, ItemApi checks the form)
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
                      ELSE 0 END
    FROM dbo.z_tb_Setting WHERE SettingKey = @SettingKey;
    RETURN @ok;
END
GO

-- 2. the settings (label, help, choices and default set again on every run; the chosen values are kept)
DECLARE @s TABLE (SettingKey VARCHAR(50), GroupName NVARCHAR(30), Label NVARCHAR(100), Descrip NVARCHAR(400), Scope INT,
                  ValueType VARCHAR(10), Options NVARCHAR(400), DefaultValue NVARCHAR(200), SortOrder INT);
INSERT @s VALUES
 ('Printer.BillConn', N'Printers', N'Bill printer: connection',
  N'How the bill printer is connected to the server: a Windows printer, a COM port (Epson TM Virtual Port Driver or a serial cable) or the network (ip:port). COM port / network: ESC/POS.',
  1, 'choice', N'1=Windows printer|2=COM port|3=Network', N'1', 11),
 ('Printer.BillPort', N'Printers', N'Bill printer: COM port', N'COM port of the bill printer, e.g. COM3.', 1, 'printer', NULL, N'', 12),
 ('Printer.BillAddress', N'Printers', N'Bill printer: network address', N'Address of the network bill printer, e.g. 192.168.1.50:9100.', 1, 'printer', NULL, N'', 13),
 ('Printer.BillBaud', N'Printers', N'Bill printer: baud rate', N'COM port speed. Only matters on a real serial cable (the Epson virtual port ignores it).',
  1, 'choice', N'9600=9600|19200=19200|38400=38400|57600=57600|115200=115200', N'38400', 14),
 ('Printer.BillWidth', N'Printers', N'Bill printer: paper',
  N'The width of the bill printer''s paper roll.',
  1, 'choice', N'48=80 mm (48 characters a line)|42=80 mm (42 characters a line)|32=58 mm (32 characters a line)', N'48', 30),
 ('Printer.StickerConn', N'Printers', N'Sticker printer: connection',
  N'How the sticker printer is connected to the server: a Windows printer, a COM port or the network (ip:port).',
  1, 'choice', N'1=Windows printer|2=COM port|3=Network', N'1', 51),
 ('Printer.StickerPort', N'Printers', N'Sticker printer: COM port', N'COM port of the sticker printer, e.g. COM4.', 1, 'printer', NULL, N'', 52),
 ('Printer.StickerAddress', N'Printers', N'Sticker printer: network address', N'Address of the network sticker printer, e.g. 192.168.1.60:9100.', 1, 'printer', NULL, N'', 53),
 ('Printer.StickerBaud', N'Printers', N'Sticker printer: baud rate', N'COM port speed (must match the printer on a serial cable).',
  1, 'choice', N'9600=9600|19200=19200|38400=38400|57600=57600|115200=115200', N'38400', 54),
 ('Backup.Enabled', N'Backup', N'Daily backup',
  N'A full backup of the back office database (easyway) every day at the time below, while the server is on. One file, overwritten every day. Each till backs up its own database.',
  1, 'bool', NULL, N'1', 10),
 ('Backup.Time', N'Backup', N'Backup time',
  N'When the daily backup runs. If the server is off at that time there is no backup that day.',
  1, 'choice', N'18:00=6:00 PM|19:00=7:00 PM|20:00=8:00 PM|21:00=9:00 PM|22:00=10:00 PM|23:00=11:00 PM|23:30=11:30 PM', N'23:00', 20),
 ('Backup.Folder', N'Backup', N'Backup folder',
  N'A folder on the SQL Server computer. Empty = D:\IRMBackup. Copy the file to a pen drive / another PC now and then.',
  1, 'folder', NULL, N'', 30);

UPDATE t SET GroupName = s.GroupName, Label = s.Label, Descrip = s.Descrip, Scope = s.Scope, ValueType = s.ValueType,
             Options = s.Options, DefaultValue = s.DefaultValue, SortOrder = s.SortOrder
FROM dbo.z_tb_Setting t JOIN @s s ON s.SettingKey = t.SettingKey;

INSERT dbo.z_tb_Setting (SettingKey, GroupName, Label, Descrip, Scope, ValueType, Options, DefaultValue, SortOrder)
SELECT SettingKey, GroupName, Label, Descrip, Scope, ValueType, Options, DefaultValue, SortOrder
FROM @s s WHERE NOT EXISTS (SELECT 1 FROM dbo.z_tb_Setting t WHERE t.SettingKey = s.SettingKey);
GO

-- 3. every backup try (ItemApi DbBackupService). Ok NULL = running (or ItemApi stopped during it).
IF OBJECT_ID(N'dbo.z_tb_DbBackup', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.z_tb_DbBackup (
        BackupId    INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_z_tb_DbBackup PRIMARY KEY,
        DbName      NVARCHAR(128)  NOT NULL,
        FileName    NVARCHAR(400)  NULL,
        StartedAt   DATETIME       NOT NULL CONSTRAINT DF_z_tb_DbBackup_StartedAt DEFAULT (GETDATE()),
        FinishedAt  DATETIME       NULL,
        SizeBytes   BIGINT         NULL,
        Ok          BIT            NULL,
        Message     NVARCHAR(1000) NULL,
        Manual      BIT            NOT NULL CONSTRAINT DF_z_tb_DbBackup_Manual DEFAULT (0),
        UserId      INT            NULL
    );
    CREATE INDEX IX_z_tb_DbBackup_StartedAt ON dbo.z_tb_DbBackup (StartedAt);
END
GO

SET NOEXEC OFF;
GO
