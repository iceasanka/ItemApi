/* =============================================================================
   U065_BackOffice_DropOldTriggers.sql   (2026-11-17)
   Update for a back office db (easyway) that is ALREADY deployed. SQL Server 2008 R2 and newer.
   Safe to run again (a second run finds nothing to drop).

   Old-system clean-up, step 2 of 7 (the shop runs fully on the new system; the old data is in a backup):
     - drops EVERY trigger that sits on an old-system table (any table whose name does not start with z_ / zf_).
       The new system has no triggers; triggers on z_ / zf_ tables and database-level triggers are never touched.
   Before: a full backup of the db. Needs the new ItemApi of 2026-11-17 (old routes removed) - not required, the
   old routes do not use the triggers.

   Run:  sqlcmd -S <server> -d easyway -E -I -b -i U065_BackOffice_DropOldTriggers.sql
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

DECLARE @Name SYSNAME, @Schema SYSNAME, @OnTable SYSNAME, @Sql NVARCHAR(MAX), @Dropped INT;
SET @Dropped = 0;

DECLARE c CURSOR LOCAL FAST_FORWARD FOR
    SELECT tr.name, s.name, t.name
    FROM sys.triggers tr
    JOIN sys.tables t ON t.object_id = tr.parent_id
    JOIN sys.schemas s ON s.schema_id = t.schema_id
    WHERE tr.parent_class = 1 AND tr.is_ms_shipped = 0
      AND t.name NOT LIKE 'z[_]%' AND t.name NOT LIKE 'zf[_]%'
    ORDER BY t.name, tr.name;
OPEN c;
FETCH NEXT FROM c INTO @Name, @Schema, @OnTable;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @Sql = N'DROP TRIGGER ' + QUOTENAME(@Schema) + N'.' + QUOTENAME(@Name) + N';';
    EXEC (@Sql);
    SET @Dropped = @Dropped + 1;
    PRINT 'Dropped trigger ' + @Schema + '.' + @Name + ' (on ' + @OnTable + ')';
    FETCH NEXT FROM c INTO @Name, @Schema, @OnTable;
END
CLOSE c;
DEALLOCATE c;

PRINT 'U065: ' + CAST(@Dropped AS VARCHAR(10)) + ' old trigger(s) dropped.';
GO
SET NOEXEC OFF;
GO
