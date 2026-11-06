using System.Drawing.Printing;
using System.Text.RegularExpressions;
using ItemApi.Data;

namespace ItemApi.Service
{
    // The printers, chosen on Settings > Printers (z_tb_Setting, U050 / U051) - not in appsettings.json any more.
    //   Bill printer    (thermal / receipt): Cash Management print + settlement, return item slips, price labels by default
    //   General printer (normal, e.g. HP):   cheques (Cheque Writer) - a Windows printer only (drawn through its driver)
    //   Sticker printer (Zebra):             barcode labels by default
    // The bill and sticker printers can be a Windows printer, a COM port or a network printer (ip:port), as on the till
    // (U051). A label layout can still name its own printer. Read once per request (scoped).
    public class PrinterConfig
    {
        public const string BillKey = "Printer.Bill";
        public const string GeneralKey = "Printer.General";
        public const string StickerKey = "Printer.Sticker";
        public const string BillModeKey = "Printer.BillMode";
        public const string BillWidthKey = "Printer.BillWidth";

        // U051: how the bill / sticker printer is connected, and its COM port / network address / baud rate
        public static string ConnKey(string kind) => $"{Prefix(kind)}Conn";
        public static string PortKey(string kind) => $"{Prefix(kind)}Port";
        public static string AddressKey(string kind) => $"{Prefix(kind)}Address";
        public static string BaudKey(string kind) => $"{Prefix(kind)}Baud";
        public static string NameKey(string kind) => kind == "bill" ? BillKey : kind == "sticker" ? StickerKey : GeneralKey;
        private static string Prefix(string kind) => kind == "bill" ? BillKey : StickerKey;

        public static readonly int[] BaudRates = { 9600, 19200, 38400, 57600, 115200 };

        private readonly AppDbContext _context;
        private Printers? _printers;

        public PrinterConfig(AppDbContext context) => _context = context;

        public async Task<Printers> GetAsync()
        {
            if (_printers != null) return _printers;
            var s = (await _context.GetSettingsAsync()).ToDictionary(r => r.SettingKey, r => r.EffectiveValue?.Trim() ?? "");
            string V(string key) => s.TryGetValue(key, out var v) ? v : "";
            PrinterTarget Target(string kind) => new()
            {
                Conn = int.TryParse(V(ConnKey(kind)), out var c) && c is >= 1 and <= 3 ? c : PrinterTarget.Windows,
                Name = V(NameKey(kind)),
                Port = V(PortKey(kind)),
                Address = V(AddressKey(kind)),
                Baud = int.TryParse(V(BaudKey(kind)), out var b) && BaudRates.Contains(b) ? b : 38400,
            };
            _printers = new Printers
            {
                General = V(GeneralKey),
                BillTarget = Target("bill"),
                StickerTarget = Target("sticker"),
                BillEscPos = string.Equals(V(BillModeKey), "escpos", StringComparison.OrdinalIgnoreCase),
                BillChars = int.TryParse(V(BillWidthKey), out var w) && w is >= 24 and <= 64 ? w : 48,
            };
            return _printers;
        }

        // the printers installed on this server (Windows), for the Settings page
        public static List<string> Installed()
        {
            var list = new List<string>();
            foreach (string p in PrinterSettings.InstalledPrinters) list.Add(p);
            list.Sort(StringComparer.OrdinalIgnoreCase);
            return list;
        }
    }

    // Where a printer is: a Windows printer on the API server, a COM port on it, or a network printer "ip:port".
    public class PrinterTarget
    {
        public const int Windows = 1, Com = 2, Network = 3;

        public int Conn { get; set; } = Windows;
        public string Name { get; set; } = "";       // 1: Windows printer name
        public string Port { get; set; } = "";       // 2: "COM3"
        public string Address { get; set; } = "";    // 3: "192.168.1.50:9100" (9100 when left out)
        public int Baud { get; set; } = 38400;       // 2: only matters on a real serial cable

        // the printer as shown in messages: the Windows name, COM3 or the address
        public string Display => Conn switch { Com => Port, Network => Address, _ => Name };
        public bool IsSet => Display.Trim().Length > 0;
        public string ConnName => Conn switch { Com => "COM port", Network => "network", _ => "Windows printer" };

        // null = fine; else what is wrong (for saving and the test print)
        public string? Problem()
        {
            switch (Conn)
            {
                case Windows:
                    if (Name.Trim().Length == 0) return "Choose the Windows printer.";
                    return PrinterConfig.Installed().Contains(Name.Trim(), StringComparer.OrdinalIgnoreCase)
                        ? null : $"'{Name.Trim()}' is not installed on the server.";
                case Com:
                    if (!Regex.IsMatch(Port.Trim(), @"^COM\d{1,3}$", RegexOptions.IgnoreCase)) return "Choose the COM port (COM1, COM2, ...).";
                    return PrinterConfig.BaudRates.Contains(Baud) ? null : "Choose the baud rate.";
                case Network:
                    return Regex.IsMatch(Address.Trim(), @"^[A-Za-z0-9.\-]{1,60}(:\d{1,5})?$")
                        ? null : "Type the printer address, e.g. 192.168.1.50:9100.";
                default:
                    return "Choose how the printer is connected.";
            }
        }

        // ready-made printer bytes (ESC/POS, ZPL) straight to the printer
        public Task SendRawAsync(byte[] data, string docName) => Conn switch
        {
            Com => RawPrinter.SendToSerialAsync(Port, Baud, data, TimeSpan.FromSeconds(10)),
            Network => RawPrinter.SendToNetworkAsync(Address, data, TimeSpan.FromSeconds(10)),
            _ => Task.Run(() => RawPrinter.SendToWindowsPrinter(Name.Trim(), data, docName)),
        };
    }

    public class Printers
    {
        public string General { get; set; } = "";
        public PrinterTarget BillTarget { get; set; } = new();
        public PrinterTarget StickerTarget { get; set; } = new();
        // bill printer as a Windows printer: through its driver (false, default) or ESC/POS bytes (true).
        // A COM port / network bill printer always gets ESC/POS.
        public bool BillEscPos { get; set; }
        public int BillChars { get; set; } = 48;

        // the bill printer's Windows name ("" when it is on a COM port / network) - for prints drawn through a driver
        public string Bill => BillTarget.Conn == PrinterTarget.Windows ? BillTarget.Name : "";
        // the sticker printer's Windows name ("" when on a COM port / network)
        public string Sticker => StickerTarget.Conn == PrinterTarget.Windows ? StickerTarget.Name : "";

        public PrinterTarget NeedBill() => Need(BillTarget, "bill printer (thermal)");
        public PrinterTarget NeedSticker() => Need(StickerTarget, "sticker printer");
        public string NeedGeneral() =>
            string.IsNullOrWhiteSpace(General)
                ? throw new PrinterNotSetException("No general printer (cheques) is chosen - choose it on Settings > Printers.")
                : General;

        private static PrinterTarget Need(PrinterTarget t, string what) =>
            t.IsSet ? t : throw new PrinterNotSetException($"No {what} is chosen - choose it on Settings > Printers.");
    }

    public class PrinterNotSetException : InvalidOperationException
    {
        public PrinterNotSetException(string message) : base(message) { }
    }
}
