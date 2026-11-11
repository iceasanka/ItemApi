/* =============================================================================
   U055_Till_ZSettlement.sql   (2026-11-10)
   Update for a till db (z_pos_fnt_db) that is ALREADY deployed (U054 run). SQL Server 2008 R2 and newer.
   Safe to run again.

   What changes (cash slip from the back office Cash Management):
     - zf_tb_ZReport.SettlementId INT NULL: the cash slip (barcode CS-<till>-<id>) scanned on the day end screen - its
       counted cash is the Z's counted cash. Sent to the back office with the Z, which links the slip to the Z and puts
       its cash to bank in the cheque sheet (back office U055_BackOffice_CashSettlement.sql). NULL = typed by hand.
   The opening cash taken from a slip is a normal opening cash movement with the reason "Cash slip <id>" (no column).
   Same change in the full script: 02_FrontCashier_zf.sql.

   Order, on each till (after the back office U055):
     1. sqlcmd -S .\SQLEXPRESS -d z_pos_fnt_db -E -I -b -i U055_Till_ZSettlement.sql
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
IF COL_LENGTH('dbo.zf_tb_ZReport', 'SettlementId') IS NULL
    ALTER TABLE dbo.zf_tb_ZReport ADD SettlementId INT NULL;
GO
SET NOEXEC OFF;
GO
