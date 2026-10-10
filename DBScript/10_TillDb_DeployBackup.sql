/* =============================================================================
   10_TillDb_DeployBackup.sql
   Makes an EMPTY till database backup to install on new till PCs. The dev till db is NOT changed:
     1. safety backup of z_pos_fnt_db              -> z_pos_fnt_db_beforeDeploy_<date>.bak
     2. restore it as z_pos_fnt_db_deploy, empty every zf_ table there (bills, Z, cash, suspended, drawer log,
        items, price links, stock, cashiers, config) and reset the id counters
     3. backup the empty copy                       -> z_pos_fnt_db_deploy_<date>.bak, then drop the copy
   Run on master:  sqlcmd -S PRASADA1 -E -C -b -i 10_TillDb_DeployBackup.sql
   On the till after restoring: EXEC dbo.zf_sp_SetupTerminal 2, 'T02', 1, 'http://<backoffice>:5000/api/';
   then the service downloads items, prices, stock and cashiers on its first sync.
   The .bak restores only on the SAME or NEWER SQL Server version (this one is SQL 2022). For an older SQL Express
   on the till, create the db with 02_FrontCashier_zf.sql instead.
   ============================================================================= */
SET NOCOUNT ON;
SET XACT_ABORT ON;
USE master;

DECLARE @Folder NVARCHAR(400) = CAST(SERVERPROPERTY('InstanceDefaultBackupPath') AS NVARCHAR(400)) + N'\';
DECLARE @DataFolder NVARCHAR(400) = CAST(SERVERPROPERTY('InstanceDefaultDataPath') AS NVARCHAR(400));
DECLARE @Stamp NVARCHAR(20) = FORMAT(GETDATE(), 'yyyyMMdd_HHmm');
DECLARE @Safety NVARCHAR(500) = @Folder + N'z_pos_fnt_db_beforeDeploy_' + @Stamp + N'.bak';
DECLARE @Deploy NVARCHAR(500) = @Folder + N'z_pos_fnt_db_deploy_' + @Stamp + N'.bak';
DECLARE @Mdf NVARCHAR(500) = @DataFolder + N'z_pos_fnt_db_deploy.mdf';
DECLARE @Ldf NVARCHAR(500) = @DataFolder + N'z_pos_fnt_db_deploy_log.ldf';

-- 1. safety backup (COPY_ONLY: does not disturb any other backup plan)
BACKUP DATABASE z_pos_fnt_db TO DISK = @Safety WITH COPY_ONLY, INIT, CHECKSUM;
PRINT 'Safety backup: ' + @Safety;

-- 2. temporary copy
IF DB_ID('z_pos_fnt_db_deploy') IS NOT NULL
BEGIN
    ALTER DATABASE z_pos_fnt_db_deploy SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE z_pos_fnt_db_deploy;
END
RESTORE DATABASE z_pos_fnt_db_deploy FROM DISK = @Safety
WITH MOVE 'z_pos_fnt_db' TO @Mdf, MOVE 'z_pos_fnt_db_log' TO @Ldf, RECOVERY;

EXEC (N'USE z_pos_fnt_db_deploy;
BEGIN TRAN;
TRUNCATE TABLE dbo.zf_tb_InvoicePayment;
TRUNCATE TABLE dbo.zf_tb_InvoiceItem;
TRUNCATE TABLE dbo.zf_tb_Invoice;
TRUNCATE TABLE dbo.zf_tb_ZReportItem;
TRUNCATE TABLE dbo.zf_tb_ZReport;
TRUNCATE TABLE dbo.zf_tb_CashMovement;
TRUNCATE TABLE dbo.zf_tb_DrawerLog;
TRUNCATE TABLE dbo.zf_tb_SuspendedBillItem;
TRUNCATE TABLE dbo.zf_tb_SuspendedBill;
TRUNCATE TABLE dbo.zf_tb_Item;
TRUNCATE TABLE dbo.zf_tb_ItemPriceLink;
TRUNCATE TABLE dbo.zf_tb_StockBalance;
TRUNCATE TABLE dbo.zf_tb_Cashier;
TRUNCATE TABLE dbo.zf_tb_Config;      -- zf_sp_SetupTerminal adds the row on each till
COMMIT;
DBCC SHRINKDATABASE (z_pos_fnt_db_deploy) WITH NO_INFOMSGS;');

-- every zf_ table must be empty now
DECLARE @Left NVARCHAR(MAX);
EXEC sp_executesql N'SELECT @Left = STRING_AGG(t.name + N''='' + CAST(r.rows AS NVARCHAR(20)), N'', '')
    FROM z_pos_fnt_db_deploy.sys.tables t
    CROSS APPLY (SELECT SUM(p.rows) rows FROM z_pos_fnt_db_deploy.sys.partitions p
                 WHERE p.object_id = t.object_id AND p.index_id IN (0, 1)) r
    WHERE r.rows > 0', N'@Left NVARCHAR(MAX) OUTPUT', @Left OUTPUT;
IF @Left IS NOT NULL
    THROW 50001, 'Tables not empty in z_pos_fnt_db_deploy - not backed up.', 1;

-- 3. deployment backup, drop the copy
BACKUP DATABASE z_pos_fnt_db_deploy TO DISK = @Deploy WITH COPY_ONLY, INIT, CHECKSUM;
ALTER DATABASE z_pos_fnt_db_deploy SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE z_pos_fnt_db_deploy;
PRINT 'Deployment backup (empty till db): ' + @Deploy;
