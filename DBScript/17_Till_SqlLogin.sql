/* =============================================================================
   17_Till_SqlLogin.sql   (2026-10-16)
   Run on: the TILL PC's SQL Server (.\SQLEXPRESS), as an administrator of that SQL Server (Windows login, -E).
   SQL Server 2008 R2 and newer. Safe to run again (an existing login gets the password again and is enabled).

   The SQL login TillService uses in ConnectionStrings:TillDb, e.g.
     Server=.\SQLEXPRESS;Database=z_pos_fnt_db;User Id=ice;Password=***;TrustServerCertificate=True;Encrypt=False
   - turns on "SQL Server and Windows Authentication mode" when the server only allows Windows logins
     (then RESTART the SQL Server service - the script says so)
   - creates the login (no password expiry / policy), or sets its password again
   - makes it a user of the till database with db_owner (TillService is the only program using that db; it runs
     procedures with table-type parameters). A user left over from a restored backup (10_TillDb_DeployBackup.sql)
     is joined to the login (orphaned user).

   The password is NOT in this file - give it on the command line (cmd, in the DBScript folder):
     sqlcmd -S .\SQLEXPRESS -E -b -i 17_Till_SqlLogin.sql -v LoginName="ice" LoginPassword="<password>" DbName="z_pos_fnt_db"
   In SSMS: Query menu -> SQLCMD Mode, and put these three lines at the top first:
     :setvar LoginName "ice"
     :setvar LoginPassword "<password>"
     :setvar DbName "z_pos_fnt_db"
   Check afterwards (as the new login):
     sqlcmd -S .\SQLEXPRESS -U ice -P "<password>" -d z_pos_fnt_db -Q "SELECT DB_NAME(), SUSER_SNAME()"
   ============================================================================= */
SET NOCOUNT ON;
GO
IF IS_SRVROLEMEMBER('sysadmin') <> 1
BEGIN
    RAISERROR('Run this as an administrator of this SQL Server (sqlcmd -E as a Windows admin) - nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
GO
IF DB_ID(N'$(DbName)') IS NULL
BEGIN
    RAISERROR('Database $(DbName) not found on this SQL Server - make the till database first - nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
GO

/* 1. SQL logins allowed? (LoginMode 2 = SQL Server and Windows). Takes effect after a service restart. */
IF CAST(SERVERPROPERTY('IsIntegratedSecurityOnly') AS INT) = 1
BEGIN
    EXEC master.dbo.xp_instance_regwrite N'HKEY_LOCAL_MACHINE', N'Software\Microsoft\MSSQLServer\MSSQLServer',
         N'LoginMode', REG_DWORD, 2;
    PRINT '*** SQL Server was "Windows Authentication only" - changed to "SQL Server and Windows Authentication".';
    PRINT '*** RESTART the SQL Server service now (services.msc -> SQL Server (SQLEXPRESS) -> Restart),';
    PRINT '*** then restart TillService. The login below cannot sign in before that restart.';
END
ELSE
    PRINT 'SQL logins are allowed on this server.';
GO

/* 2. The login */
IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'$(LoginName)')
BEGIN
    CREATE LOGIN [$(LoginName)] WITH PASSWORD = N'$(LoginPassword)', DEFAULT_DATABASE = [$(DbName)],
        CHECK_POLICY = OFF, CHECK_EXPIRATION = OFF;
    PRINT 'Login $(LoginName) created.';
END
ELSE
BEGIN
    ALTER LOGIN [$(LoginName)] WITH PASSWORD = N'$(LoginPassword)', CHECK_POLICY = OFF, CHECK_EXPIRATION = OFF;
    ALTER LOGIN [$(LoginName)] WITH DEFAULT_DATABASE = [$(DbName)];
    ALTER LOGIN [$(LoginName)] ENABLE;
    PRINT 'Login $(LoginName) was there - password set again, enabled.';
END
GO

/* 3. The user in the till database */
USE [$(DbName)];
GO
DECLARE @sid VARBINARY(85);
SELECT @sid = sid FROM sys.server_principals WHERE name = N'$(LoginName)';

IF IS_SRVROLEMEMBER('sysadmin', N'$(LoginName)') = 1
    PRINT 'Login $(LoginName) is a sysadmin - it can use $(DbName) already, no user needed.';
ELSE IF EXISTS (SELECT 1 FROM sys.databases WHERE name = N'$(DbName)' AND owner_sid = @sid)
    PRINT 'Login $(LoginName) owns $(DbName) (dbo) - no user needed.';
ELSE
BEGIN
    IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'$(LoginName)')
    BEGIN
        -- e.g. after restoring a backup made on another PC: same name, different (or no) login behind it
        IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'$(LoginName)' AND sid = @sid)
        BEGIN
            ALTER USER [$(LoginName)] WITH LOGIN = [$(LoginName)];
            PRINT 'User $(LoginName) in $(DbName) was joined to the login again (orphaned user).';
        END
        ELSE
            PRINT 'User $(LoginName) in $(DbName) was there.';
    END
    ELSE
    BEGIN
        CREATE USER [$(LoginName)] FOR LOGIN [$(LoginName)];
        PRINT 'User $(LoginName) created in $(DbName).';
    END
    EXEC sp_addrolemember N'db_owner', N'$(LoginName)';
    PRINT 'User $(LoginName) is db_owner of $(DbName).';
END
GO
SELECT DB_NAME() AS [Database], p.name AS [User], r.name AS [Role]
FROM sys.database_principals p
LEFT JOIN sys.database_role_members m ON m.member_principal_id = p.principal_id
LEFT JOIN sys.database_principals r ON r.principal_id = m.role_principal_id
WHERE p.name = N'$(LoginName)';
GO
SET NOEXEC OFF;
GO
