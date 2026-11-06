using ItemApi.Interface;
using ItemApi.Models;
using ItemApi.Service;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;
using Serilog;

namespace ItemApi.Controllers
{
    // Settings page — admins only, ALWAYS (also while Auth:Enforce is false). Docs/StockSystem.md §6.28.
    // General settings for the whole system, and per-user settings (a user's own value instead of the general one).
    // Till settings reach the tills on their next download (≤ 5 min / Reload) — api/Sync/Settings.
    // Also Settings > Printers (§6.37) and Settings > Backup (§6.38).
    [Route("api/[controller]")]
    [ApiController]
    [Authorize(Roles = UserRoles.AdminName)]
    public class SettingsController : ControllerBase
    {
        private readonly ISettingRepository _settings;

        public SettingsController(ISettingRepository settings)
        {
            _settings = settings;
        }

        // GET: api/Settings — every setting with its general value
        [HttpGet]
        public async Task<IActionResult> List()
        {
            return await Run(async () => Ok(await _settings.ListAsync()));
        }

        // PUT: api/Settings/Till.BillDiscSkipItemDisc { value } — value null = back to the default
        [HttpPut("{key}")]
        public async Task<IActionResult> Set(string key, [FromBody] SettingValueRequest request)
        {
            return await Run(async () =>
            {
                // a printer must be one installed on this server (Settings > Printers)
                var value = request?.Value?.Trim();
                if (key is PrinterConfig.BillKey or PrinterConfig.GeneralKey or PrinterConfig.StickerKey && !string.IsNullOrEmpty(value)
                    && !PrinterConfig.Installed().Contains(value, StringComparer.OrdinalIgnoreCase))
                    return BadRequest(new { message = $"'{value}' is not installed on the server." });
                // the backup folder: a full path on the SQL Server computer
                if (key == DbBackupService.FolderKey && !string.IsNullOrEmpty(value) && !DbBackupService.FolderOk(value))
                    return BadRequest(new { message = @"Type the full folder path, e.g. D:\Backup or \\server\share\backup." });
                await _settings.SetAsync(key, string.IsNullOrEmpty(value) ? null : request?.Value?.Trim(), Me);
                return Ok(new { message = "Setting saved." });
            });
        }

        // GET: api/Settings/Users — the per-user settings and each user's own values
        [HttpGet("Users")]
        public async Task<IActionResult> Users()
        {
            return await Run(async () => Ok(await _settings.ListUsersAsync()));
        }

        // PUT: api/Settings/User/5/Till.ProfitView { value } — value null = the user gets the general value again
        [HttpPut("User/{userId:int}/{key}")]
        public async Task<IActionResult> SetUser(int userId, string key, [FromBody] SettingValueRequest request)
        {
            return await Run(async () =>
            {
                await _settings.SetUserAsync(userId, key, request?.Value, Me);
                return Ok(new { message = "Setting saved." });
            });
        }

        // ---- Settings > Printers ------------------------------------------------------------------------------------------

        // GET: api/Settings/Printers — the printers installed on the API server, its COM ports and the saved printers.
        // Bill / sticker: Windows printer, COM port or network (U051). General: a Windows printer.
        [HttpGet("Printers")]
        public async Task<IActionResult> Printers([FromServices] PrinterConfig config)
        {
            return await Run(async () =>
            {
                var p = await config.GetAsync();
                return Ok(new
                {
                    installed = PrinterConfig.Installed(),
                    comPorts = SafePorts(),
                    baudRates = PrinterConfig.BaudRates,
                    bill = new
                    {
                        conn = p.BillTarget.Conn, name = p.BillTarget.Name, port = p.BillTarget.Port, address = p.BillTarget.Address,
                        baud = p.BillTarget.Baud, mode = p.BillEscPos ? "escpos" : "driver", width = p.BillChars,
                    },
                    general = new { conn = PrinterTarget.Windows, name = p.General, port = "", address = "", baud = 38400 },
                    sticker = new
                    {
                        conn = p.StickerTarget.Conn, name = p.StickerTarget.Name, port = p.StickerTarget.Port,
                        address = p.StickerTarget.Address, baud = p.StickerTarget.Baud,
                    },
                });
            });
        }

        // PUT: api/Settings/Printers/bill { conn, name, port, address, baud, mode, width } — the whole printer at once.
        // Nothing picked (no name / port / address for the connection) = the printer is cleared.
        [HttpPut("Printers/{kind}")]
        public async Task<IActionResult> SavePrinter(string kind, [FromBody] PrinterSaveRequest request)
        {
            return await Run(async () =>
            {
                kind = (kind ?? "").Trim().ToLowerInvariant();
                if (kind is not ("bill" or "general" or "sticker")) return BadRequest(new { message = "Which printer: bill, general or sticker." });
                if (request == null) return BadRequest(new { message = "Nothing to save." });
                var t = ToTarget(kind, request);
                var clear = !t.IsSet;
                if (!clear && t.Problem() is { } problem) return BadRequest(new { message = problem });
                if (kind == "bill" && request.Mode is not (null or "driver" or "escpos"))
                    return BadRequest(new { message = "How to print: driver or escpos." });
                if (kind == "bill" && request.Width is not (null or 32 or 42 or 48))
                    return BadRequest(new { message = "Paper: 48, 42 or 32 characters a line." });

                static string? N(string? v) => string.IsNullOrWhiteSpace(v) ? null : v.Trim();
                // the Windows name is kept when another connection is chosen (switching back keeps it)
                await _settings.SetAsync(PrinterConfig.NameKey(kind), clear ? null : N(t.Name), Me);
                if (kind != "general")
                {
                    await _settings.SetAsync(PrinterConfig.ConnKey(kind), clear || t.Conn == PrinterTarget.Windows ? null : t.Conn.ToString(), Me);
                    await _settings.SetAsync(PrinterConfig.PortKey(kind), clear ? null : N(t.Port.ToUpperInvariant()), Me);
                    await _settings.SetAsync(PrinterConfig.AddressKey(kind), clear ? null : N(t.Address), Me);
                    await _settings.SetAsync(PrinterConfig.BaudKey(kind), t.Baud == 38400 ? null : t.Baud.ToString(), Me);
                }
                if (kind == "bill")
                {
                    await _settings.SetAsync(PrinterConfig.BillModeKey, request.Mode is null or "driver" ? null : request.Mode, Me);
                    await _settings.SetAsync(PrinterConfig.BillWidthKey, request.Width is null or 48 ? null : request.Width.ToString(), Me);
                }
                var note = t.Conn == PrinterTarget.Com && !SafePorts().Contains(t.Port, StringComparer.OrdinalIgnoreCase)
                    ? $" Note: {t.Port} is not on the server now (printer off or unplugged?)." : "";
                return Ok(new { message = (clear ? "Printer cleared." : $"Saved: {t.ConnName} {t.Display}.") + note });
            });
        }

        // POST: api/Settings/Printers/Test { kind, conn, name, port, address, baud, mode, width } — a short test page on the
        // printer as picked on the page (not saved yet); nothing picked = the saved one
        [HttpPost("Printers/Test")]
        public async Task<IActionResult> TestPrinter([FromBody] PrinterTestRequest request, [FromServices] PrinterConfig config)
        {
            var p = await config.GetAsync();
            var kind = (request?.Kind ?? "").Trim().ToLowerInvariant();
            if (request == null || kind is not ("bill" or "general" or "sticker"))
                return BadRequest(new { message = "Which printer: bill, general or sticker." });
            var picked = request.Conn != null || !string.IsNullOrWhiteSpace(request.Printer) || !string.IsNullOrWhiteSpace(request.Name);
            var t = picked
                ? ToTarget(kind, new PrinterSaveRequest
                {
                    Conn = request.Conn, Name = request.Name ?? request.Printer, Port = request.Port, Address = request.Address, Baud = request.Baud,
                })
                : kind switch
                {
                    "bill" => p.BillTarget,
                    "sticker" => p.StickerTarget,
                    _ => new PrinterTarget { Conn = PrinterTarget.Windows, Name = p.General },
                };
            if (!t.IsSet) return BadRequest(new { message = "Choose the printer first." });
            if (t.Problem() is { } problem) return BadRequest(new { message = problem });
            var chars = request.Width is 32 or 42 or 48 ? request.Width.Value : p.BillChars;
            var escPos = request.Mode != null ? request.Mode == "escpos" : p.BillEscPos;
            try
            {
                var now = DateTime.Now;
                switch (kind)
                {
                    case "bill":
                        var slip = new ReceiptSlip(chars);
                        slip.Line("PRINTER TEST", SlipAlign.Center, bold: true, tall: true);
                        slip.Line("Bill printer (thermal)", SlipAlign.Center);
                        slip.Divider();
                        slip.LeftRight("Printer", t.Display);
                        slip.LeftRight("Connection", t.ConnName);
                        slip.LeftRight("Time", now.ToString("yyyy-MM-dd HH:mm"));
                        slip.LeftRight("Characters a line", chars.ToString());
                        slip.Line(string.Concat(Enumerable.Range(1, chars).Select(i => (char)('0' + i % 10))));
                        slip.Divider('=');
                        await slip.PrintAsync(t, "Printer test", escPos);
                        break;
                    case "general":
                        await Task.Run(() => PrintGeneralTest(t.Name, now));
                        break;
                    case "sticker":
                        var zpl = $"^XA^CI28^CF0,28^FO20,20^FDPRINTER TEST^FS^CF0,22^FO20,60^FD{Zpl(t.Display)}^FS^FO20,90^FD{now:yyyy-MM-dd HH:mm}^FS^XZ";
                        await t.SendRawAsync(System.Text.Encoding.UTF8.GetBytes(zpl), "Printer test");
                        break;
                }
                return Ok(new { message = $"Test page sent to {t.Display}." });
            }
            catch (Exception ex)
            {
                Log.Error(ex, "Printer test on {Printer} failed", t.Display);
                return BadRequest(new { message = $"Could not print on {t.Display}: {ex.Message}" });
            }
        }

        private static PrinterTarget ToTarget(string kind, PrinterSaveRequest r) => new()
        {
            Conn = kind == "general" ? PrinterTarget.Windows : r.Conn is >= 1 and <= 3 ? r.Conn.Value : PrinterTarget.Windows,
            Name = (r.Name ?? "").Trim(),
            Port = (r.Port ?? "").Trim().ToUpperInvariant(),
            Address = (r.Address ?? "").Trim(),
            Baud = r.Baud ?? 38400,
        };

        private static List<string> SafePorts()
        {
            try { return RawPrinter.ListComPorts(); } catch { return new(); }
        }

        private static string Zpl(string s) => s.Replace("^", " ").Replace("~", " ");

        private static void PrintGeneralTest(string printer, DateTime now)
        {
            using var doc = new System.Drawing.Printing.PrintDocument();
            doc.PrinterSettings.PrinterName = printer;
            doc.PrintController = new System.Drawing.Printing.StandardPrintController();
            doc.DocumentName = "Printer test";
            doc.PrintPage += (_, e) =>
            {
                var g = e.Graphics!;
                using var big = new System.Drawing.Font("Arial", 18, System.Drawing.FontStyle.Bold);
                using var small = new System.Drawing.Font("Arial", 11);
                var x = e.MarginBounds.Left;
                var y = e.MarginBounds.Top;
                g.DrawString("PRINTER TEST", big, System.Drawing.Brushes.Black, x, y);
                g.DrawString($"General printer (cheques): {printer}", small, System.Drawing.Brushes.Black, x, y + 40);
                g.DrawString(now.ToString("yyyy-MM-dd HH:mm"), small, System.Drawing.Brushes.Black, x, y + 62);
                e.HasMorePages = false;
            };
            doc.Print();
        }

        // ---- Settings > Backup --------------------------------------------------------------------------------------------

        // GET: api/Settings/Backup — the daily backup: settings, running now, the last tries (U051)
        [HttpGet("Backup")]
        public async Task<IActionResult> Backup([FromServices] DbBackupService backup)
        {
            return await Run(async () =>
            {
                var s = await backup.ReadSettingsAsync();
                return Ok(new
                {
                    enabled = s.Enabled,
                    time = s.Time.ToString(@"hh\:mm"),
                    folder = s.Folder,
                    defaultFolder = DbBackupService.DefaultFolder,
                    databases = backup.DatabaseNames(),
                    running = backup.Running,
                    runningSince = backup.RunningSince,
                    runningDb = backup.RunningDb,
                    history = await backup.HistoryAsync(30),
                });
            });
        }

        // POST: api/Settings/Backup/Run — "Back up now" (runs in the background; GET Backup shows when it is done)
        [HttpPost("Backup/Run")]
        public IActionResult BackupNow([FromServices] DbBackupService backup)
        {
            return backup.StartNow(Me)
                ? Accepted(new { message = "Backup started." })
                : Conflict(new { message = "A backup is running now - wait for it to finish." });
        }

        private int Me => AuthTokenService.UserId(User);

        private async Task<IActionResult> Run(Func<Task<IActionResult>> action)
        {
            try
            {
                return await action();
            }
            catch (SqlException ex) when (ex.Number >= 50000)
            {
                return BadRequest(new { message = ex.Message });
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex}");
                return StatusCode(500, new { message = "Internal Server Error", error = ex.Message });
            }
        }
    }
}
