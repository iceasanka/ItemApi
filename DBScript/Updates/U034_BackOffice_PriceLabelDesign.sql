/* =============================================================================
   U034_BackOffice_PriceLabelDesign.sql   (2026-10-30)
   Update for the back office db (easyway) that is ALREADY deployed. SQL Server 2008 R2 and newer.
   Safe to run again. No data is changed (one new column). Needs U010_BackOffice_LabelLayout.sql.

   What changes (price label designer, Docs/StockSystem.md 6.21):
     - z_tb_LabelLayout.DesignJson NVARCHAR(MAX) NULL: on a price layout, where each part of the label goes and how
       big its text is, set by drag and drop on the Label layouts page:
       [{ "k": "name", "x": 30, "y": 1, "w": 40, "h": 10, "size": 14, "align": "C", "bold": true, "italic": false,
          "font": "Arial" }, ...]   (font NULL = the layout's English font)
       k = code / name / name2 / price / save / now / footer; x, y, w, h in mm on the label (upright, before the
       landscape turn); size in pt (0 = as big as the box allows); align L / C / R.
       NULL = the parts are placed by themselves, as before.
   Same column in the full script: 16_BackOffice_LabelLayout.sql.

   Order: this script, then the new ItemApi (it reads DesignJson on every layout, so it needs this script; the old
   ItemApi keeps working after it), then the back office UI (Label layouts, Price labels).
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
IF OBJECT_ID(N'dbo.z_tb_LabelLayout', 'U') IS NULL OR COL_LENGTH('dbo.z_tb_LabelLayout', 'FooterText') IS NULL
BEGIN
    RAISERROR('Run U010_BackOffice_LabelLayout.sql first - nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
GO

IF COL_LENGTH('dbo.z_tb_LabelLayout', 'DesignJson') IS NULL
    ALTER TABLE dbo.z_tb_LabelLayout ADD DesignJson NVARCHAR(MAX) NULL;
GO

PRINT 'U034_BackOffice_PriceLabelDesign done.';
GO
