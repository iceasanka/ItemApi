/* =============================================================================
   U054_Till_ZCountedCash.sql   (2026-11-09)
   Update for a till db (z_pos_fnt_db) that is ALREADY deployed (U014 run). SQL Server 2008 R2 and newer.
   Safe to run again.

   What changes (counted cash at day end):
     - zf_tb_ZReport.CountedCash DECIMAL(18,2) NULL: the drawer cash the cashier counted on the day end screen
       (it was only printed on the Z slip). NULL = not entered / Z closed before this script.
   The TillService saves it right after the Z is closed and sends it to the back office with the Z
   (back office U054_BackOffice_ZCountedCash.sql). No proc is changed.
   Same change in the full script: 02_FrontCashier_zf.sql.

   Order, on each till (after the back office U054):
     1. sqlcmd -S .\SQLEXPRESS -d z_pos_fnt_db -E -I -b -i U054_Till_ZCountedCash.sql
     2. the new TillService (the old one keeps working after the script - the column just stays empty)
   ============================================================================= */
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
IF OBJECT_ID(N'dbo.zf_tb_ZReport', 'U') IS NULL OR COL_LENGTH('dbo.zf_tb_ZReport', 'ItemDiscount') IS NULL
BEGIN
    RAISERROR('This is not a till database with U014 (zf_tb_ZReport.ItemDiscount not found) - nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
GO
IF COL_LENGTH('dbo.zf_tb_ZReport', 'CountedCash') IS NULL
    ALTER TABLE dbo.zf_tb_ZReport ADD CountedCash DECIMAL(18,2) NULL;
GO
SET NOEXEC OFF;
GO
