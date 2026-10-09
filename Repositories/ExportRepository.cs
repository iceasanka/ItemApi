using System.Globalization;
using System.Text;
using ItemApi.Data;
using ItemApi.Interface;
using ItemApi.Models;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using Serilog;

namespace ItemApi.Repositories
{
    // Writes export files to a folder on the API server. SCALE = the weighing scale item file:
    //   PLU#Description#Price#   one line per item, CRLF, no header (same as the scale's sample ScaleItem.txt).
    // Written only when someone presses Export; z_tb_ScaleExportItem remembers what was sent so the page can show
    // what changed since. Docs/StockSystem.md §6.10.
    public class ExportRepository : IExportRepository
    {
        public const string Scale = "SCALE";
        private const int PluLength = 5;

        // one export at a time, so two clicks never write the file at once
        private static readonly SemaphoreSlim ExportLock = new(1, 1);

        private readonly AppDbContext _context;
        private readonly int _locationId;

        public ExportRepository(AppDbContext context, IOptions<AppSettings> appSettings)
        {
            _context = context;
            _locationId = appSettings.Value.LocationId;
        }

        public async Task<List<ExportSetting>> GetSettingsAsync()
        {
            return await _context.ExportSettings.AsNoTracking().OrderBy(s => s.Name).ToListAsync();
        }

        public async Task<ExportSetting?> GetSettingAsync(string exportCode)
        {
            return await _context.ExportSettings.AsNoTracking().FirstOrDefaultAsync(s => s.ExportCode == exportCode);
        }

        public async Task<ExportSetting> UpdateSettingAsync(string exportCode, ExportSettingUpdate request)
        {
            var setting = await _context.ExportSettings.FirstOrDefaultAsync(s => s.ExportCode == exportCode)
                          ?? throw new KeyNotFoundException();

            var folder = (request.FolderPath ?? "").Trim();
            var fileName = (request.FileName ?? "").Trim();
            if (folder.Length == 0)
                throw new ExportException("Folder is required.");
            if (folder.Length > 260 || !Path.IsPathFullyQualified(folder))
                throw new ExportException("Folder must be a full path, e.g. D:\\Scale or \\\\SCALE-PC\\Import.");
            if (!Directory.Exists(folder))
                throw new ExportException($"Folder '{folder}' was not found from the server, or the server has no access to it.");
            if (fileName.Length == 0 || fileName.Length > 100 || fileName.IndexOfAny(Path.GetInvalidFileNameChars()) >= 0)
                throw new ExportException("File name is required, max 100 characters, without \\ / : * ? \" < > |.");
            if (request.NameMaxLength is < 0 or > 100)
                throw new ExportException("Name length must be 0 (no limit) to 100.");

            setting.FolderPath = folder;
            setting.FileName = fileName;
            setting.NameMaxLength = request.NameMaxLength;
            setting.UserId = request.UserId;
            setting.UDate = DateTime.Now;
            await _context.SaveChangesAsync();
            return setting;
        }

        public async Task<ExportPreview> GetScalePreviewAsync()
        {
            var setting = await GetSettingAsync(Scale) ?? throw new KeyNotFoundException();
            return await BuildScalePreviewAsync(setting);
        }

        public async Task<(string FileName, byte[] Content)> BuildScaleFileAsync()
        {
            var preview = await GetScalePreviewAsync();
            return (preview.Setting.FileName, Encode(preview.Lines));
        }

        public async Task<ExportResult> RunScaleExportAsync(int? userId)
        {
            await ExportLock.WaitAsync();
            try
            {
                var setting = await _context.ExportSettings.FirstOrDefaultAsync(s => s.ExportCode == Scale)
                              ?? throw new KeyNotFoundException();
                if (string.IsNullOrWhiteSpace(setting.FolderPath))
                    throw new ExportException("Set the export folder first.");

                var preview = await BuildScalePreviewAsync(setting);
                var target = Path.Combine(setting.FolderPath, setting.FileName);
                var now = DateTime.Now;

                try
                {
                    if (!Directory.Exists(setting.FolderPath))
                        throw new ExportException($"Folder '{setting.FolderPath}' was not found from the server, or the server has no access to it.");

                    // write next to the target, then swap it in, so the scale program never reads a half-written file
                    var temp = target + ".tmp";
                    await File.WriteAllBytesAsync(temp, Encode(preview.Lines));
                    File.Move(temp, target, overwrite: true);
                }
                catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or ExportException)
                {
                    var message = ex is ExportException ? ex.Message : $"Could not write '{target}': {ex.Message}";
                    Log.Error($"Scale export failed: {ex}");
                    _context.ExportLogs.Add(new ExportLog
                    {
                        ExportCode = Scale, FilePath = target, LineCount = 0, SkippedCount = preview.Skipped.Count,
                        Status = 9, Error = Cut(message, 500), UserId = userId, CDate = now
                    });
                    await _context.SaveChangesAsync();
                    throw new ExportException(message);
                }

                setting.LastExportAt = now;
                setting.LastExportBy = userId;
                setting.LastLineCount = preview.Lines.Count;
                await _context.SaveScaleExportAsync(setting,
                    preview.Lines.Select(l => new ScaleExportItem
                    {
                        ItemId = l.ItemId, Plu = l.Plu, Descrip = l.Descrip, Price = l.Price, ExportedAt = now
                    }).ToList(),
                    new ExportLog
                    {
                        ExportCode = Scale, FilePath = target, LineCount = preview.Lines.Count,
                        SkippedCount = preview.Skipped.Count, Status = 1, UserId = userId, CDate = now
                    });

                return new ExportResult
                {
                    FilePath = target,
                    LineCount = preview.Lines.Count,
                    SkippedCount = preview.Skipped.Count,
                    NewCount = preview.NewCount,
                    ChangedCount = preview.ChangedCount,
                    RemovedCount = preview.Removed.Count,
                    ExportedAt = now
                };
            }
            finally
            {
                ExportLock.Release();
            }
        }

        public async Task<List<ExportLog>> GetLogAsync(string exportCode, int top)
        {
            return await _context.ExportLogs.AsNoTracking()
                .Where(l => l.ExportCode == exportCode)
                .OrderByDescending(l => l.ExportLogId)
                .Take(top)
                .ToListAsync();
        }

        // ─── Scale file rules ───

        private async Task<ExportPreview> BuildScalePreviewAsync(ExportSetting setting)
        {
            var sources = await _context.GetScaleItemSourcesAsync(_locationId);
            var last = await _context.ScaleExportItems.AsNoTracking().ToDictionaryAsync(s => s.ItemId);
            var preview = new ExportPreview
            {
                Setting = setting,
                FilePath = string.IsNullOrWhiteSpace(setting.FolderPath) ? null : Path.Combine(setting.FolderPath, setting.FileName)
            };

            var candidates = new List<ScaleExportLine>();
            foreach (var s in sources)
            {
                var reason = SkipReason(s, out var plu, out var name);
                if (reason != null)
                {
                    preview.Skipped.Add(new ScaleExportSkipped
                    {
                        ItemId = s.ItemId, RefCode = s.RefCode, Descrip = s.Descrip, Price = s.RetailPrice, Reason = reason
                    });
                    continue;
                }

                var line = new ScaleExportLine
                {
                    ItemId = s.ItemId, RefCode = s.RefCode, Plu = plu, Descrip = name, Price = Math.Round(s.RetailPrice!.Value, 2)
                };
                if (setting.NameMaxLength > 0 && line.Descrip.Length > setting.NameMaxLength)
                {
                    line.Descrip = line.Descrip.Substring(0, setting.NameMaxLength).TrimEnd();
                    line.Warning = $"Name cut to {setting.NameMaxLength} characters";
                }
                candidates.Add(line);
            }

            // the scale finds an item by its PLU, so a PLU used twice would sell one item at the other's price
            foreach (var dup in candidates.GroupBy(l => l.Plu).Where(g => g.Count() > 1))
            {
                foreach (var l in dup)
                {
                    var others = string.Join(", ", dup.Where(o => o != l).Select(o => o.Descrip));
                    preview.Skipped.Add(new ScaleExportSkipped
                    {
                        ItemId = l.ItemId, RefCode = l.RefCode, Descrip = l.Descrip, Price = l.Price,
                        Reason = $"Same scale code {l.Plu} as {others}"
                    });
                }
            }
            var dupPlus = candidates.GroupBy(l => l.Plu).Where(g => g.Count() > 1).Select(g => g.Key).ToHashSet();
            preview.Lines = candidates.Where(l => !dupPlus.Contains(l.Plu)).OrderBy(l => l.Plu).ToList();

            foreach (var l in preview.Lines)
            {
                if (!last.TryGetValue(l.ItemId, out var was))
                {
                    l.Change = "new";
                    continue;
                }
                if (was.Plu != l.Plu) l.Changes.Add($"Code {was.Plu} → {l.Plu}");
                if (was.Price != l.Price) l.Changes.Add($"Price {Money(was.Price)} → {Money(l.Price)}");
                if (was.Descrip != l.Descrip) l.Changes.Add($"Name '{was.Descrip}' → '{l.Descrip}'");
                if (l.Changes.Count > 0) l.Change = "changed";
            }

            var exported = preview.Lines.Select(l => l.ItemId).ToHashSet();
            preview.Removed = last.Values.Where(w => !exported.Contains(w.ItemId)).OrderBy(w => w.Plu)
                .Select(w => new ScaleExportRemoved { ItemId = w.ItemId, Plu = w.Plu, Descrip = w.Descrip, Price = w.Price })
                .ToList();
            preview.Skipped = preview.Skipped.OrderBy(s => s.RefCode).ToList();
            preview.NewCount = preview.Lines.Count(l => l.Change == "new");
            preview.ChangedCount = preview.Lines.Count(l => l.Change == "changed");
            preview.HasChanges = preview.NewCount + preview.ChangedCount + preview.Removed.Count > 0;
            return preview;
        }

        private static string? SkipReason(ScaleItemSource s, out string plu, out string name)
        {
            plu = "";
            name = CleanName(s.Descrip);
            var code = (s.RefCode ?? "").Trim();
            if (code.Length == 0) return "No ref code (the scale code)";
            if (!code.All(char.IsAsciiDigit)) return "Ref code is not a number";
            if (code.Length > PluLength) return $"Ref code is longer than {PluLength} digits";
            plu = code.PadLeft(PluLength, '0');
            if (name.Length == 0) return "No description";
            if ((s.RetailPrice ?? 0) <= 0) return "No retail price";
            if (s.IsSaleLocked) return "Sale locked";
            return null;
        }

        // '#' separates the fields and a line break ends the line, so neither may be in the name
        private static string CleanName(string? descrip)
        {
            var sb = new StringBuilder();
            foreach (var c in (descrip ?? "").Trim())
                sb.Append(c == '#' || char.IsControl(c) ? ' ' : c);
            return sb.ToString().Trim();
        }

        private static byte[] Encode(List<ScaleExportLine> lines)
        {
            var sb = new StringBuilder();
            foreach (var l in lines)
                sb.Append(l.Plu).Append('#').Append(l.Descrip).Append('#').Append(Money(l.Price)).Append("#\r\n");
            return new UTF8Encoding(false).GetBytes(sb.ToString());
        }

        private static string Money(decimal value) => value.ToString("0.00", CultureInfo.InvariantCulture);

        private static string Cut(string text, int max) => text.Length <= max ? text : text.Substring(0, max);
    }
}
