/* =============================================================================
   39_BackOffice_GrnScanScanner.sql   (2026-11-16, U061)
   Full script for a back office db (easyway). SQL Server 2008 R2 and newer. Safe to run again.

   What changes (GRN Scan: scan on the page + smaller pages to Gemini):
     - z_tb_Setting rows (group "Scanner", Settings > Scanner):
         Scanner.Device      the scanner on the server where ItemApi runs (WIA device; none chosen at first)
         Scanner.Dpi         150 / 200 (default) / 300
         Scanner.Source      flatbed (one page a click, default) / feeder (every page in the document feeder)
         GrnScan.ImageSize   every page (scanned or a photo uploaded) is made down to this long side before Gemini:
                             1600 / 2000 / 2400 (default, = A4 at about 200 DPI) / 3200 / 0 = as it came
         GrnScan.ImageColor  color / gray (default) / bw
     - no new value type: Scanner.Device uses 'printer' (a name of 1 to 100 letters, U050).
   Needs U023 (settings) and U050 (value type 'printer'). Same as the update script: Updates/U061_BackOffice_GrnScanScanner.sql.

   Run:  sqlcmd -S <server> -d easyway -E -I -b -i 39_BackOffice_GrnScanScanner.sql
   Then: the new ItemApi and the back office UI, then Settings > Scanner: choose the scanner (Test scan).
         Without this script ItemApi uses the defaults (2400 px, gray) and the Scan button stays hidden.
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

-- label, help, choices and default set again on every run; the chosen values are kept
DECLARE @s TABLE (SettingKey VARCHAR(50), GroupName NVARCHAR(30), Label NVARCHAR(100), Descrip NVARCHAR(400), Scope INT,
                  ValueType VARCHAR(10), Options NVARCHAR(400), DefaultValue NVARCHAR(200), SortOrder INT);
INSERT @s VALUES
 ('Scanner.Device', N'Scanner', N'Scanner',
  N'The scanner (or multi-function printer) for GRN Scan, on the server where ItemApi runs. It must show in Windows "Scanners and Cameras" there.',
  1, 'printer', NULL, N'', 10),
 ('Scanner.Dpi', N'Scanner', N'Scan resolution',
  N'200 DPI reads every printed digit and keeps the scan small. 300 DPI only for very small print (the page is made small again before it is read).',
  1, 'choice', N'150=150 DPI (small, fast)|200=200 DPI (best for invoices)|300=300 DPI (very small print)', N'200', 20),
 ('Scanner.Source', N'Scanner', N'Scan from',
  N'Flatbed: one page each time Scan is clicked. Document feeder: every page put in the feeder (up to 4) in one go.',
  1, 'choice', N'flatbed=Flatbed (glass)|feeder=Document feeder (ADF)', N'flatbed', 30),
 ('GrnScan.ImageSize', N'Scanner', N'Page size sent to the AI',
  N'Every page - scanned or a photo uploaded - is made down to this size (the long side) before it is read. Bigger is not read better: the AI makes it smaller itself. Too big pages made a read of 3-4 pages fail.',
  1, 'choice', N'1600=1600 px (smallest)|2000=2000 px|2400=2400 px (best, A4 at about 200 DPI)|3200=3200 px (very small print)|0=As it came (not made smaller)', N'2400', 40),
 ('GrnScan.ImageColor', N'Scanner', N'Page colour sent to the AI',
  N'Grayscale reads as well as colour and is smaller. Black & white is the smallest, but faint or shaded print can disappear (phone photos) - only for clean scans.',
  1, 'choice', N'gray=Grayscale (best)|color=Colour|bw=Black & white (clean scans only)', N'gray', 50);

UPDATE t SET GroupName = s.GroupName, Label = s.Label, Descrip = s.Descrip, Scope = s.Scope, ValueType = s.ValueType,
             Options = s.Options, DefaultValue = s.DefaultValue, SortOrder = s.SortOrder
FROM dbo.z_tb_Setting t JOIN @s s ON s.SettingKey = t.SettingKey;

INSERT dbo.z_tb_Setting (SettingKey, GroupName, Label, Descrip, Scope, ValueType, Options, DefaultValue, SortOrder)
SELECT SettingKey, GroupName, Label, Descrip, Scope, ValueType, Options, DefaultValue, SortOrder
FROM @s s WHERE NOT EXISTS (SELECT 1 FROM dbo.z_tb_Setting t WHERE t.SettingKey = s.SettingKey);
GO

SET NOEXEC OFF;
GO
