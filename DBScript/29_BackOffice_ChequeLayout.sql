/* =============================================================================
   29_BackOffice_ChequeLayout.sql   (2026-11-05)
   Full script (new install or an existing back office db). SQL Server 2008 R2 and newer. Safe to run again.

   Cheque printing without BarTender (StockSystem.md section 6.36): ItemApi draws the cheque itself on the cheque
   printer (AppSettings:PrinterHP). z_tb_ChequeLayout keeps where each part prints, set on Cheque Writer > Cheque layout.
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
IF OBJECT_ID(N'dbo.z_tb_WrittenCheque', 'U') IS NULL
BEGIN
    RAISERROR('This is not the back office database (z_tb_WrittenCheque not found) - nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
GO

-- where each part of the cheque prints (positions in mm, page size, printer shift). One row; no row = the
-- defaults in ItemApi (Models/ChequeLayout.cs, measured from the old BarTender ChqPrint.btw).
IF OBJECT_ID(N'dbo.z_tb_ChequeLayout', 'U') IS NULL
CREATE TABLE dbo.z_tb_ChequeLayout (
    LayoutId        INT           NOT NULL CONSTRAINT PK_z_tb_ChequeLayout PRIMARY KEY,   -- always 1
    LayoutJson      NVARCHAR(MAX) NOT NULL,
    PrevLayoutJson  NVARCHAR(MAX) NULL,         -- the layout before the last save (undo)
    UpdatedAt       DATETIME      NOT NULL CONSTRAINT DF_z_tb_ChequeLayout_UpdatedAt DEFAULT (GETDATE()),
    UpdatedBy       NVARCHAR(50)  NULL
);
GO

SET NOEXEC OFF;
GO
