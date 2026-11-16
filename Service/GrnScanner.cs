using System.Reflection;
using System.Runtime.InteropServices;
using ItemApi.Data;
using ItemApi.Models;

namespace ItemApi.Service
{
    // GRN scan settings (z_tb_Setting group "Scanner", U061) - Settings > Scanner.
    //   Scanner.Device   WIA device id of the scanner on the server where ItemApi runs ("" = none chosen)
    //   Scanner.Dpi      150 / 200 (default) / 300 - what the scanner scans at
    //   Scanner.Source   flatbed (one page a click) / feeder (every page in the document feeder, up to 4)
    //   GrnScan.ImageSize  long side in pixels every page (scanned or uploaded) is made down to before Gemini: 1600 /
    //                      2000 / 2400 (default) / 3200 / 0 = as it came
    //   GrnScan.ImageColor color / gray (default) / bw
    public class GrnScanConfig
    {
        public const string DeviceKey = "Scanner.Device", DpiKey = "Scanner.Dpi", SourceKey = "Scanner.Source";
        public const string SizeKey = "GrnScan.ImageSize", ColorKey = "GrnScan.ImageColor";

        public string Device { get; set; } = "";
        public int Dpi { get; set; } = 200;
        public bool Feeder { get; set; }
        public int MaxSide { get; set; } = 2400;
        public string Color { get; set; } = GrnScanImage.Gray;

        // the settings, or the defaults on a db without U061
        public static async Task<GrnScanConfig> LoadAsync(AppDbContext db)
        {
            var c = new GrnScanConfig();
            List<SettingRow> rows;
            try { rows = await db.GetSettingsAsync(); }
            catch (Microsoft.Data.SqlClient.SqlException) { return c; }
            var s = rows.ToDictionary(r => r.SettingKey, r => r.EffectiveValue?.Trim() ?? "");
            string V(string key) => s.TryGetValue(key, out var v) ? v : "";
            c.Device = V(DeviceKey);
            if (int.TryParse(V(DpiKey), out var dpi) && dpi is >= 75 and <= 600) c.Dpi = dpi;
            c.Feeder = V(SourceKey) == "feeder";
            if (int.TryParse(V(SizeKey), out var side) && (side == 0 || side is >= 1000 and <= 6000)) c.MaxSide = side;
            if (V(ColorKey) is GrnScanImage.Color or GrnScanImage.Gray or GrnScanImage.Bw) c.Color = V(ColorKey);
            return c;
        }
    }

    public class ScannerDevice
    {
        public string Id { get; set; } = "";
        public string Name { get; set; } = "";
        public int Type { get; set; } = 1;   // WIA device type: 1 scanner, 2 camera, 3 video
        // anything but a camera / video is taken as a scanner: some drivers give another type (HP Laser MFP 135a: 65535)
        public bool IsScanner => Type is not (2 or 3);
    }

    // how ItemApi runs - why WIA may see no scanner (Settings > Scanner shows it when none is found)
    public static class ScannerDiagnostics
    {
        public static object Get(List<ScannerDevice> all)
        {
            var p = System.Diagnostics.Process.GetCurrentProcess();
            string? wia = null;
            try
            {
                // the Windows Image Acquisition service (stisvc) must be running
                var psi = new System.Diagnostics.ProcessStartInfo("sc.exe", "query stisvc") { RedirectStandardOutput = true, UseShellExecute = false, CreateNoWindow = true };
                using var sc = System.Diagnostics.Process.Start(psi)!;
                var o = sc.StandardOutput.ReadToEnd();
                sc.WaitForExit(5000);
                wia = o.Contains("RUNNING") ? "running" : o.Contains("STOPPED") ? "stopped" : "unknown";
            }
            catch (Exception) { /* not allowed */ }
            return new
            {
                runAs = $"{Environment.UserDomainName}\\{Environment.UserName}",
                process = p.ProcessName,          // w3wp = IIS, ItemApi = run by hand / as a service
                session = p.SessionId,            // 0 = a service / IIS (no desktop): USB scanners are often not seen there
                interactive = Environment.UserInteractive,
                is64Bit = Environment.Is64BitProcess,
                wiaService = wia,
                otherDevices = all.Where(d => !d.IsScanner).Select(d => $"{d.Name} (type {d.Type})").ToList(),
            };
        }
    }

    // The scanner on the server where ItemApi runs (as the printers of Settings > Printers), through Windows Image
    // Acquisition (WIA 2.0 automation, wiaaut.dll - part of Windows). Any scanner / multi-function printer with a WIA
    // driver (Windows "Scanners and Cameras" shows it). One scan at a time; WIA needs an STA thread.
    // ItemApi in IIS: the app pool must run as a user that can see the scanner (as for the printers, §6.37).
    public static class GrnScanner
    {
        private const string FormatBmp = "{B96B3CAB-0728-11D3-9D7B-0000F81EF32E}";
        // device properties
        private const int DocumentHandlingSelect = 3088, Pages = 3096;
        private const int Feeder = 1, Flatbed = 2;
        // item properties
        private const int CurrentIntent = 6146, XResolution = 6147, YResolution = 6148, XExtent = 6151, YExtent = 6152;
        private const int IntentColor = 1, IntentGray = 2;
        private static readonly SemaphoreSlim Gate = new(1, 1);

        // every WIA device ItemApi can see (Type 1 = scanner, 2 = camera, 3 = video) - Settings > Scanner lists the scanners
        // and tells what else was seen (to find out why a scanner is missing)
        public static Task<List<ScannerDevice>> ListAsync() => Sta(() =>
        {
            var list = new List<ScannerDevice>();
            dynamic mgr = Manager();
            try
            {
                foreach (dynamic info in mgr.DeviceInfos)
                {
                    string id = info.DeviceID;
                    // the type may come packed as the STI type in the high word + subtype in the low word
                    var type = (int)info.Type;
                    if (type > 0xFFFF) type >>= 16;
                    list.Add(new ScannerDevice { Id = id, Name = Text((object)info.Properties, "Name") ?? id, Type = type });
                }
            }
            finally { Marshal.FinalReleaseComObject(mgr); }
            return list.OrderBy(d => d.Name, StringComparer.OrdinalIgnoreCase).ToList();
        }, TimeSpan.FromSeconds(30));

        // flatbed: one page; feeder: every page in the feeder (at most maxPages). Raw images as the scanner gave them.
        public static async Task<List<byte[]>> ScanAsync(GrnScanConfig cfg, int maxPages, CancellationToken ct)
        {
            if (string.IsNullOrWhiteSpace(cfg.Device))
                throw new GrnScanException("No scanner chosen - choose it on Settings > Scanner.");
            if (!await Gate.WaitAsync(TimeSpan.FromSeconds(5), ct))
                throw new GrnScanException("The scanner is busy with another scan - try again in a moment.", 409);
            try
            {
                return await Sta(() => Scan(cfg, maxPages), TimeSpan.FromMinutes(3));
            }
            finally { Gate.Release(); }
        }

        private static List<byte[]> Scan(GrnScanConfig cfg, int maxPages)
        {
            dynamic mgr = Manager();
            dynamic? device = null;
            try
            {
                foreach (dynamic info in mgr.DeviceInfos)
                    if ((string)info.DeviceID == cfg.Device) { device = info.Connect(); break; }
                if (device == null)
                    throw new GrnScanException("The scanner chosen on Settings > Scanner is not there - is it on and connected? Choose it again if it was changed.", 503);

                // flatbed or document feeder (a scanner without a feeder has no such property: flatbed)
                Set((object)device.Properties, DocumentHandlingSelect, cfg.Feeder ? Feeder : Flatbed);
                if (cfg.Feeder) Set((object)device.Properties, Pages, 1);

                dynamic? item = null;
                foreach (dynamic it in device.Items) { item = it; break; }
                if (item == null) throw new GrnScanException("The scanner has nothing to scan from.", 503);
                // intent first (it resets the resolution on some drivers), then the resolution, then the whole bed
                Set((object)item.Properties, CurrentIntent, cfg.Color == GrnScanImage.Color ? IntentColor : IntentGray);
                Set((object)item.Properties, XResolution, cfg.Dpi);
                Set((object)item.Properties, YResolution, cfg.Dpi);
                SetMax((object)item.Properties, XExtent);
                SetMax((object)item.Properties, YExtent);

                var pages = new List<byte[]>();
                while (pages.Count < Math.Max(1, maxPages))
                {
                    dynamic img;
                    try { img = item.Transfer(FormatBmp); }
                    catch (COMException ex) when (pages.Count > 0 && (uint)ex.HResult == 0x80210003)
                    {
                        break;   // feeder empty after the last page
                    }
                    catch (COMException ex)
                    {
                        throw new GrnScanException(WiaError(ex, cfg.Feeder), 503);
                    }
                    byte[] data = (byte[])img.FileData.BinaryData;
                    Marshal.FinalReleaseComObject(img);
                    pages.Add(data);
                    if (!cfg.Feeder) break;
                }
                return pages;
            }
            catch (COMException ex)
            {
                throw new GrnScanException(WiaError(ex, cfg.Feeder), 503);
            }
            finally
            {
                if (device != null) Marshal.FinalReleaseComObject(device);
                Marshal.FinalReleaseComObject(mgr);
            }
        }

        private static object Manager()
        {
            var type = Type.GetTypeFromProgID("WIA.DeviceManager")
                ?? throw new GrnScanException("Windows Image Acquisition (WIA) is not on this server.", 503);
            try { return Activator.CreateInstance(type)!; }
            catch (COMException ex) { throw new GrnScanException("WIA could not start on the server: " + ex.Message, 503); }
        }

        private static string WiaError(COMException ex, bool feeder) => (uint)ex.HResult switch
        {
            0x80210003 => feeder ? "No paper in the document feeder." : "No paper on the scanner.",
            0x80210002 => "Paper jam in the scanner.",
            0x80210005 => "The scanner is off or not connected.",
            0x80210006 => "The scanner is busy - try again in a moment.",
            0x80210016 => "The scanner lid / cover is open.",
            0x8021000A => "The scanner does not answer (cable / network?).",
            0x80210015 => "No scanner found - is it on and connected?",
            0x80070005 => "The server may not use the scanner (access denied - IIS: run the app pool as a user who can).",
            _ => $"Scan failed: {ex.Message} (0x{ex.HResult:X8})",
        };

        // ─── WIA properties (late bound) ───

        private static dynamic? Find(object props, int id)
        {
            foreach (dynamic p in (dynamic)props)
                if ((int)p.PropertyID == id) return p;
            return null;
        }

        private static string? Text(object props, string name)
        {
            foreach (dynamic p in (dynamic)props)
                if ((string)p.Name == name) return Convert.ToString((object)p.Value);
            return null;
        }

        // a value the driver does not take is left as it is (the scan still works, at the driver's own value)
        private static void Set(object props, int id, object value)
        {
            var p = Find(props, id);
            if (p == null) return;
            try { p.Value = value; }
            catch (Exception)
            {
                try { ((object)p).GetType().InvokeMember("Value", BindingFlags.SetProperty, null, (object)p, new[] { value }); }
                catch (Exception) { /* not taken */ }
            }
        }

        private static void SetMax(object props, int id)
        {
            var p = Find(props, id);
            if (p == null) return;
            try { Set(props, id, (int)p.SubTypeMax); } catch (Exception) { /* no range */ }
        }

        private static Task<T> Sta<T>(Func<T> work, TimeSpan timeout)
        {
            var tcs = new TaskCompletionSource<T>(TaskCreationOptions.RunContinuationsAsynchronously);
            var t = new Thread(() =>
            {
                try { tcs.SetResult(work()); }
                catch (TargetInvocationException ex) when (ex.InnerException != null) { tcs.SetException(ex.InnerException); }
                catch (Exception ex) { tcs.SetException(ex); }
            }) { IsBackground = true, Name = "WIA scan" };
            t.SetApartmentState(ApartmentState.STA);
            t.Start();
            return tcs.Task.WaitAsync(timeout).ContinueWith(task =>
                task.Exception?.InnerException is TimeoutException
                    ? throw new GrnScanException("The scanner did not finish in time.", 504)
                    : task.GetAwaiter().GetResult(), TaskScheduler.Default);
        }
    }
}
