/* =============================================================================
   U070_BackOffice_ShrinkAfterCleanup.sql   (2026-11-17)
   Update for a back office db (easyway) that is ALREADY deployed. SQL Server 2008 R2 and newer.
   Safe to run again (it only shrinks what can be shrunk).

   Old-system clean-up, step 7 of 7 - give the disk space of the dropped old tables back (after U069):
     - shrinks the data file to the space in use + 500 MB free room (local db: 4 GB file, 148 MB used),
     - shrinks the log file to 256 MB (with the FULL recovery model it shrinks only as far as the last log backup
       allows - run it again after the next log backup if it stays big),
     - then REORGANIZEs the indexes of the new z_ / zf_ tables and updates their statistics (a shrink scatters
       the index pages). REORGANIZE, not REBUILD: it never locks a table, on every SQL Server edition.
   No data is changed. The db stays usable while it runs, only slower - run it after the day end when the shop is
   closed (a few minutes for the local db).

   Run:  sqlcmd -S <server> -d easyway -E -I -b -i U070_BackOffice_ShrinkAfterCleanup.sql
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

-- 1. data file(s): space in use + 500 MB
DECLARE @FileId INT, @FileName SYSNAME, @Type TINYINT, @SizeMB INT, @UsedMB INT, @Target INT, @Sql NVARCHAR(400);
DECLARE c CURSOR LOCAL STATIC FOR
    SELECT file_id, name, type, size / 128, CAST(FILEPROPERTY(name, 'SpaceUsed') AS INT) / 128
    FROM sys.database_files WHERE type IN (0, 1);
OPEN c;
FETCH NEXT FROM c INTO @FileId, @FileName, @Type, @SizeMB, @UsedMB;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @Target = CASE WHEN @Type = 0 THEN @UsedMB + 500 ELSE 256 END;
    IF @SizeMB > @Target
    BEGIN
        PRINT 'Shrinking ' + @FileName + ' from ' + CAST(@SizeMB AS VARCHAR(10)) + ' MB to ' + CAST(@Target AS VARCHAR(10)) + ' MB ...';
        SET @Sql = N'DBCC SHRINKFILE (' + CAST(@FileId AS NVARCHAR(10)) + N', ' + CAST(@Target AS NVARCHAR(10)) + N') WITH NO_INFOMSGS;';
        EXEC (@Sql);
    END
    ELSE
        PRINT @FileName + ' is ' + CAST(@SizeMB AS VARCHAR(10)) + ' MB - nothing to shrink.';
    FETCH NEXT FROM c INTO @FileId, @FileName, @Type, @SizeMB, @UsedMB;
END
CLOSE c;
DEALLOCATE c;
GO

-- 2. the new tables: reorganize their indexes (online) and update statistics
DECLARE @T NVARCHAR(600), @Sql NVARCHAR(MAX), @Done INT;
SET @Done = 0;
DECLARE t CURSOR LOCAL STATIC FOR
    SELECT QUOTENAME(s.name) + N'.' + QUOTENAME(tb.name)
    FROM sys.tables tb JOIN sys.schemas s ON s.schema_id = tb.schema_id
    WHERE tb.is_ms_shipped = 0 AND (tb.name LIKE 'z[_]%' OR tb.name LIKE 'zf[_]%')
    ORDER BY tb.name;
OPEN t;
FETCH NEXT FROM t INTO @T;
WHILE @@FETCH_STATUS = 0
BEGIN
    IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(@T) AND index_id > 0)
    BEGIN
        BEGIN TRY
            SET @Sql = N'ALTER INDEX ALL ON ' + @T + N' REORGANIZE;';
            EXEC (@Sql);
        END TRY
        BEGIN CATCH
            PRINT 'Could not reorganize ' + @T + ': ' + ERROR_MESSAGE();
        END CATCH
    END
    SET @Sql = N'UPDATE STATISTICS ' + @T + N';';
    EXEC (@Sql);
    SET @Done = @Done + 1;
    FETCH NEXT FROM t INTO @T;
END
CLOSE t;
DEALLOCATE t;
PRINT CAST(@Done AS VARCHAR(10)) + ' new table(s) reorganized and statistics updated.';

SELECT name AS FileName, type_desc, size / 128 AS FileMB, CAST(FILEPROPERTY(name, 'SpaceUsed') AS INT) / 128 AS UsedMB
FROM sys.database_files;
PRINT 'U070 done.';
GO
SET NOEXEC OFF;
GO
