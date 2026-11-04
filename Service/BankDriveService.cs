using Google;
using Google.Apis.Auth.OAuth2;
using Google.Apis.Drive.v3;
using Google.Apis.Services;
using ItemApi.Models;
using Microsoft.Extensions.Options;
using DriveFile = Google.Apis.Drive.v3.Data.File;

namespace ItemApi.Service
{
    // Bank statement CSVs dropped by hand into Google Drive (1_IreshaFoodCity > BankTransactionFiles), read by the
    // cheque-validate page. Same service account as GoogleSheetService (AppSettings.Apicre / peppy-road-357-...json):
    // the folder must be shared with that account's client_email as Editor. Config section "BankDrive" (optional):
    //   FolderId     the Drive id of BankTransactionFiles (from its URL) - fastest; when "" the folder is found by name
    //   FolderName   default BankTransactionFiles
    //   ParentName   default 1_IreshaFoodCity (only used to pick the right folder when more share the name)
    public class BankDriveService
    {
        private const string FolderMime = "application/vnd.google-apps.folder";
        private const string ProcessedFolderName = "Processed";

        private readonly Lazy<DriveService> _lazy;
        private readonly IConfiguration _config;
        private readonly ILogger<BankDriveService> _log;
        private string? _folderId;

        public BankDriveService(IOptions<AppSettings> appSettings, IConfiguration config, ILogger<BankDriveService> log)
        {
            _config = config;
            _log = log;
            var dir = appSettings.Value.Apicre;
            _lazy = new Lazy<DriveService>(() =>
            {
                var path = Path.Combine(dir, "peppy-road-357-f3c4409465bf.json");
                if (!File.Exists(path))
                    throw new BankDriveException($"Google credential file not found: {path} (AppSettings:Apicre).");
                var credential = GoogleCredential.FromFile(path).CreateScoped(DriveService.Scope.Drive);
                return new DriveService(new BaseClientService.Initializer
                {
                    HttpClientInitializer = credential,
                    ApplicationName = "Cheque Validate"
                });
            });
        }

        private DriveService Drive => _lazy.Value;
        private string FolderName => _config["BankDrive:FolderName"] is { Length: > 0 } n ? n : "BankTransactionFiles";
        private string ParentName => _config["BankDrive:ParentName"] is { Length: > 0 } n ? n : "1_IreshaFoodCity";

        private static string Q(string s) => s.Replace("\\", "\\\\").Replace("'", "\\'");

        private async Task<string> FolderIdAsync(CancellationToken ct)
        {
            if (_folderId != null) return _folderId;
            if (_config["BankDrive:FolderId"] is { Length: > 0 } id) return _folderId = id;

            var req = Drive.Files.List();
            req.Q = $"name = '{Q(FolderName)}' and mimeType = '{FolderMime}' and trashed = false";
            req.Fields = "files(id, name, parents)";
            req.SupportsAllDrives = true;
            req.IncludeItemsFromAllDrives = true;
            var found = (await Run(() => req.ExecuteAsync(ct))).Files ?? new List<DriveFile>();
            if (found.Count == 0)
                throw new BankDriveException($"Google Drive folder '{FolderName}' not found. Share it ({ParentName} > {FolderName}) with {ClientEmail()} as Editor, or set BankDrive:FolderId.");
            if (found.Count > 1)
            {
                // more than one: take the one inside ParentName
                foreach (var f in found)
                {
                    var parent = f.Parents?.FirstOrDefault();
                    if (parent == null) continue;
                    try
                    {
                        var p = Drive.Files.Get(parent);
                        p.Fields = "name";
                        p.SupportsAllDrives = true;
                        if ((await p.ExecuteAsync(ct)).Name == ParentName) return _folderId = f.Id;
                    }
                    catch (GoogleApiException) { /* parent not shared with us */ }
                }
            }
            return _folderId = found[0].Id;
        }

        private string ClientEmail()
        {
            try
            {
                return (Drive.HttpClientInitializer as GoogleCredential)?.UnderlyingCredential is ServiceAccountCredential sa
                    ? sa.Id : "the service account";
            }
            catch { return "the service account"; }
        }

        // the files waiting in the folder, newest first (sub folders such as Processed are left out)
        public async Task<List<BankDriveFile>> ListAsync(CancellationToken ct)
        {
            var folderId = await FolderIdAsync(ct);
            var list = new List<BankDriveFile>();
            string? page = null;
            do
            {
                var req = Drive.Files.List();
                req.Q = $"'{Q(folderId)}' in parents and trashed = false and mimeType != '{FolderMime}'";
                req.Fields = "nextPageToken, files(id, name, size, mimeType, modifiedTime, createdTime)";
                req.OrderBy = "modifiedTime desc";
                req.PageSize = 100;
                req.PageToken = page;
                req.SupportsAllDrives = true;
                req.IncludeItemsFromAllDrives = true;
                var res = await Run(() => req.ExecuteAsync(ct));
                foreach (var f in res.Files ?? new List<DriveFile>())
                    list.Add(new BankDriveFile
                    {
                        Id = f.Id,
                        Name = f.Name,
                        Size = f.Size,
                        MimeType = f.MimeType,
                        Modified = f.ModifiedTimeDateTimeOffset?.LocalDateTime
                    });
                page = res.NextPageToken;
            } while (page != null);
            return list;
        }

        // downloads the file to localPath; a Google Sheet is exported as CSV
        public async Task<string> DownloadAsync(string fileId, string localDir, CancellationToken ct)
        {
            var get = Drive.Files.Get(fileId);
            get.Fields = "id, name, mimeType, parents";
            get.SupportsAllDrives = true;
            var meta = await Run(() => get.ExecuteAsync(ct));
            var folderId = await FolderIdAsync(ct);
            if (meta.Parents?.Contains(folderId) != true)
                throw new BankDriveException($"{meta.Name} is not in the {FolderName} folder.");

            Directory.CreateDirectory(localDir);
            var name = Path.GetFileName(meta.Name);
            var isSheet = meta.MimeType == "application/vnd.google-apps.spreadsheet";
            if (isSheet && !name.EndsWith(".csv", StringComparison.OrdinalIgnoreCase)) name += ".csv";
            foreach (var c in Path.GetInvalidFileNameChars()) name = name.Replace(c, '_');
            var path = Path.Combine(localDir, $"{DateTime.Now:yyyyMMdd-HHmmss}_{name}");

            await using (var fs = new FileStream(path, FileMode.Create))
            {
                var progress = isSheet
                    ? await Drive.Files.Export(fileId, "text/csv").DownloadAsync(fs, ct)
                    : await DownloadMediaAsync(fileId, fs, ct);
                if (progress.Exception != null)
                    throw new BankDriveException($"Download of {meta.Name} failed: {progress.Exception.Message}");
            }
            return path;
        }

        private Task<Google.Apis.Download.IDownloadProgress> DownloadMediaAsync(string fileId, Stream to, CancellationToken ct)
        {
            var req = Drive.Files.Get(fileId);
            req.SupportsAllDrives = true;
            return req.DownloadAsync(to, ct);
        }

        // takes the file out of the folder once processed: deleted; when the account may not delete (the file is owned by
        // the person who uploaded it) it is moved to BankTransactionFiles/Processed. Returns "deleted" / "moved".
        public async Task<string> RemoveAsync(string fileId, CancellationToken ct)
        {
            try
            {
                var del = Drive.Files.Delete(fileId);
                del.SupportsAllDrives = true;
                await del.ExecuteAsync(ct);
                return "deleted";
            }
            catch (GoogleApiException ex) when (ex.HttpStatusCode is System.Net.HttpStatusCode.Forbidden or System.Net.HttpStatusCode.NotFound)
            {
                _log.LogInformation("BankDrive: cannot delete {FileId} ({Error}), moving it to {Folder}", fileId, ex.Message, ProcessedFolderName);
            }

            var folderId = await FolderIdAsync(ct);
            var processedId = await ProcessedFolderIdAsync(folderId, ct);
            var move = Drive.Files.Update(new DriveFile(), fileId);
            move.AddParents = processedId;
            move.RemoveParents = folderId;
            move.SupportsAllDrives = true;
            await Run(() => move.ExecuteAsync(ct));
            return "moved";
        }

        private async Task<string> ProcessedFolderIdAsync(string folderId, CancellationToken ct)
        {
            var req = Drive.Files.List();
            req.Q = $"'{Q(folderId)}' in parents and name = '{ProcessedFolderName}' and mimeType = '{FolderMime}' and trashed = false";
            req.Fields = "files(id)";
            req.SupportsAllDrives = true;
            req.IncludeItemsFromAllDrives = true;
            var hit = (await Run(() => req.ExecuteAsync(ct))).Files?.FirstOrDefault();
            if (hit != null) return hit.Id;
            var create = Drive.Files.Create(new DriveFile { Name = ProcessedFolderName, MimeType = FolderMime, Parents = new List<string> { folderId } });
            create.Fields = "id";
            create.SupportsAllDrives = true;
            return (await Run(() => create.ExecuteAsync(ct))).Id;
        }

        private async Task<T> Run<T>(Func<Task<T>> call)
        {
            try { return await call(); }
            catch (GoogleApiException ex)
            {
                _log.LogWarning("BankDrive: {Error}", ex.Message);
                throw new BankDriveException("Google Drive: " + (ex.Error?.Message ?? ex.Message)
                    + (ex.HttpStatusCode == System.Net.HttpStatusCode.Forbidden && ex.Message.Contains("has not been used", StringComparison.OrdinalIgnoreCase)
                        ? " (enable the Google Drive API for project peppy-road-357 in the Google Cloud console)" : ""));
            }
        }
    }

    public class BankDriveException : Exception
    {
        public BankDriveException(string message) : base(message) { }
    }
}
