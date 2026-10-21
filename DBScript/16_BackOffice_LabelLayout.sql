/* =============================================================================
   16_BackOffice_LabelLayout.sql   (2026-10-16) - full script for a new install.
   Run on: back office db (easyway). SQL Server 2008 R2 and newer. Safe to run again.
   Needs: z_tb_Item. Then the new ItemApi.
   Deployed databases get the same file as DBScript/Updates/U010_BackOffice_LabelLayout.sql - change both together.

   Label printing without BarTender (StockSystem.md sections 6.20 and 6.21). The old pages (api/Util/printbarcode,
   printprice, printDiscountPrice, printitempricelandscape -> LocalPrintAgent -> BarTender) are not changed.
     z_tb_LabelLayout  one row per sticker roll / sheet: size of ONE label, how many across (LabelsAcross), how many
                       rows on one page (RowsPerPage: 1 for a roll), the gaps between labels, the margins, the printer
                       and what is printed. All sizes in mm. The page picks a layout when it prints.
       LabelKind 1 = barcode label: ZPL sent RAW to the Zebra (Dpi, BarcodeType, Darkness, PrinterAddress apply)
       LabelKind 2 = price label (shelf price): drawn by the server and printed through the Windows printer driver
                     (receipt printer, A4 laser ...) - Sinhala and English names, price, discount (Language, Rotate,
                     SinhalaFont, EnglishFont, FooterText apply)
   Adds one example layout of each kind when there is none - change them on the Label layouts page.
   ============================================================================= */
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
IF OBJECT_ID(N'dbo.z_tb_Item', 'U') IS NULL
BEGIN
    RAISERROR('This is not the back office database (z_tb_Item not found) - nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
GO

IF OBJECT_ID('dbo.z_tb_LabelLayout', 'U') IS NULL
CREATE TABLE dbo.z_tb_LabelLayout (
    LabelLayoutId    INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_z_tb_LabelLayout PRIMARY KEY,
    LabelKind        INT           NOT NULL CONSTRAINT DF_z_tb_LabelLayout_LabelKind DEFAULT (1),   -- 1 barcode (ZPL), 2 price (driver)
    Name             NVARCHAR(50)  NOT NULL,
    -- Windows printer name on the API server; NULL = AppSettings:PrinterZebra (kind 1) / AppSettings:PrinterName (kind 2).
    -- PrinterAddress (ip:9100, kind 1 only) is used when PrinterName is empty AND PrinterAddress is set.
    PrinterName      NVARCHAR(100) NULL,
    PrinterAddress   VARCHAR(50)   NULL,
    Dpi              INT           NOT NULL CONSTRAINT DF_z_tb_LabelLayout_Dpi DEFAULT (203),   -- 203, 300 or 600 (kind 1)
    LabelWidthMm     DECIMAL(6,2)  NOT NULL,     -- ONE label
    LabelHeightMm    DECIMAL(6,2)  NOT NULL,
    LabelsAcross     INT           NOT NULL CONSTRAINT DF_z_tb_LabelLayout_LabelsAcross DEFAULT (1),   -- labels across
    RowsPerPage      INT           NOT NULL CONSTRAINT DF_z_tb_LabelLayout_RowsPerPage DEFAULT (1),      -- rows per page (roll = 1)
    GapXMm           DECIMAL(6,2)  NOT NULL CONSTRAINT DF_z_tb_LabelLayout_GapX DEFAULT (0),      -- between columns
    GapYMm           DECIMAL(6,2)  NOT NULL CONSTRAINT DF_z_tb_LabelLayout_GapY DEFAULT (0),      -- between rows on a page
    MarginLeftMm     DECIMAL(6,2)  NOT NULL CONSTRAINT DF_z_tb_LabelLayout_MarginLeft DEFAULT (0),
    MarginTopMm      DECIMAL(6,2)  NOT NULL CONSTRAINT DF_z_tb_LabelLayout_MarginTop DEFAULT (0),
    BarcodeType      VARCHAR(10)   NOT NULL CONSTRAINT DF_z_tb_LabelLayout_BarcodeType DEFAULT ('AUTO'),   -- AUTO, CODE128, EAN13
    BarcodeHeightMm  DECIMAL(6,2)  NOT NULL CONSTRAINT DF_z_tb_LabelLayout_BarcodeHeight DEFAULT (0),     -- 0 = fit the label
    ShowName         BIT           NOT NULL CONSTRAINT DF_z_tb_LabelLayout_ShowName DEFAULT (1),
    ShowPrice        BIT           NOT NULL CONSTRAINT DF_z_tb_LabelLayout_ShowPrice DEFAULT (1),
    ShowItemCode     BIT           NOT NULL CONSTRAINT DF_z_tb_LabelLayout_ShowItemCode DEFAULT (0),
    ShowDates        BIT           NOT NULL CONSTRAINT DF_z_tb_LabelLayout_ShowDates DEFAULT (0),     -- MFD / EXP line (kind 1)
    Darkness         INT           NULL,         -- 0-30; NULL = the printer's own setting (kind 1)
    Language         INT           NOT NULL CONSTRAINT DF_z_tb_LabelLayout_Language DEFAULT (1),      -- kind 2: 1 English, 2 Sinhala, 3 both
    Rotate           BIT           NOT NULL CONSTRAINT DF_z_tb_LabelLayout_Rotate DEFAULT (0),        -- kind 2: label turned 90 deg (landscape)
    SinhalaFont      NVARCHAR(50)  NULL,         -- kind 2: NULL = Iskoola Pota
    EnglishFont      NVARCHAR(50)  NULL,         -- kind 2: NULL = Courier New (as the old BarTender labels)
    FooterText       NVARCHAR(100) NULL,         -- kind 2: a line on price labels without a discount (shop slogan)
    IsDefault        BIT           NOT NULL CONSTRAINT DF_z_tb_LabelLayout_IsDefault DEFAULT (0),     -- one per LabelKind
    Status           INT           NOT NULL CONSTRAINT DF_z_tb_LabelLayout_Status DEFAULT (1),        -- 1 active, 0 deleted
    UserId           INT           NULL,
    CDate            DATETIME      NOT NULL CONSTRAINT DF_z_tb_LabelLayout_CDate DEFAULT (GETDATE()),
    UDate            DATETIME      NOT NULL CONSTRAINT DF_z_tb_LabelLayout_UDate DEFAULT (GETDATE())
);
GO

-- a table made by the first version of this script (barcode labels only) gets the price label columns
IF COL_LENGTH('dbo.z_tb_LabelLayout', 'LabelKind') IS NULL
    ALTER TABLE dbo.z_tb_LabelLayout ADD LabelKind INT NOT NULL CONSTRAINT DF_z_tb_LabelLayout_LabelKind DEFAULT (1);
IF COL_LENGTH('dbo.z_tb_LabelLayout', 'Language') IS NULL
    ALTER TABLE dbo.z_tb_LabelLayout ADD Language INT NOT NULL CONSTRAINT DF_z_tb_LabelLayout_Language DEFAULT (1);
IF COL_LENGTH('dbo.z_tb_LabelLayout', 'Rotate') IS NULL
    ALTER TABLE dbo.z_tb_LabelLayout ADD Rotate BIT NOT NULL CONSTRAINT DF_z_tb_LabelLayout_Rotate DEFAULT (0);
IF COL_LENGTH('dbo.z_tb_LabelLayout', 'SinhalaFont') IS NULL
    ALTER TABLE dbo.z_tb_LabelLayout ADD SinhalaFont NVARCHAR(50) NULL;
IF COL_LENGTH('dbo.z_tb_LabelLayout', 'EnglishFont') IS NULL
    ALTER TABLE dbo.z_tb_LabelLayout ADD EnglishFont NVARCHAR(50) NULL;
IF COL_LENGTH('dbo.z_tb_LabelLayout', 'FooterText') IS NULL
    ALTER TABLE dbo.z_tb_LabelLayout ADD FooterText NVARCHAR(100) NULL;
GO

IF NOT EXISTS (SELECT 1 FROM dbo.z_tb_LabelLayout WHERE LabelKind = 1)
BEGIN
    INSERT INTO dbo.z_tb_LabelLayout (LabelKind, Name, Dpi, LabelWidthMm, LabelHeightMm, LabelsAcross, RowsPerPage,
                                      BarcodeType, ShowName, ShowPrice, ShowItemCode, ShowDates, IsDefault)
    VALUES (1, N'50 x 25 mm, 1 across', 203, 50, 25, 1, 1, 'AUTO', 1, 1, 0, 0, 1);
    PRINT 'Barcode label layout "50 x 25 mm, 1 across" added - change it on the Label layouts page.';
END
GO
-- the old BarTender price labels: 80 mm receipt printer (72 mm printable), about 25 mm high; landscape = turned
IF NOT EXISTS (SELECT 1 FROM dbo.z_tb_LabelLayout WHERE LabelKind = 2)
BEGIN
    INSERT INTO dbo.z_tb_LabelLayout (LabelKind, Name, LabelWidthMm, LabelHeightMm, LabelsAcross, RowsPerPage,
                                      ShowName, ShowPrice, ShowItemCode, Language, Rotate, IsDefault)
    VALUES (2, N'Price 72 x 25 mm', 72, 25, 1, 1, 1, 1, 1, 1, 0, 1);
    INSERT INTO dbo.z_tb_LabelLayout (LabelKind, Name, LabelWidthMm, LabelHeightMm, LabelsAcross, RowsPerPage,
                                      ShowName, ShowPrice, ShowItemCode, Language, Rotate, IsDefault)
    VALUES (2, N'Price landscape 72 x 100 mm', 72, 100, 1, 1, 1, 1, 1, 1, 1, 0);
    PRINT 'Price label layouts "Price 72 x 25 mm" and "Price landscape 72 x 100 mm" added - check them with Test print.';
END
GO
SELECT LabelLayoutId, LabelKind, Name, PrinterName, LabelWidthMm, LabelHeightMm, LabelsAcross, RowsPerPage, Language,
       Rotate, IsDefault, Status
FROM dbo.z_tb_LabelLayout
ORDER BY LabelKind, Name;
GO
SET NOEXEC OFF;
GO
