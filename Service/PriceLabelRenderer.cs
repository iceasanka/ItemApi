using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Drawing.Printing;
using System.Drawing.Text;
using System.Globalization;
using System.Text.Json;
using ItemApi.Models;

namespace ItemApi.Service
{
    // Draws price labels (z_tb_LabelLayout kind 2) and prints them through the Windows printer driver, so Sinhala works
    // on any printer (the 80 mm receipt printer the old BarTender labels used, an A4 laser for sheets …).
    // StockSystem.md §6.21. The same drawing makes the PNG preview, so the page shows exactly what is printed.
    //
    // Wide label (as the old PricePrint.btw):        Narrow / tall label: the same parts one under the other.
    //   item code      | name (Sinhala / English)
    //   (English name) |  ─ plain:     footer text (slogan)
    //   Rs 175.00      |  ─ discount:  Save Rs 25.00 / Now Rs 150.00
    //                  |  ─ discount%: Save 10%   (no price, as the old DiscountPercentagePrint.btw)
    // Every text is made as big as its box allows. All sizes in mm.
    // A designed layout (DesignJson, U034) puts each part in its own box instead, at its own font size.
    public static class PriceLabelRenderer
    {
        public const string DefaultSinhalaFont = "Iskoola Pota";
        public const string DefaultEnglishFont = "Courier New";
        private const float PreviewPixelsPerMm = 8f;   // ≈ 203 dpi, like the printers
        private static readonly JsonSerializerOptions DesignJsonOptions = new(JsonSerializerDefaults.Web);

        // The designed parts of a layout; null = none (the parts are placed by themselves)
        public static List<PriceLabelElement>? Design(LabelLayout l)
        {
            if (string.IsNullOrWhiteSpace(l.DesignJson)) return null;
            List<PriceLabelElement>? list;
            try
            {
                list = JsonSerializer.Deserialize<List<PriceLabelElement>>(l.DesignJson, DesignJsonOptions);
            }
            catch (JsonException)
            {
                throw new LabelException("The label design could not be read - open the layout and save it again.");
            }
            return list is { Count: > 0 } ? list : null;
        }

        // The upright label (the design's size): width × height, turned when the layout is landscape
        public static (float Width, float Height) UprightSize(LabelLayout l) => l.Rotate
            ? ((float)l.LabelHeightMm, (float)l.LabelWidthMm)
            : ((float)l.LabelWidthMm, (float)l.LabelHeightMm);

        public static int PageCount(LabelLayout layout, int slots) =>
            (slots + PerPage(layout) - 1) / PerPage(layout);

        public static (float Width, float Height) PageSize(LabelLayout l) =>
            ((float)(l.MarginLeftMm + l.LabelsAcross * l.LabelWidthMm + (l.LabelsAcross - 1) * l.GapXMm),
             (float)(l.MarginTopMm + l.RowsPerPage * l.LabelHeightMm + (l.RowsPerPage - 1) * l.GapYMm));

        // One page as a PNG (page 0 = the first)
        public static byte[] Preview(LabelLayout layout, IList<PriceLabelData?> slots, int page, bool borders)
        {
            var (w, h) = PageSize(layout);
            using var bmp = new Bitmap(Math.Max(1, (int)Math.Ceiling(w * PreviewPixelsPerMm)),
                                       Math.Max(1, (int)Math.Ceiling(h * PreviewPixelsPerMm)));
            bmp.SetResolution(PreviewPixelsPerMm * 25.4f, PreviewPixelsPerMm * 25.4f);
            using (var g = Graphics.FromImage(bmp))
            {
                g.Clear(Color.White);
                g.PageUnit = GraphicsUnit.Millimeter;
                DrawPage(g, layout, slots, page, borders);
            }
            using var ms = new MemoryStream();
            bmp.Save(ms, ImageFormat.Png);
            return ms.ToArray();
        }

        // Prints every page; returns the number of pages. Success = the spooler took the job.
        public static int Print(string printerName, LabelLayout layout, IList<PriceLabelData?> slots, string docName, bool borders)
        {
            var pages = PageCount(layout, slots.Count);
            var (w, h) = PageSize(layout);

            using var doc = new PrintDocument();
            doc.PrinterSettings.PrinterName = printerName;
            if (!doc.PrinterSettings.IsValid)
                throw new LabelException($"Printer '{printerName}' not found on the API server.");
            doc.DocumentName = docName;
            doc.PrintController = new StandardPrintController();   // no "Printing…" window on the server
            doc.OriginAtMargins = false;
            doc.DefaultPageSettings.Landscape = false;
            doc.DefaultPageSettings.Margins = new Margins(0, 0, 0, 0);
            doc.DefaultPageSettings.PaperSize = new PaperSize("Label", Hundredths(w), Hundredths(h));

            var page = 0;
            doc.PrintPage += (_, e) =>
            {
                var g = e.Graphics!;
                g.PageUnit = GraphicsUnit.Millimeter;
                // the driver puts 0,0 at the printable area — move back to the paper's corner
                g.TranslateTransform(-e.PageSettings.HardMarginX * 0.254f, -e.PageSettings.HardMarginY * 0.254f);
                DrawPage(g, layout, slots, page, borders);
                page++;
                e.HasMorePages = page < pages;
            };
            doc.Print();
            return pages;
        }

        // The font must be on the server, or Windows quietly uses another one (Sinhala would print as boxes)
        public static bool FontExists(string name)
        {
            using var fonts = new InstalledFontCollection();
            return fonts.Families.Any(f => string.Equals(f.Name, name, StringComparison.OrdinalIgnoreCase));
        }

        // every font family on the server, by name
        public static List<string> Fonts()
        {
            using var fonts = new InstalledFontCollection();
            return fonts.Families.Select(f => f.Name).OrderBy(n => n, StringComparer.OrdinalIgnoreCase).ToList();
        }

        private static int PerPage(LabelLayout l) => l.LabelsAcross * l.RowsPerPage;

        private static int Hundredths(float mm) => (int)Math.Round(mm / 25.4f * 100f);

        private static void DrawPage(Graphics g, LabelLayout layout, IList<PriceLabelData?> slots, int page, bool borders)
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
            var design = Design(layout);
            var perPage = PerPage(layout);
            for (var i = 0; i < perPage; i++)
            {
                var n = page * perPage + i;
                if (n >= slots.Count) break;
                var col = i % layout.LabelsAcross;
                var row = i / layout.LabelsAcross;
                var cell = new RectangleF(
                    (float)(layout.MarginLeftMm + col * (layout.LabelWidthMm + layout.GapXMm)),
                    (float)(layout.MarginTopMm + row * (layout.LabelHeightMm + layout.GapYMm)),
                    (float)layout.LabelWidthMm, (float)layout.LabelHeightMm);
                if (borders)
                    using (var pen = new Pen(Color.Black, 0.3f))
                        g.DrawRectangle(pen, cell.X, cell.Y, cell.Width, cell.Height);
                if (slots[n] is { } label)
                    DrawLabel(g, layout, design, label, cell);
            }
        }

        private static void DrawLabel(Graphics g, LabelLayout layout, List<PriceLabelElement>? design, PriceLabelData label,
                                      RectangleF cell)
        {
            var state = g.Save();
            try
            {
                // turned label: draw it upright in a W×H box, then turn the box into the cell
                float w = cell.Width, h = cell.Height;
                g.TranslateTransform(cell.X, cell.Y);
                if (layout.Rotate)
                {
                    g.TranslateTransform(cell.Width, 0);
                    g.RotateTransform(90);
                    (w, h) = (h, w);
                }
                g.SetClip(new RectangleF(0, 0, w, h));

                var parts = new Parts(layout, label);
                if (design != null)
                {
                    DrawDesign(g, parts, design);
                    return;
                }
                var pad = Math.Min(1.5f, Math.Min(w, h) * 0.05f);
                var box = new RectangleF(pad, pad, w - 2 * pad, h - 2 * pad);
                if (box.Width >= box.Height * 1.8f)
                    DrawWide(g, parts, box);
                else
                    DrawTall(g, parts, box);
            }
            finally
            {
                g.Restore(state);
            }
        }

        private static void DrawWide(Graphics g, Parts p, RectangleF box)
        {
            var leftWidth = box.Width * 0.45f;
            var left = new RectangleF(box.X, box.Y, leftWidth - 1f, box.Height);
            var right = new RectangleF(box.X + leftWidth, box.Y, box.Width - leftWidth, box.Height);

            // left keeps its places (code top, price bottom) like the old label, even when a part is left out
            Stack(g, left, new List<(float, Action<RectangleF>?)>
            {
                (0.24f, p.Code.Length > 0 ? r => p.English(g, p.Code, r, 1, StringAlignment.Near, true) : null),
                (0.36f, p.SecondName.Length > 0 ? r => p.English(g, p.SecondName, r, 2, StringAlignment.Near, true) : null),
                (0.40f, p.PriceText.Length > 0 ? r => p.English(g, p.PriceText, r, 1, StringAlignment.Near, true) : null)
            }, keepEmpty: true);
            Stack(g, right, RightParts(g, p));
        }

        private static List<(float, Action<RectangleF>?)> RightParts(Graphics g, Parts p)
        {
            var list = new List<(float, Action<RectangleF>?)>
            {
                (0.50f, p.MainName.Length > 0 ? r => p.Name(g, p.MainName, p.MainIsSinhala, r, 2) : null)
            };
            if (p.Label.DiscountAmount is > 0)
            {
                list.Add((0.20f, r => p.English(g, "Save " + Money(p.Label.DiscountAmount.Value), r, 1, StringAlignment.Near, false)));
                list.Add((0.30f, r => p.English(g, "Now " + Money(p.Label.Price - p.Label.DiscountAmount.Value), r, 1, StringAlignment.Near, true)));
            }
            else if (p.Label.DiscountPercent is > 0)
            {
                list.Add((0.50f, r => p.English(g, $"Save {Num(p.Label.DiscountPercent.Value)}%", r, 1, StringAlignment.Near, true)));
            }
            else if (p.Footer.Length > 0)
            {
                list.Add((0.25f, r => p.Name(g, p.Footer, IsSinhala(p.Footer), r, 1)));
            }
            return list;
        }

        private static void DrawTall(Graphics g, Parts p, RectangleF box)
        {
            var list = new List<(float, Action<RectangleF>?)>
            {
                (0.10f, p.Code.Length > 0 ? r => p.English(g, p.Code, r, 1, StringAlignment.Near, true) : null),
                (0.28f, p.MainName.Length > 0 ? r => p.Name(g, p.MainName, p.MainIsSinhala, r, 2) : null),
                (0.16f, p.SecondName.Length > 0 ? r => p.English(g, p.SecondName, r, 2, StringAlignment.Center, true) : null),
                (0.22f, p.PriceText.Length > 0 ? r => p.English(g, p.PriceText, r, 1, StringAlignment.Center, true) : null)
            };
            if (p.Label.DiscountAmount is > 0)
            {
                list.Add((0.10f, r => p.English(g, "Save " + Money(p.Label.DiscountAmount.Value), r, 1, StringAlignment.Center, false)));
                list.Add((0.20f, r => p.English(g, "Now " + Money(p.Label.Price - p.Label.DiscountAmount.Value), r, 1, StringAlignment.Center, true)));
            }
            else if (p.Label.DiscountPercent is > 0)
            {
                list.Add((0.22f, r => p.English(g, $"Save {Num(p.Label.DiscountPercent.Value)}%", r, 1, StringAlignment.Center, true)));
            }
            else if (p.Footer.Length > 0)
            {
                list.Add((0.10f, r => p.Name(g, p.Footer, IsSinhala(p.Footer), r, 1)));
            }
            Stack(g, box, list);
        }

        // Each part in its own box. A part with nothing to show on this label (no discount, no code …) is left out.
        private static void DrawDesign(Graphics g, Parts p, List<PriceLabelElement> design)
        {
            foreach (var e in design)
            {
                var text = p.Text(e.K);
                if (text.Length == 0) continue;
                var r = new RectangleF(e.X, e.Y, e.W, e.H);
                var align = e.Align switch { "C" => StringAlignment.Center, "R" => StringAlignment.Far, _ => StringAlignment.Near };
                float? start = e.Size > 0 ? e.Size * 25.4f / 72f : null;   // pt → mm
                // names and the footer may wrap: as many lines as the size allows, 2 when it fits the box
                var lines = e.K is "name" or "name2" or "footer"
                    ? start is { } s ? Math.Max(1, (int)(r.Height / (s * 1.15f))) : 2
                    : 1;
                var sinhala = e.K == "name" ? p.MainIsSinhala : e.K == "footer" && IsSinhala(text);
                var style = (e.Bold ? FontStyle.Bold : FontStyle.Regular) | (e.Italic ? FontStyle.Italic : FontStyle.Regular);
                var family = sinhala ? p.SinhalaFont : string.IsNullOrWhiteSpace(e.Font) ? p.EnglishFont : e.Font;
                DrawFit(g, text, family, style, r, lines, align, start);
            }
        }

        // Splits the box top to bottom by the weights of the parts that are there (null = left out; keepEmpty = its
        // space stays empty instead of going to the others)
        private static void Stack(Graphics g, RectangleF box, List<(float Weight, Action<RectangleF>? Draw)> parts,
                                  bool keepEmpty = false)
        {
            var used = parts.Where(p => keepEmpty || p.Draw != null).ToList();
            var total = used.Sum(p => p.Weight);
            if (total <= 0) return;
            var y = box.Y;
            foreach (var (weight, draw) in used)
            {
                var height = box.Height * weight / total;
                draw?.Invoke(new RectangleF(box.X, y, box.Width, height));
                y += height;
            }
        }

        // The biggest font (mm) that fits the box in at most maxLines lines, from startSize when given; at the smallest
        // size the text is cut
        private static void DrawFit(Graphics g, string text, string family, FontStyle style, RectangleF r, int maxLines,
                                    StringAlignment align, float? startSize = null)
        {
            if (text.Length == 0 || r.Width <= 0 || r.Height <= 0) return;
            style = StyleOf(family, style);
            using var format = new StringFormat
            {
                Alignment = align,
                LineAlignment = StringAlignment.Center,
                Trimming = StringTrimming.EllipsisWord
            };
            if (maxLines == 1)
                format.FormatFlags |= StringFormatFlags.NoWrap;

            var size = startSize ?? r.Height / maxLines * 0.8f;
            Font? font = null;
            try
            {
                while (true)
                {
                    font?.Dispose();
                    font = new Font(family, size, style, GraphicsUnit.Millimeter);
                    var lineHeight = font.GetHeight(g);
                    var measured = g.MeasureString(text, font, new SizeF(maxLines == 1 ? 10000f : r.Width, 10000f), format);
                    var lines = (int)Math.Round(measured.Height / lineHeight);
                    if ((measured.Width <= r.Width && measured.Height <= r.Height && lines <= maxLines) || size <= 1.2f)
                        break;
                    size *= 0.92f;
                }
                g.DrawString(text, font, Brushes.Black, r, format);
            }
            finally
            {
                font?.Dispose();
            }
        }

        // a font without that style (no italic, bold only …) would throw: the nearest one it has
        private static FontStyle StyleOf(string family, FontStyle style)
        {
            try
            {
                using var f = new FontFamily(family);
                if (f.IsStyleAvailable(style)) return style;
                foreach (var s in new[] { style & ~FontStyle.Italic, style & ~FontStyle.Bold, FontStyle.Regular, FontStyle.Bold })
                    if (f.IsStyleAvailable(s)) return s;
            }
            catch (ArgumentException)
            {
                // not installed: Font() falls back to a default family, which has every style
            }
            return style;
        }

        private static string Money(decimal v) => "Rs " + v.ToString("#,0.00", CultureInfo.InvariantCulture);
        private static string Num(decimal v) => v.ToString("0.##", CultureInfo.InvariantCulture);
        private static bool IsSinhala(string s) => s.Any(c => c >= '඀' && c <= '෿');

        // What goes where on one label, from the layout and the language
        private sealed class Parts
        {
            public readonly PriceLabelData Label;
            public readonly string Code, MainName, SecondName, PriceText, Footer;
            public readonly bool MainIsSinhala;
            public readonly string SinhalaFont, EnglishFont;

            public Parts(LabelLayout l, PriceLabelData label)
            {
                Label = label;
                SinhalaFont = string.IsNullOrWhiteSpace(l.SinhalaFont) ? DefaultSinhalaFont : l.SinhalaFont;
                EnglishFont = string.IsNullOrWhiteSpace(l.EnglishFont) ? DefaultEnglishFont : l.EnglishFont;
                Code = l.ShowItemCode ? label.ItemCode : "";
                // percent label: no price (as the old one); price hidden by the layout: none either
                PriceText = l.ShowPrice && label.DiscountPercent is not > 0 ? Money(label.Price) : "";
                Footer = (l.FooterText ?? "").Trim();

                var english = l.ShowName ? label.Name : "";
                var sinhala = l.ShowName ? label.SinhalaName : "";
                // the big name: Sinhala for Sinhala / both (English when the item has no Sinhala name). Some items have
                // English typed in the Sinhala name — the font follows the text, and the same name is not printed twice.
                if (l.Language != 1 && sinhala.Length > 0)
                {
                    MainName = sinhala;
                    MainIsSinhala = IsSinhala(sinhala);
                    SecondName = l.Language == 3 && !string.Equals(english, sinhala, StringComparison.OrdinalIgnoreCase) ? english : "";
                }
                else
                {
                    MainName = english;
                    SecondName = "";
                }
            }

            // the text of a designed part (PriceLabelElement.K); "" = nothing on this label
            public string Text(string k)
            {
                var disc = Label.DiscountAmount is > 0 ? Label.DiscountAmount.Value : 0;
                var pct = disc == 0 && Label.DiscountPercent is > 0 ? Label.DiscountPercent.Value : 0;
                return k switch
                {
                    "code" => Code,
                    "name" => MainName,
                    "name2" => SecondName,
                    "price" => PriceText,
                    "save" => disc > 0 ? "Save " + Money(disc) : pct > 0 ? $"Save {Num(pct)}%" : "",
                    "now" => disc > 0 ? "Now " + Money(Label.Price - disc) : "",
                    "footer" => disc == 0 && pct == 0 ? Footer : "",
                    _ => ""
                };
            }

            public void English(Graphics g, string text, RectangleF r, int lines, StringAlignment align, bool bold) =>
                DrawFit(g, text, EnglishFont, bold ? FontStyle.Bold : FontStyle.Regular, r, lines, align);

            public void Name(Graphics g, string text, bool sinhala, RectangleF r, int lines) =>
                DrawFit(g, text, sinhala ? SinhalaFont : EnglishFont, FontStyle.Bold, r, lines, StringAlignment.Center);
        }
    }
}
