using System.Data;
using System.Text.RegularExpressions;
using Microsoft.Data.SqlClient;
using Serilog;

namespace ItemApi.Service
{
    // Settings > Backup (U051, Docs/StockSystem.md §6.38): a full backup of the databases every day at the chosen time
    // (default 11 PM) while this server is on, into ONE file per database that is overwritten every day:
    //   <folder>\<db>_daily.bak     (written as <db>_daily_new.bak first, checked, then put over yesterday's file - so a
    //                                failed backup never destroys the last good one, when ItemApi can see the folder)
    // The database: the DefaultConnection one (easyway) only. The till database (z_pos_fnt_db) is backed up by
    // TillService on each till PC (also when a till runs on the back office PC).
    // Folder empty = D:\IRMBackup. The folder is on the SQL Server computer (SQL Server writes the file).
    // Missed because the PC was off at that time = no backup that day (the next one is at the time on the next day).
    // A failed automatic backup is tried again 30 minutes later, at most 3 times a day. Every try is in z_tb_DbBackup.
    public class DbBackupService : BackgroundService
    {
        public const string EnabledKey = "Backup.Enabled";
        public const string TimeKey = "Backup.Time";
        public const string FolderKey = "Backup.Folder";

        // used when Backup.Folder is empty (same folder as the tills' backups)
        public const string DefaultFolder = @"D:\IRMBackup";

        private readonly IConfiguration _config;
        private readonly SemaphoreSlim _gate = new(1, 1);

        public DbBackupService(IConfiguration config) => _config = config;

        // a backup is running now (automatic or "Back up now")
        public bool Running { get; private set; }
        public DateTime? RunningSince { get; private set; }
        public string? RunningDb { get; private set; }

        private string MainConn => _config.GetConnectionString("DefaultConnection")!;

        // ---- the timer ------------------------------------------------------------------------------------------------

        protected override async Task ExecuteAsync(CancellationToken stoppingToken)
        {
            try { await Task.Delay(TimeSpan.FromSeconds(30), stoppingToken); } catch (OperationCanceledException) { return; }
            while (!stoppingToken.IsCancellationRequested)
            {
                try
                {
                    await TickAsync();
                }
                catch (Exception ex)
                {
                    Log.Error(ex, "Daily backup check failed");
                }
                try { await Task.Delay(TimeSpan.FromMinutes(1), stoppingToken); } catch (OperationCanceledException) { return; }
            }
        }

        private async Task TickAsync()
        {
            var s = await ReadSettingsAsync();
            if (!s.Enabled || Running) return;
            var now = DateTime.Now;
            if (now < now.Date + s.Time) return;

            await using var con = new SqlConnection(MainConn);
            await con.OpenAsync();
            await using var cmd = new SqlCommand(
                "SELECT SUM(CASE WHEN Ok = 1 THEN 1 ELSE 0 END), COUNT(*), MAX(StartedAt) FROM dbo.z_tb_DbBackup " +
                "WHERE Manual = 0 AND StartedAt >= @Due", con);
            cmd.Parameters.Add("@Due", SqlDbType.DateTime).Value = now.Date + s.Time;   // tries since today's backup time
            await using var r = await cmd.ExecuteReaderAsync();
            await r.ReadAsync();
            var ok = r.IsDBNull(0) ? 0 : r.GetInt32(0);
            var tries = r.GetInt32(1);
            var last = r.IsDBNull(2) ? (DateTime?)null : r.GetDateTime(2);
            await r.CloseAsync();
            // done today, or 3 runs today (a run = one row per database), or the last try was under 30 minutes ago
            if (ok > 0 || tries >= 3 * Databases().Count || (last != null && now - last.Value < TimeSpan.FromMinutes(30))) return;

            await RunAsync(manual: false, userId: null);
        }

        // "Back up now" on the Settings page: starts in the background; false = one is already running
        public bool StartNow(int userId)
        {
            if (Running) return false;
            _ = Task.Run(async () =>
            {
                try { await RunAsync(manual: true, userId: userId); }
                catch (Exception ex) { Log.Error(ex, "Backup now failed"); }
            });
            return true;
        }

        // ---- the backup -----------------------------------------------------------------------------------------------

        private async Task RunAsync(bool manual, int? userId)
        {
            if (!await _gate.WaitAsync(0)) return;
            try
            {
                Running = true;
                RunningSince = DateTime.Now;
                var s = await ReadSettingsAsync();
                var folder = s.Folder.Length > 0 ? s.Folder : DefaultFolder;
                foreach (var (conn, db) in Databases())
                {
                    RunningDb = db;
                    await BackupOneAsync(conn, db, folder, manual, userId);
                }
            }
            finally
            {
                Running = false;
                RunningSince = null;
                RunningDb = null;
                _gate.Release();
            }
        }

        // (connection string, database) to back up: the back office database (DefaultConnection) only.
        // Not PosConnection: the till database is backed up on each till by TillService.
        private List<(string Conn, string Db)> Databases()
        {
            var list = new List<(string, string)>();
            var cs = _config.GetConnectionString("DefaultConnection");
            if (string.IsNullOrWhiteSpace(cs)) return list;
            var b = new SqlConnectionStringBuilder(cs);
            if (!string.IsNullOrWhiteSpace(b.InitialCatalog)) list.Add((cs, b.InitialCatalog));
            return list;
        }

        private async Task BackupOneAsync(string conn, string db, string folder, bool manual, int? userId)
        {
            SqlConnection con;
            try
            {
                con = new SqlConnection(conn);
                await con.OpenAsync();
            }
            catch (Exception ex)
            {
                var failId = await LogStartAsync(db, null, manual, userId);
                await LogEndAsync(failId, false, null, $"Could not connect: {ex.Message}");
                return;
            }

            await using (con)
            {
                var final = folder.Length == 0 ? "" : Path.Combine(folder, $"{db}_daily.bak");
                var id = await LogStartAsync(db, final, manual, userId);
                try
                {
                    // ItemApi on the SQL Server computer (it can see the folder): back up to _new, check, then replace
                    // yesterday's file. Else straight over yesterday's file.
                    var apiSeesFolder = SafeDirectoryExists(folder);
                    await ExecAsync(con, "EXEC master.dbo.xp_create_subdir @Dir", ("@Dir", folder));   // makes the folder when missing
                    if (!apiSeesFolder) apiSeesFolder = SafeDirectoryExists(folder);
                    var target = apiSeesFolder ? Path.Combine(folder, $"{db}_daily_new.bak") : final;

                    await ExecAsync(con,
                        "DECLARE @sql NVARCHAR(MAX); " +
                        "SET @sql = N'BACKUP DATABASE ' + QUOTENAME(@Db) + N' TO DISK = @File WITH INIT, FORMAT, CHECKSUM, NAME = @Name'; " +
                        "EXEC sp_executesql @sql, N'@File NVARCHAR(400), @Name NVARCHAR(128)', @File = @File, @Name = @Name;",
                        ("@Db", db), ("@File", target), ("@Name", $"{db} daily {DateTime.Now:yyyy-MM-dd HH:mm}"));
                    await ExecAsync(con, "RESTORE VERIFYONLY FROM DISK = @File WITH CHECKSUM", ("@File", target));

                    long? size = null;
                    if (apiSeesFolder)
                    {
                        File.Move(target, final, overwrite: true);
                        size = new FileInfo(final).Length;
                    }
                    else
                    {
                        size = await BackupSizeAsync(con, db);
                    }
                    await LogEndAsync(id, true, size, null);
                    Log.Information("Backup of {Db} done: {File} ({Size} bytes)", db, final, size);
                }
                catch (Exception ex)
                {
                    var msg = ex.Message;
                    if (msg.Contains("xp_create_subdir", StringComparison.OrdinalIgnoreCase))
                        msg = $"The folder {folder} could not be made on the SQL Server computer ({msg}) - check the drive and the path.";
                    else if (msg.Contains("Operating system error 5", StringComparison.OrdinalIgnoreCase))
                        msg += " - the SQL Server service account cannot write to this folder: give it write access, or choose another folder.";
                    Log.Error(ex, "Backup of {Db} failed", db);
                    await LogEndAsync(id, false, null, msg);
                }
            }
        }

        private static bool SafeDirectoryExists(string folder)
        {
            try { return Directory.Exists(folder); } catch { return false; }
        }

        private static async Task ExecAsync(SqlConnection con, string sql, params (string Name, string Value)[] args)
        {
            await using var cmd = new SqlCommand(sql, con) { CommandTimeout = 0 };   // a backup can take a while
            foreach (var (n, v) in args) cmd.Parameters.Add(n, SqlDbType.NVarChar, 400).Value = v;
            await cmd.ExecuteNonQueryAsync();
        }

        private static async Task<long?> BackupSizeAsync(SqlConnection con, string db)
        {
            try
            {
                await using var cmd = new SqlCommand(
                    "SELECT TOP 1 CAST(backup_size AS BIGINT) FROM msdb.dbo.backupset WHERE database_name = @Db ORDER BY backup_finish_date DESC", con);
                cmd.Parameters.Add("@Db", SqlDbType.NVarChar, 128).Value = db;
                var v = await cmd.ExecuteScalarAsync();
                return v is long l ? l : null;
            }
            catch { return null; }
        }

        // ---- the log (z_tb_DbBackup) ----------------------------------------------------------------------------------

        private async Task<int> LogStartAsync(string db, string? file, bool manual, int? userId)
        {
            await using var con = new SqlConnection(MainConn);
            await con.OpenAsync();
            await using var cmd = new SqlCommand(
                "INSERT dbo.z_tb_DbBackup (DbName, FileName, StartedAt, Manual, UserId) VALUES (@Db, @File, GETDATE(), @Manual, @UserId); " +
                "SELECT CAST(SCOPE_IDENTITY() AS INT); " +
                "DELETE FROM dbo.z_tb_DbBackup WHERE StartedAt < DATEADD(DAY, -90, GETDATE());", con);
            cmd.Parameters.Add("@Db", SqlDbType.NVarChar, 128).Value = db;
            cmd.Parameters.Add("@File", SqlDbType.NVarChar, 400).Value = (object?)NullIfEmpty(file) ?? DBNull.Value;
            cmd.Parameters.Add("@Manual", SqlDbType.Bit).Value = manual;
            cmd.Parameters.Add("@UserId", SqlDbType.Int).Value = (object?)userId ?? DBNull.Value;
            return (int)(await cmd.ExecuteScalarAsync())!;
        }

        private async Task LogEndAsync(int id, bool ok, long? size, string? message)
        {
            await using var con = new SqlConnection(MainConn);
            await con.OpenAsync();
            await using var cmd = new SqlCommand(
                "UPDATE dbo.z_tb_DbBackup SET FinishedAt = GETDATE(), Ok = @Ok, SizeBytes = @Size, Message = @Msg WHERE BackupId = @Id", con);
            cmd.Parameters.Add("@Id", SqlDbType.Int).Value = id;
            cmd.Parameters.Add("@Ok", SqlDbType.Bit).Value = ok;
            cmd.Parameters.Add("@Size", SqlDbType.BigInt).Value = (object?)size ?? DBNull.Value;
            cmd.Parameters.Add("@Msg", SqlDbType.NVarChar, 1000).Value =
                (object?)(message?.Length > 1000 ? message[..1000] : message) ?? DBNull.Value;
            await cmd.ExecuteNonQueryAsync();
        }

        private static string? NullIfEmpty(string? s) => string.IsNullOrEmpty(s) ? null : s;

        // ---- settings and status for the page ----------------------------------------------------------------------------

        public record BackupSettings(bool Enabled, TimeSpan Time, string Folder);

        public async Task<BackupSettings> ReadSettingsAsync()
        {
            await using var con = new SqlConnection(MainConn);
            await con.OpenAsync();
            await using var cmd = new SqlCommand(
                "SELECT SettingKey, ISNULL(Value, DefaultValue) FROM dbo.z_tb_Setting WHERE SettingKey LIKE 'Backup.%'", con);
            var v = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            await using (var r = await cmd.ExecuteReaderAsync())
                while (await r.ReadAsync()) v[r.GetString(0)] = r.IsDBNull(1) ? "" : r.GetString(1).Trim();
            return new BackupSettings(
                v.GetValueOrDefault(EnabledKey, "1") == "1",
                TimeSpan.TryParse(v.GetValueOrDefault(TimeKey, "23:00"), out var t) && t < TimeSpan.FromDays(1) ? t : new TimeSpan(23, 0, 0),
                v.GetValueOrDefault(FolderKey, ""));
        }

        public List<string> DatabaseNames() => Databases().Select(d => d.Db).ToList();

        // a folder the page may save: "D:\Backup" or "\\server\share\backup", no characters Windows does not allow
        public static bool FolderOk(string folder) =>
            folder.Length <= 200 && Regex.IsMatch(folder, @"^([A-Za-z]:\\|\\\\[^\\/:*?""<>|]+\\[^\\/:*?""<>|]+)[^/:*?""<>|]*$");

        public async Task<List<BackupLogRow>> HistoryAsync(int top)
        {
            await using var con = new SqlConnection(MainConn);
            await con.OpenAsync();
            await using var cmd = new SqlCommand(
                "SELECT TOP (@Top) b.BackupId, b.DbName, b.FileName, b.StartedAt, b.FinishedAt, b.SizeBytes, b.Ok, b.Message, b.Manual, u.UserName " +
                "FROM dbo.z_tb_DbBackup b LEFT JOIN dbo.z_tb_User u ON u.UserId = b.UserId ORDER BY b.BackupId DESC", con);
            cmd.Parameters.Add("@Top", SqlDbType.Int).Value = top;
            var list = new List<BackupLogRow>();
            await using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
                list.Add(new BackupLogRow
                {
                    BackupId = r.GetInt32(0),
                    DbName = r.GetString(1),
                    FileName = r.IsDBNull(2) ? null : r.GetString(2),
                    StartedAt = r.GetDateTime(3),
                    FinishedAt = r.IsDBNull(4) ? null : r.GetDateTime(4),
                    SizeBytes = r.IsDBNull(5) ? null : r.GetInt64(5),
                    Ok = r.IsDBNull(6) ? null : r.GetBoolean(6),
                    Message = r.IsDBNull(7) ? null : r.GetString(7),
                    Manual = r.GetBoolean(8),
                    UserName = r.IsDBNull(9) ? null : r.GetString(9),
                });
            return list;
        }
    }

    public class BackupLogRow
    {
        public int BackupId { get; set; }
        public string DbName { get; set; } = "";
        public string? FileName { get; set; }
        public DateTime StartedAt { get; set; }
        public DateTime? FinishedAt { get; set; }
        public long? SizeBytes { get; set; }
        public bool? Ok { get; set; }          // null = running (or the API stopped during it)
        public string? Message { get; set; }
        public bool Manual { get; set; }
        public string? UserName { get; set; }
    }
}
