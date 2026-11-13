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
        // BarcodeHeight > 0 = Text is printed as a CODE128 barcode that many dots high (8 dots = 1 mm), centred
        private record SlipLine(string Text, SlipAlign Align, bool Bold, bool Tall, bool Wide, int BarcodeHeight = 0);

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

        // CODE128 barcode, centred, no text under it (the caller prints the code where it wants it). Same as the till's
        // ReceiptDoc.Barcode. Skipped when the data can't be a barcode that fits: the slip still prints.
        public void Barcode(string? data, int heightDots = 64)
        {
            data = data?.Trim() ?? "";
            if (data.Length is 0 or > 20 || !Code128.CanEncode(data) || data.Contains('{'))
                return;
            _lines.Add(new SlipLine(data, SlipAlign.Center, false, false, false, Math.Clamp(heightDots, 16, 160)));
        }

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

        // A table: 1 cell = a line, 2 cells = label + value (LeftRight), more = the first column takes what the right-aligned
        // columns leave; when that is too narrow the first cell gets a line of its own and the rest go right under it.
        // A head row is followed by a divider.
        public void Table(IReadOnlyList<(IReadOnlyList<string> Cells, bool Bold, bool Head)> rows)
        {
            var clean = rows.Select(r => (Cells: r.Cells.Select(c => ToPrintable(c).Trim()).ToList(), r.Bold, r.Head))
                            .Where(r => r.Cells.Any(c => c.Length > 0)).ToList();
            var n = clean.Count == 0 ? 0 : clean.Max(r => r.Cells.Count);
            var widths = new int[Math.Max(n, 1)];
            foreach (var r in clean.Where(r => r.Cells.Count == n && n > 2))
                for (var i = 1; i < n; i++)
                    widths[i] = Math.Max(widths[i], r.Cells[i].Length);
            var first = Width - widths.Skip(1).Sum() - (n - 1);
            foreach (var (cells, bold, head) in clean)
            {
                if (cells.Count == 1)
                    Line(cells[0], bold: bold || head);
                else if (cells.Count == 2 || n <= 2)
                    LeftRight(cells[0], string.Join(" ", cells.Skip(1)), bold: bold || head);
                else if (cells.Count < n)
                    LeftRight(string.Join(" ", cells.Take(cells.Count - 1).Where(c => c.Length > 0)), cells[^1], bold: bold || head);
                else
                {
                    var right = string.Join(" ", cells.Skip(1).Select((c, i) => c.PadLeft(widths[i + 1])));
                    if (first >= 6)
                        Line((cells[0].Length > first ? cells[0][..first] : cells[0].PadRight(first)) + " " + right, bold: bold || head);
                    else
                    {
                        if (cells[0].Length > 0)
                            Line(cells[0], bold: bold || head);
                        Line(right, SlipAlign.Right, bold: bold || head);
                    }
                }
                if (head)
                    Divider();
            }
        }

        // ESC/POS (Epson standard - understood by practically every receipt printer), then feed and a partial cut
        public byte[] ToEscPos(int feedLines = 4, bool cut = true)
        {
            var b = new List<byte> { 0x1B, 0x40 };                                                  // ESC @  initialise
            foreach (var l in _lines)
            {
                b.AddRange(new byte[] { 0x1B, 0x61, (byte)l.Align });                               // ESC a  alignment
                if (l.BarcodeHeight > 0)
                {
                    b.AddRange(new byte[] { 0x1D, 0x68, (byte)l.BarcodeHeight });                   // GS h  bar height in dots
                    b.AddRange(new byte[] { 0x1D, 0x77, 2 });                                       // GS w  thinnest bar 2 dots
                    b.AddRange(new byte[] { 0x1D, 0x48, 0 });                                       // GS H  no text under the bars
                    b.AddRange(new byte[] { 0x1D, 0x6B, 73, (byte)(l.Text.Length + 2), 0x7B, 0x42 });   // GS k 73 n {B  CODE128 set B
                    b.AddRange(Encoding.ASCII.GetBytes(l.Text));                                    // the printer feeds the paper itself
                    continue;
                }
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
            var heightMm = _lines.Sum(l => LineHeightMm(l, lineMm)) + 25;   // + feed past the cutter
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
                        var h = LineHeightMm(l, lineMm);
                        if (y + h > bottom && y > 1f) break;   // next page
                        if (l.BarcodeHeight > 0)
                            DrawBarcode(g, l, y, printableMm);
                        else
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

        // a barcode: its height (8 dots = 1 mm) + 2 mm room under it; a text line: one or two lines high
        private static float LineHeightMm(SlipLine l, float lineMm) =>
            l.BarcodeHeight > 0 ? l.BarcodeHeight / 8f + 2f : lineMm * (l.Tall ? 2 : 1);

        // CODE128 drawn as rectangles, centred: the thinnest bar 0.25 mm (2 dots at 203 dpi, as GS w 2), thinner when
        // the code would not fit the paper with a 3 mm quiet zone on each side
        private static void DrawBarcode(Graphics g, SlipLine l, float y, float printableMm)
        {
            var widths = Code128.Widths(l.Text);
            var modules = widths.Sum();
            var moduleMm = Math.Min(0.25f, (printableMm - 6f) / modules);
            var x = Math.Max(0f, (printableMm - modules * moduleMm) / 2f);
            var height = l.BarcodeHeight / 8f;
            for (int i = 0; i < widths.Count; i++)
            {
                var w = widths[i] * moduleMm;
                if (i % 2 == 0)   // bars at even places, spaces between
                    g.FillRectangle(Brushes.Black, x, y, w, height);
                x += w;
            }
        }

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

        // Cash Management > Print - notes counted, cash in, cash out, the balance and what goes back to the cashier.
        // slip = a saved cash slip (U055): its number, till and cashier on top, its barcode at the end - scanned on that
        // till at day end (counted cash) and at the next opening cash (the cash returned).
        public static ReceiptSlip CashManagement(PrintRequest r, int width, DateTime now, CashSettlementRow? slip = null)
        {
            var doc = new ReceiptSlip(width);
            doc.Line(slip == null ? "CASH MANAGEMENT" : "CASH SLIP", SlipAlign.Center, bold: true, tall: true);
            if (slip?.Status == 0)
                doc.Line("*** CANCELLED - DO NOT SCAN ***", SlipAlign.Center, bold: true);
            doc.LeftRight($"Date: {now:yyyy-MM-dd}", $"Time: {now:HH:mm}");
            if (slip != null)
            {
                doc.LeftRight($"Slip: {slip.SettlementId}", $"Till: {slip.TerminalCode}", bold: true);
                if (!string.IsNullOrEmpty(slip.CashierId))
                    doc.Line($"Cashier: {slip.CashierName ?? slip.CashierId}");
                doc.Line($"Counted: {slip.CreatedAt:yyyy-MM-dd HH:mm}{(string.IsNullOrEmpty(slip.CreatedBy) ? "" : " by " + slip.CreatedBy)}");
            }
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
            if (slip != null && slip.Status == 1)
            {
                doc.Line();
                doc.Line($"Scan on till {slip.TerminalCode}:", SlipAlign.Center, bold: true);
                doc.Line($"Day end  - counted {Money(slip.CountedCash)}", SlipAlign.Center);
                doc.Line($"Opening  - cash {Money(slip.ReturnedCash)}", SlipAlign.Center);
                doc.Barcode(slip.Barcode, 64);
                doc.Line(slip.Barcode, SlipAlign.Center, bold: true);
            }
            return doc;
        }

        // Day Reports > Bill copy > Print 80mm - a copy of an uploaded bill on the bill printer, no print preview
        public static ReceiptSlip BillCopy(DayBillDetail b, int width, string? shop, DateTime now)
        {
            var doc = new ReceiptSlip(width);
            if (!string.IsNullOrWhiteSpace(shop))
                doc.Line(shop.Trim(), SlipAlign.Center, bold: true, tall: true);
            doc.Line("***** COPY *****", SlipAlign.Center, bold: true);
            doc.Line($"{(b.InvType == 2 ? "REFUND " : "")}{b.InvoiceNo}{(b.Status == 9 ? " - VOIDED" : "")}", SlipAlign.Center, bold: true);
            doc.LeftRight($"{b.InvDate:yyyy-MM-dd HH:mm}", $"{b.TerminalCode} Z{b.ZNo}");
            var cashier = b.CashierName ?? b.CashierId;
            if (!string.IsNullOrWhiteSpace(cashier))
                doc.Line($"Cashier: {cashier}");
            doc.Divider();
            foreach (var l in b.Lines)
            {
                doc.Line((l.Name ?? l.RefCode ?? l.ItemId.ToString()) + (l.PriceType == 2 ? " (W)" : ""));
                doc.LeftRight($"  {Qty(l.Qty)} x {Money(l.UnitPrice)}" + (l.Discount != 0 ? $"  -{Money(l.Discount)}" : ""), Money(l.Amount));
            }
            doc.Divider();
            if (b.ItemDiscount != 0)
                doc.LeftRight("Item discounts", Money(b.ItemDiscount));
            doc.LeftRight("Sub total", Money(b.GrossAmount));
            if (b.Discount != 0)
                doc.LeftRight("Bill discount", Money(b.Discount));
            doc.LeftRight(b.InvType == 2 ? "REFUND" : "TOTAL", Money(b.NetAmount), bold: true, tall: true);
            foreach (var p in b.Payments)
                doc.LeftRight(PayName(p.PayType) + (string.IsNullOrWhiteSpace(p.RefNo) ? "" : " " + p.RefNo.Trim()), Money(p.Amount));
            doc.LeftRight("Lines / qty", $"{b.Lines.Count} / {Qty(b.TotalQty)}");
            doc.Divider();
            doc.Line($"Copy printed {now:yyyy-MM-dd HH:mm}", SlipAlign.Center);
            return doc;
        }

        private static string Qty(decimal n) => n.ToString("0.###", CultureInfo.InvariantCulture);

        // PayType 1 cash, 2 card, 3 credit, 4 voucher, 5 bank transfer, 6 cheque
        private static string PayName(int payType) => payType switch
        {
            1 => "Cash", 2 => "Card", 3 => "Credit", 4 => "Voucher", 5 => "Bank transfer", 6 => "Cheque", _ => $"Pay {payType}",
        };

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
        public static decimal Num(Dictionary<string, object> row, string key)
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
            // dashes, dots and quotes the pages use, as plain ASCII rather than '?'
            text = text.Replace('–', '-').Replace('—', '-').Replace('−', '-').Replace('·', '-')
                       .Replace('‘', '\'').Replace('’', '\'').Replace('“', '"').Replace('”', '"')
                       .Replace(' ', ' ').Replace("…", "...");
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
