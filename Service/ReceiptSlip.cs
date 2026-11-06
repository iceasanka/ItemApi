using System.Drawing;
using System.Drawing.Printing;
using System.Globalization;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using ItemApi.Models;

namespace ItemApi.Service
{
    public enum SlipAlign { Left, Center, Right }

    // A short slip for the 80 mm receipt printer, built line by line and printed as ESC/POS - straight to the printer,
    // no BarTender, no LocalPrintAgent. Same idea as TillService/Printing/ReceiptDoc.cs (the till receipts).
    // Width = characters per line in the normal font (80 mm paper: 48, 58 mm paper: 32).
    public class ReceiptSlip
    {
        private record SlipLine(string Text, SlipAlign Align, bool Bold, bool Tall, bool Wide);

        private readonly List<SlipLine> _lines = new();

        public ReceiptSlip(int width) => Width = Math.Clamp(width, 24, 64);

        public int Width { get; }

        public void Line(string text = "", SlipAlign align = SlipAlign.Left, bool bold = false, bool tall = false, bool wide = false)
        {
            var max = wide ? Width / 2 : Width;
            text = ToPrintable(text);
            _lines.Add(new SlipLine(text.Length > max ? text[..max] : text, align, bold, tall, wide));
        }

        public void Divider(char c = '-') => Line(new string(c, Width));

        // "Cashier cash                15,000.00" - the right part is never cut, the left part is when both don't fit
        public void LeftRight(string left, string right, bool bold = false, bool tall = false, bool wide = false)
        {
            var max = wide ? Width / 2 : Width;
            left = ToPrintable(left);
            right = ToPrintable(right);
            var room = Math.Max(0, max - right.Length - 1);
            if (left.Length > room)
                left = left[..room];
            Line(left + new string(' ', Math.Max(1, max - left.Length - right.Length)) + right, SlipAlign.Left, bold, tall, wide);
        }

        // ESC/POS (Epson standard - understood by practically every receipt printer), then feed and a partial cut
        public byte[] ToEscPos(int feedLines = 4, bool cut = true)
        {
            var b = new List<byte> { 0x1B, 0x40 };                                                  // ESC @  initialise
            foreach (var l in _lines)
            {
                b.AddRange(new byte[] { 0x1B, 0x61, (byte)l.Align });                               // ESC a  alignment
                b.AddRange(new byte[] { 0x1B, 0x45, (byte)(l.Bold ? 1 : 0) });                     // ESC E  bold
                b.AddRange(new byte[] { 0x1D, 0x21, (byte)((l.Wide ? 0x10 : 0) | (l.Tall ? 0x01 : 0)) });   // GS !  size
                b.AddRange(Encoding.ASCII.GetBytes(l.Text));
                b.Add(0x0A);
            }
            b.AddRange(new byte[] { 0x1B, 0x61, 0, 0x1B, 0x45, 0, 0x1D, 0x21, 0 });                  // back to normal
            b.AddRange(new byte[] { 0x1B, 0x64, (byte)Math.Clamp(feedLines, 0, 20) });              // ESC d  feed past the cutter
            if (cut)
                b.AddRange(new byte[] { 0x1D, 0x56, 0x01 });                                         // GS V  partial cut
            return b.ToArray();
        }

        public static string Money(decimal value) => value.ToString("#,##0.00", CultureInfo.InvariantCulture);

        // printer = Windows printer name (e.g. PegasusPR8003) or "ip:port" (network printer: always ESC/POS).
        // escPos false (Settings > Printers > bill printer mode "driver", the default) = a normal Windows print through the printer's
        // own driver, as the old Cash Management print did - works on any printer (thermal or not). true = raw ESC/POS
        // bytes (only for a printer / driver that passes them through).
        // Settings > Printers bill printer: a Windows printer as below; a COM port / network printer always gets ESC/POS
        public async Task PrintAsync(PrinterTarget target, string docName, bool escPos)
        {
            if (!target.IsSet)
                throw new InvalidOperationException("No bill printer (thermal) is chosen - choose it on Settings > Printers.");
            if (target.Conn == PrinterTarget.Windows)
                await PrintAsync(target.Name, docName, escPos);
            else
                await target.SendRawAsync(ToEscPos(), docName);
        }

        public async Task PrintAsync(string printer, string docName, bool escPos)
        {
            printer = printer.Trim();
            if (printer.Length == 0)
                throw new InvalidOperationException("No bill printer (thermal) is chosen - choose it on Settings > Printers.");
            if (Regex.IsMatch(printer, @"^[\w.\-]+:\d{1,5}$"))
                await RawPrinter.SendToNetworkAsync(printer, ToEscPos(), TimeSpan.FromSeconds(10));
            else if (escPos)
                await Task.Run(() => RawPrinter.SendToWindowsPrinter(printer, ToEscPos(), docName));
            else
                await Task.Run(() => PrintWithDriver(printer, docName, new StandardPrintController()));
        }

        // ---- through the Windows driver: the slip drawn in a fixed-width font, as wide as the paper allows ----------

        private const string DriverFont = "Courier New";

        public void PrintWithDriver(string printer, string docName, PrintController controller)
        {
            using var doc = new PrintDocument();
            doc.PrinterSettings.PrinterName = printer;
            if (!doc.PrinterSettings.IsValid)
                throw new InvalidOperationException($"Printer '{printer}' is not installed on the server.");
            doc.PrintController = controller;   // StandardPrintController: no "Printing..." window on the server
            doc.DocumentName = docName;
            doc.OriginAtMargins = false;
            doc.DefaultPageSettings.Margins = new Margins(0, 0, 0, 0);

            // paper as long as the slip (roll printers cut there); the width is the driver's own paper width
            var paper = doc.DefaultPageSettings.PaperSize;
            var widthIn100 = paper.Width > 0 ? paper.Width : 315;   // 80 mm
            var printableMm = doc.DefaultPageSettings.PrintableArea.Width > 0
                ? (float)doc.DefaultPageSettings.PrintableArea.Width * 0.254f
                : widthIn100 * 0.254f - 8;
            var em = FontEmMm(printableMm);
            var lineMm = em * 1.2f;
            var heightMm = _lines.Sum(l => lineMm * (l.Tall ? 2 : 1)) + 25;   // + feed past the cutter
            doc.DefaultPageSettings.PaperSize = new PaperSize("Slip", widthIn100, Math.Max(100, (int)Math.Ceiling(heightMm / 0.254f)));

            var next = 0;
            Exception? drawError = null;
            doc.PrintPage += (_, e) =>
            {
                try
                {
                    var g = e.Graphics!;
                    g.PageUnit = GraphicsUnit.Millimeter;
                    // (0,0) = the corner of the printable area - the slip starts there
                    var bottom = e.PageSettings.PrintableArea.Height * 0.254f;
                    var y = 1f;
                    while (next < _lines.Count)
                    {
                        var l = _lines[next];
                        var h = lineMm * (l.Tall ? 2 : 1);
                        if (y + h > bottom && y > 1f) break;   // next page
                        DrawLine(g, l, y, em);
                        y += h;
                        next++;
                    }
                    e.HasMorePages = next < _lines.Count;
                }
                catch (Exception ex)
                {
                    drawError = ex;
                    e.HasMorePages = false;
                }
            };
            doc.Print();
            if (drawError != null)
                throw new InvalidOperationException($"Could not draw the slip: {drawError.Message}");
        }

        // Width characters of Courier New (a character is 0.6 of the font size wide) across the printable width
        private float FontEmMm(float printableMm) => Math.Clamp(printableMm * 0.96f / (Width * 0.6f), 1.8f, 4.5f);   // a small margin on the right

        private void DrawLine(Graphics g, SlipLine l, float y, float em)
        {
            var chars = l.Wide ? Width / 2 : Width;
            var pad = l.Align == SlipAlign.Center ? Math.Max(0, (chars - l.Text.Length) / 2)
                    : l.Align == SlipAlign.Right ? Math.Max(0, chars - l.Text.Length) : 0;
            using var font = new Font(DriverFont, em, l.Bold ? FontStyle.Bold : FontStyle.Regular, GraphicsUnit.World);
            var state = g.Save();
            g.TranslateTransform(0, y);
            g.ScaleTransform(l.Wide ? 2 : 1, l.Tall ? 2 : 1);   // double width / height, as ESC/POS GS !
            g.DrawString(l.Text, font, Brushes.Black, pad * em * 0.6f, 0, StringFormat.GenericTypographic);   // a Courier New character is 0.6 em wide
            g.Restore(state);
        }

        // Cash Management > Print Settlement - the values the old BarTender SettlementPrint.btw printed
        public static ReceiptSlip Settlement(CashierSettlement s, int width, DateTime now)
        {
            var doc = new ReceiptSlip(width);
            doc.Line("CASHIER SETTLEMENT", SlipAlign.Center, bold: true, tall: true);
            doc.LeftRight($"Date: {now:yyyy-MM-dd}", $"Time: {now:HH:mm}");
            doc.Divider();
            doc.LeftRight("Total cash balance", Money(s.TotalCashBalance));
            doc.LeftRight("Cashier cash", Money(s.CashierCash));
            doc.LeftRight("Returned coins", Money(s.ReturnedCoinsValue));
            doc.Divider();
            doc.LeftRight("Total returned to cashier", Money(s.TotalReturnedToCashier), bold: true);
            doc.Divider('=');
            doc.LeftRight("CASH TO BANK", Money(s.CashBank), bold: true, tall: true);
            doc.Divider('=');
            return doc;
        }

        // Cash Management > Print - notes counted, cash in, cash out, the balance and what goes back to the cashier
        public static ReceiptSlip CashManagement(PrintRequest r, int width, DateTime now)
        {
            var doc = new ReceiptSlip(width);
            doc.Line("CASH MANAGEMENT", SlipAlign.Center, bold: true, tall: true);
            doc.LeftRight($"Date: {now:yyyy-MM-dd}", $"Time: {now:HH:mm}");
            doc.Divider('=');

            doc.Line("TOTAL CASH", bold: true);
            var qtyCol = Math.Max(4, doc.Width / 4);
            doc.LeftRight("Note".PadRight(qtyCol) + "Qty", "Amount");
            doc.Divider();
            foreach (var row in r.CashTable.Rows)
            {
                var note = Num(row, "cash");
                var qty = Num(row, "qty");
                if (qty == 0)
                    continue;
                doc.LeftRight(Plain(note).PadRight(qtyCol) + Plain(qty), Money(note * qty));
            }
            doc.Divider();
            doc.LeftRight("TOTAL CASH", Money(r.CashTable.Total), bold: true);

            Section(doc, "CASH IN", r.CreditTable, "credit", "TOTAL CASH IN");
            Section(doc, "CASH OUT", r.DebitTable, "debit", "TOTAL CASH OUT");

            doc.Divider('=');
            doc.LeftRight("CASH BALANCE", Money(r.TotalCashBalance), bold: true, tall: true);
            doc.Divider('=');
            doc.LeftRight("Cashier cash", Money(r.CashierCash));
            doc.LeftRight("Returned coins", Money(r.ReturnedCoinsValue));
            doc.LeftRight("Returned to cashier", Money(r.TotalReturnedToCashier), bold: true);
            doc.Divider();
            doc.LeftRight("CASH TO BANK", Money(r.FinalCashBalance), bold: true, tall: true);
            doc.Divider('=');
            return doc;
        }

        private static void Section(ReceiptSlip doc, string title, TableData table, string textKey, string totalLabel)
        {
            doc.Line();
            doc.Line(title, bold: true);
            doc.Divider();
            var any = false;
            foreach (var row in table.Rows)
            {
                var text = Str(row, textKey);
                var amount = Num(row, "amount");
                if (amount == 0 && text.Length == 0)
                    continue;
                doc.LeftRight(text.Length == 0 ? "-" : text, Money(amount));
                any = true;
            }
            if (!any)
                doc.Line("(none)");
            doc.Divider();
            doc.LeftRight(totalLabel, Money(table.Total), bold: true);
        }

        private static string Plain(decimal n) => n.ToString("0.##", CultureInfo.InvariantCulture);

        // the rows arrive as JSON (System.Text.Json gives JsonElement for object values)
        private static decimal Num(Dictionary<string, object> row, string key)
        {
            var v = Find(row, key);
            return v switch
            {
                JsonElement { ValueKind: JsonValueKind.Number } e => e.GetDecimal(),
                JsonElement { ValueKind: JsonValueKind.String } e when decimal.TryParse(e.GetString(), NumberStyles.Any, CultureInfo.InvariantCulture, out var d) => d,
                IConvertible c => Convert.ToDecimal(c, CultureInfo.InvariantCulture),
                _ => 0,
            };
        }

        private static string Str(Dictionary<string, object> row, string key) => Find(row, key) switch
        {
            JsonElement { ValueKind: JsonValueKind.String } e => e.GetString()?.Trim() ?? "",
            JsonElement { ValueKind: JsonValueKind.Null or JsonValueKind.Undefined } => "",
            JsonElement e => e.ToString().Trim(),
            null => "",
            var o => o.ToString()?.Trim() ?? "",
        };

        private static object? Find(Dictionary<string, object> row, string key) =>
            row.FirstOrDefault(kv => string.Equals(kv.Key, key, StringComparison.OrdinalIgnoreCase)).Value;

        // Receipt printers print ASCII reliably; accents are dropped and anything else becomes '?'
        private static string ToPrintable(string? text)
        {
            if (string.IsNullOrEmpty(text))
                return "";
            var sb = new StringBuilder(text.Length);
            foreach (var ch in text.Normalize(NormalizationForm.FormD))
            {
                if (CharUnicodeInfo.GetUnicodeCategory(ch) == UnicodeCategory.NonSpacingMark)
                    continue;
                sb.Append(ch is >= ' ' and <= '~' ? ch : ch is '\t' ? ' ' : '?');
            }
            return sb.ToString();
        }
    }
}
