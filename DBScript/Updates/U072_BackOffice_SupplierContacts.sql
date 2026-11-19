/* =============================================================================
   U072_BackOffice_SupplierContacts.sql   (2026-11-19)
   Update for a back office db (easyway) that is ALREADY deployed. SQL Server 2008 R2 and newer.
   Safe to run again.

   Supplier page: three more contact fields on z_tb_Supplier (all NULL-able, old rows stay as they are):
     - RefPhone      the supplier's rep / ref phone number
     - AreaMgrPhone  the area manager's phone number
     - BrNo          the company business registration (BR) number
   Phone / Phone2 stay as they are (shown as "Company phone 1 / 2" on the page).
   Same change in the full script: 43_BackOffice_SupplierContacts.sql.
   Run it BEFORE the new ItemApi (the new ItemApi reads these columns).

   Run:  sqlcmd -S <server> -d easyway -E -I -b -i U072_BackOffice_SupplierContacts.sql
   ============================================================================= */
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
IF OBJECT_ID(N'dbo.z_tb_Supplier', 'U') IS NULL OR OBJECT_ID(N'dbo.z_tb_Setting', 'U') IS NULL
BEGIN
    RAISERROR('This is not a back office database of the new system (z_tb_Supplier / z_tb_Setting not found) - nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
GO

IF COL_LENGTH('dbo.z_tb_Supplier', 'RefPhone') IS NULL
BEGIN
    ALTER TABLE dbo.z_tb_Supplier ADD RefPhone VARCHAR(20) NULL;
    PRINT 'Added z_tb_Supplier.RefPhone';
END
IF COL_LENGTH('dbo.z_tb_Supplier', 'AreaMgrPhone') IS NULL
BEGIN
    ALTER TABLE dbo.z_tb_Supplier ADD AreaMgrPhone VARCHAR(20) NULL;
    PRINT 'Added z_tb_Supplier.AreaMgrPhone';
END
IF COL_LENGTH('dbo.z_tb_Supplier', 'BrNo') IS NULL
BEGIN
    ALTER TABLE dbo.z_tb_Supplier ADD BrNo VARCHAR(50) NULL;
    PRINT 'Added z_tb_Supplier.BrNo';
END
PRINT 'U072 done.';
GO
SET NOEXEC OFF;
GO
