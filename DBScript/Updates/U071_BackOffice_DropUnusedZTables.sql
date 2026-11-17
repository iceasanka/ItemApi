/* =============================================================================
   U071_BackOffice_DropUnusedZTables.sql   (2026-11-17)
   Update for a back office db (easyway) that is ALREADY deployed. SQL Server 2008 R2 and newer.
   Safe to run again.

   Old-system clean-up, extra step: drops three z_ tables nothing uses since the old routes were removed
   (new ItemApi of 2026-11-17) - WITH their rows (in the backup):
     - z_tb_ReturnItem       the old return list (api/Return; replaced by z_tb_ReturnList, U016)
     - z_tb_GrnTemp          the old phone GRN (api/GrnTemp; replaced by the mobile GRN, U017)
     - z_tb_PosCountedStock  the old phone stock count (api/PosCountedStock)
   No proc, function, foreign key or app code uses them.
   Before: a full backup of the db. Needs the new ItemApi of 2026-11-17 (the old one still has those routes).

   Run:  sqlcmd -S <server> -d easyway -E -I -b -i U071_BackOffice_DropUnusedZTables.sql
   ============================================================================= */
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
IF OBJECT_ID(N'dbo.z_tb_Setting', 'U') IS NULL OR OBJECT_ID(N'dbo.z_tb_Item', 'U') IS NULL
BEGIN
    RAISERROR('This is not a back office database of the new system (z_tb_Setting / z_tb_Item not found) - nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
GO

IF OBJECT_ID(N'dbo.z_tb_ReturnItem', 'U') IS NOT NULL
BEGIN
    DROP TABLE dbo.z_tb_ReturnItem;
    PRINT 'Dropped z_tb_ReturnItem';
END
IF OBJECT_ID(N'dbo.z_tb_GrnTemp', 'U') IS NOT NULL
BEGIN
    DROP TABLE dbo.z_tb_GrnTemp;
    PRINT 'Dropped z_tb_GrnTemp';
END
IF OBJECT_ID(N'dbo.z_tb_PosCountedStock', 'U') IS NOT NULL
BEGIN
    DROP TABLE dbo.z_tb_PosCountedStock;
    PRINT 'Dropped z_tb_PosCountedStock';
END
PRINT 'U071 done.';
GO
SET NOEXEC OFF;
GO
