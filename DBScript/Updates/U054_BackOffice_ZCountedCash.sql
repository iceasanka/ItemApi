/* =============================================================================
   U054_BackOffice_ZCountedCash.sql   (2026-11-09)
   Update for a back office db (easyway) that is ALREADY deployed. SQL Server 2008 R2 and newer. Safe to run again.

   What changes (counted cash at day end):
     - z_tb_ZReport.CountedCash DECIMAL(18,2) NULL: the drawer cash the cashier counted at day end, sent by the till
       with the Z (till U054_Till_ZCountedCash.sql). NULL = not entered / older till.
   The ItemApi stores it after z_sp_SubmitZReport (no proc is changed) and puts the day's cash to bank
   (counted cash - opening cash, every Z of the day) in Avg_Cash of the cheque Google sheet.
   Same change in the full script: 01_BackOffice_Stock.sql.

   Run BEFORE the new ItemApi (the old ItemApi keeps working after it):
     sqlcmd -S <server> -d easyway -E -I -b -i U054_BackOffice_ZCountedCash.sql
   ============================================================================= */
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
IF OBJECT_ID(N'dbo.z_tb_ZReport', 'U') IS NULL
BEGIN
    RAISERROR('z_tb_ZReport is not in this database (run U003 first) - nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
GO
IF COL_LENGTH('dbo.z_tb_ZReport', 'CountedCash') IS NULL
    ALTER TABLE dbo.z_tb_ZReport ADD CountedCash DECIMAL(18,2) NULL;
GO
SET NOEXEC OFF;
GO
