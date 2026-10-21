using System.Globalization;
using System.Text;
using ItemApi.Models;

namespace ItemApi.Service
{
    // Builds the ZPL for barcode labels from a z_tb_LabelLayout (StockSystem.md §6.20). One ZPL page (^XA … ^XZ) =
    // RowsPerPage rows of LabelsAcross labels; labels fill left to right, top to bottom. Pages that come out the same
    // are sent once with ^PQ (100 labels of one item on a 1-across roll = one page × 100).
    //
    // One label, top to bottom: name (1 or 2 lines) · barcode · barcode number · item code + price · MFD / EXP.
    // Font sizes follow the label height, so the same layout code works for 25 mm and 40 mm stickers.
    // Text is UTF-8 (^CI28) but the printer's font has no Sinhala — the English name is printed.
    public static class ZplLabelBuilder
    {
        public static (string Zpl, int Pages) Build(LabelLayout layout, IList<LabelData?> slots, bool borders = false)
        {
            var g = new Geometry(layout);
            var perPage = layout.LabelsAcross * layout.RowsPerPage;

            var zpl = new StringBuilder();
            var pages = 0;
            string? previous = null;
            var repeat = 0;

            for (var start = 0; start < slots.Count; start += perPage)
            {
                var body = new StringBuilder();
                for (var i = 0; i < perPage && start + i < slots.Count; i++)
                {
                    var col = i % layout.LabelsAcross;
                    var row = i / layout.LabelsAcross;
                    var x = g.MarginLeft + col * (g.LabelWidth + g.GapX);
                    var y = g.MarginTop + row * (g.LabelHeight + g.GapY);
                    if (borders)
                        body.Append($"^FO{x},{y}^GB{g.LabelWidth},{g.LabelHeight},2^FS");
                    if (slots[start + i] is { } label)
                        AppendLabel(body, layout, g, label, x, y);
                }

                var page = body.ToString();
                if (page == previous)
                {
                    repeat++;
                }
                else
                {
                    if (previous != null)
                        AppendPage(zpl, layout, g, previous, repeat);
                    previous = page;
                    repeat = 1;
                }
                pages++;
            }
            if (previous != null)
                AppendPage(zpl, layout, g, previous, repeat);

            return (zpl.ToString(), pages);
        }

        // Checks that every label fits before anything is sent; the message says what to change.
        public static void CheckFits(LabelLayout layout, IEnumerable<LabelData> labels)
        {
            var g = new Geometry(layout);
            foreach (var label in labels)
            {
                var (_, modules, _) = PickBarcode(layout, label.Barcode);
                if (modules > g.InnerWidth)
                    throw new LabelException(
                        $"Barcode {label.Barcode} is too long for a {Mm(layout.LabelWidthMm)} mm wide label.");
            }
            if (g.BarcodeHeight(layout) < Dots(3, layout.Dpi))
                throw new LabelException(
                    $"No room for the barcode on a {Mm(layout.LabelHeightMm)} mm high label - turn off the name, " +
                    "item code / price or dates line, or set a smaller barcode height.");
        }

        private static void AppendPage(StringBuilder zpl, LabelLayout layout, Geometry g, string body, int copies)
        {
            if (layout.Darkness is { } d)
                zpl.Append($"~SD{Math.Clamp(d, 0, 30):00}");
            zpl.Append("^XA^CI28^LH0,0");
            zpl.Append($"^PW{g.PageWidth}^LL{g.PageHeight}");
            zpl.Append(body);
            zpl.Append($"^PQ{copies}^XZ\n");
        }

        private static void AppendLabel(StringBuilder z, LabelLayout layout, Geometry g, LabelData label, int x0, int y0)
        {
            var x = x0 + g.PadX;
            var y = y0 + g.PadY;

            if (layout.ShowName)
            {
                // a long name gets the smaller font; ^FB writes text that still does not fit over its last line,
                // so what is left over is cut
                var font = label.Name.Length > g.NameLines * Fit(g.InnerWidth, g.Font) ? g.Small : g.Font;
                var room = g.NameLines * Fit(g.InnerWidth, font);
                var name = label.Name.Length > room ? label.Name[..room].TrimEnd() : label.Name;
                z.Append($"^FO{x},{y + g.Font - font}^A0N,{font},{font}^FB{g.InnerWidth},{g.NameLines},0,C^FH^FD{Esc(name)}^FS");
                y += g.NameLines * g.Font + g.Space;
            }

            var barH = g.BarcodeHeight(layout);
            var (kind, modules, data) = PickBarcode(layout, label.Barcode);
            var module = Math.Clamp(g.InnerWidth / Math.Max(1, modules), 1, Math.Max(1, layout.Dpi / 100));
            var barX = x + Math.Max(0, (g.InnerWidth - modules * module) / 2);
            z.Append($"^BY{module}");
            z.Append(kind == "EAN13"
                ? $"^FO{barX},{y}^BEN,{barH},N,N^FD{data}^FS"
                : $"^FO{barX},{y}^BCN,{barH},N,N,N,A^FD{data}^FS");
            y += barH + g.Space / 2;
            z.Append($"^FO{x},{y}^A0N,{g.Small},{g.Small}^FB{g.InnerWidth},1,0,C^FH^FD{Esc(label.Barcode)}^FS");
            y += g.Small + g.Space;

            if (layout.ShowItemCode || layout.ShowPrice)
            {
                // item code left, price right; on a narrow label the price gets smaller so the two never overlap
                var code = layout.ShowItemCode ? label.ItemCode : "";
                var codeWidth = code.Length == 0 ? 0 : code.Length * CharWidth(g.Small) + g.Space;
                if (code.Length > 0)
                    z.Append($"^FO{x},{y + g.Big - g.Small}^A0N,{g.Small},{g.Small}^FB{g.InnerWidth},1,0,L^FH^FD{Esc(code)}^FS");
                if (layout.ShowPrice && label.Price is { } price)
                {
                    var text = "Rs " + price.ToString("#,0.00", CultureInfo.InvariantCulture);
                    var size = Math.Min(g.Big, (g.InnerWidth - codeWidth) * 100 / (text.Length * CharPercent));
                    size = Math.Max(size, g.Small * 3 / 4);
                    z.Append($"^FO{x},{y + g.Big - size}^A0N,{size},{size}^FB{g.InnerWidth},1,0,{(code.Length > 0 ? "R" : "C")}^FD{text}^FS");
                }
                y += g.Big + g.Space;
            }

            if (layout.ShowDates && (label.MfdDate != null || label.ExpDate != null))
            {
                var dates = string.Join("  ", new[]
                {
                    label.MfdDate is { } m ? "MFD " + m.ToString("dd-MM-yy") : null,
                    label.ExpDate is { } e ? "EXP " + e.ToString("dd-MM-yy") : null
                }.Where(s => s != null));
                z.Append($"^FO{x},{y}^A0N,{g.Small},{g.Small}^FB{g.InnerWidth},1,0,C^FD{dates}^FS");
            }
        }

        // AUTO: EAN13 for a 13 digit barcode with a right check digit, otherwise Code 128. EAN13 on a barcode that is
        // not a valid EAN13 also prints Code 128 (so the label still scans). Modules = the barcode's width in bars.
        private static (string Kind, int Modules, string Data) PickBarcode(LabelLayout layout, string barcode)
        {
            var type = (layout.BarcodeType ?? "AUTO").ToUpperInvariant();
            if (type != "CODE128" && IsEan13(barcode))
                return ("EAN13", 95 + 18, barcode[..12]);   // + quiet zones
            var digits = barcode.All(char.IsDigit);
            var symbols = digits ? (barcode.Length + 1) / 2 + 1 : barcode.Length;
            return ("CODE128", 11 * symbols + 35 + 20, barcode);   // start, check, stop + quiet zones
        }

        private static bool IsEan13(string s)
        {
            if (s.Length != 13 || !s.All(char.IsDigit))
                return false;
            var sum = 0;
            for (var i = 0; i < 12; i++)
                sum += (s[i] - '0') * (i % 2 == 0 ? 1 : 3);
            return (10 - sum % 10) % 10 == s[12] - '0';
        }

        // ^FH: _ ^ ~ as hex, so a name can never end the field or start a command
        private static string Esc(string s) =>
            s.Replace("_", "_5F").Replace("^", "_5E").Replace("~", "_7E");

        // Font 0 with width = height: a character is at most about 60 % of the height wide (capitals, digits)
        private const int CharPercent = 60;
        private static int CharWidth(int fontHeight) => fontHeight * CharPercent / 100;
        private static int Fit(int width, int fontHeight) => Math.Max(1, width / Math.Max(1, CharWidth(fontHeight)));

        private static int Dots(decimal mm, int dpi) => (int)Math.Round(mm * dpi / 25.4m);

        private static string Mm(decimal mm) => mm.ToString("0.##", CultureInfo.InvariantCulture);

        // Everything in printer dots
        private sealed class Geometry
        {
            public readonly int LabelWidth, LabelHeight, GapX, GapY, MarginLeft, MarginTop, PageWidth, PageHeight;
            public readonly int PadX, PadY, InnerWidth, InnerHeight, Font, Small, Big, Space, NameLines;

            public Geometry(LabelLayout l)
            {
                LabelWidth = Dots(l.LabelWidthMm, l.Dpi);
                LabelHeight = Dots(l.LabelHeightMm, l.Dpi);
                GapX = Dots(l.GapXMm, l.Dpi);
                GapY = Dots(l.GapYMm, l.Dpi);
                MarginLeft = Dots(l.MarginLeftMm, l.Dpi);
                MarginTop = Dots(l.MarginTopMm, l.Dpi);
                PageWidth = MarginLeft + l.LabelsAcross * LabelWidth + (l.LabelsAcross - 1) * GapX;
                PageHeight = MarginTop + l.RowsPerPage * LabelHeight + (l.RowsPerPage - 1) * GapY;

                PadX = Dots(1.2m, l.Dpi);
                PadY = Dots(1m, l.Dpi);
                InnerWidth = LabelWidth - 2 * PadX;
                InnerHeight = LabelHeight - 2 * PadY;

                // 25 mm high at 203 dpi → name 22 dots (~2.7 mm), price 30 dots
                var unit = Dots(1m, l.Dpi);
                Font = Math.Clamp(LabelHeight * 11 / 100, 2 * unit, 5 * unit);
                Small = Math.Max(Font * 85 / 100, 2 * unit);
                Big = Font * 135 / 100;
                Space = Math.Max(2, unit / 2);
                NameLines = l.LabelHeightMm >= 30 ? 2 : 1;
            }

            // fixed height, or what is left after the text lines
            public int BarcodeHeight(LabelLayout l)
            {
                if (l.BarcodeHeightMm > 0)
                    return Dots(l.BarcodeHeightMm, l.Dpi);
                var used = Small + Space + Space / 2;
                if (l.ShowName) used += NameLines * Font + Space;
                if (l.ShowItemCode || l.ShowPrice) used += Big + Space;
                if (l.ShowDates) used += Small;
                return InnerHeight - used;
            }
        }
    }
}
