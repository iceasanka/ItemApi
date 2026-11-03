/* =============================================================================
   U044_Till_ZDateFirstBill.sql   (2026-11-03)
   Update for a till db (z_pos_fnt_db) that is ALREADY deployed. SQL Server 2008 R2 and newer.
   Safe to run again. No table or data change.

   What was wrong: a Z took its date (BusinessDate) when it OPENED. The day end closes the Z and the next one
   opens straight after, so a day end at night (2 Nov 21:12) gave the next Z the date 2 Nov although all its bills
   were made on 3 Nov. The back office Tills page and Day Reports then showed that Z under the wrong day.

   What changes:
     - zf_sp_OpenZ: the open Z with no bill yet takes today's date. zf_sp_OpenZ runs at sign-on, at every bill
       (SaveInvoice / refund / exchange) and at cash in / out, so the Z gets the date of the first one of those
       on a new day - at the latest the first bill. OpenedAt is not changed. A Z with bills keeps its date (a Z
       left open over midnight stays on the day it started selling).
   Same change in the full script: 02_FrontCashier_zf.sql.
   Old Zs already dated wrong: DataFixes/F003_Till_ZDateFirstBill.sql + F003_BackOffice_ZDateFirstBill.sql.

   Order, on each till (any time; no TillService / billing page change):
     sqlcmd -S .\SQLEXPRESS -d z_pos_fnt_db -E -I -b -i U044_Till_ZDateFirstBill.sql
   ============================================================================= */
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
IF OBJECT_ID(N'dbo.zf_tb_ZReport', 'U') IS NULL OR OBJECT_ID(N'dbo.zf_tb_Invoice', 'U') IS NULL
BEGIN
    RAISERROR('This is not a till database (zf_tb_ZReport / zf_tb_Invoice not found) - nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
GO
IF OBJECT_ID(N'dbo.zf_sp_OpenZ', 'P') IS NOT NULL DROP PROCEDURE dbo.zf_sp_OpenZ;
GO
-- Returns the open Z, opening a new one if there is none (called at cashier sign-on and by SaveInvoice).
-- An open Z with no bill yet takes today's date (U044): the Z opened right after a day end at night is dated the
-- day it sells, not the night before. OpenedAt is not changed.
CREATE PROCEDURE dbo.zf_sp_OpenZ
    @CashierId VARCHAR(20) = NULL,
    @ZNo       INT = NULL OUTPUT,
    @Silent    BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRAN;
        SELECT @ZNo = ZNo FROM dbo.zf_tb_ZReport WITH (UPDLOCK, HOLDLOCK) WHERE Status = 0;

        IF @ZNo IS NOT NULL
            UPDATE dbo.zf_tb_ZReport SET BusinessDate = CAST(GETDATE() AS DATE)
            WHERE ZNo = @ZNo AND BusinessDate < CAST(GETDATE() AS DATE)
              AND NOT EXISTS (SELECT 1 FROM dbo.zf_tb_Invoice i WHERE i.ZNo = @ZNo);

        IF @ZNo IS NULL
        BEGIN
            SELECT @ZNo = ISNULL(MAX(ZNo), 0) + 1 FROM dbo.zf_tb_ZReport WITH (UPDLOCK, HOLDLOCK);
            INSERT dbo.zf_tb_ZReport (ZNo, BusinessDate, CashierId, OpenedAt, Status)
            VALUES (@ZNo, CAST(GETDATE() AS DATE), @CashierId, GETDATE(), 0);
        END
    COMMIT;

    IF @Silent = 0
        SELECT ZNo, BusinessDate, CashierId, OpenedAt, Status FROM dbo.zf_tb_ZReport WHERE ZNo = @ZNo;
END
GO
SET NOEXEC OFF;
GO
PRINT 'U044 till: an open Z with no bill yet takes today''s date (zf_sp_OpenZ).';
GO
