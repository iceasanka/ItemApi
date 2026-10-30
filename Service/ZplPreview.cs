using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Drawing.Text;
using System.Text;
using System.Text.RegularExpressions;
using ItemApi.Models;

namespace ItemApi.Service
{
    // Draws the ZPL that ZplLabelBuilder makes as a PNG, for the Barcode labels page's preview (StockSystem.md §6.20).
    // It reads the ZPL itself, so the preview is what goes to the Zebra: ^FO places, ^A0N + ^FB text, ^BEN / ^BCN
    // barcodes (^BY module), ^GB frames, ^PW / ^LL page, ^PQ copies. Only the commands the builder writes are known.
    // 1 pixel = 1 printer dot. The Zebra's font 0 (CG Triumvirate condensed) is drawn with Arial Narrow, so text widths
    // are close but not exact; bars and places are exact.
    public static class ZplPreview
    {
        private const string Font0 = "Arial Narrow";

        public static int PageCount(string zpl) => Pages(zpl).Sum(p => p.Copies);

        // page 0 = the first, counting ^PQ copies
        public static byte[] Png(string zpl, int page)
        {
            var n = page;
            foreach (var (body, copies) in Pages(zpl))
            {
                if (n < copies) return Draw(body);
                n -= copies;
            }
            throw new LabelException($"Page must be 0 to {PageCount(zpl) - 1}.");
        }

        // ^XA … ^PQn^XZ blocks
        private static List<(string Body, int Copies)> Pages(string zpl) =>
            Regex.Matches(zpl, @"\^XA(.*?)\^XZ", RegexOptions.Singleline)
                 .Select(m => (m.Groups[1].Value, Regex.Match(m.Groups[1].Value, @"\^PQ(\d+)") is { Success: true } q ? int.Parse(q.Groups[1].Value) : 1))
                 .ToList();

        private static byte[] Draw(string body)
        {
            var w = Num(body, "PW", 400);
            var h = Num(body, "LL", 200);
            using var bmp = new Bitmap(Math.Max(1, w), Math.Max(1, h));
            using (var g = Graphics.FromImage(bmp))
            {
                g.Clear(Color.White);
                g.SmoothingMode = SmoothingMode.None;
                g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;

                int x = 0, y = 0, fontH = 20, module = 2;
                (int Width, int Lines, string Align)? block = null;
                (string Kind, int Height)? barcode = null;
                var hex = false;
                // every command starts with ^; field data has no ^ in it (the builder writes ^ as _5E with ^FH)
                foreach (var cmd in body.Split('^', StringSplitOptions.RemoveEmptyEntries))
                {
                    var name = cmd.Length >= 2 ? cmd[..2] : cmd;
                    var args = cmd.Length > 2 ? cmd[2..] : "";
                    var a = args.Split(',');
                    switch (name)
                    {
                        case "FO": x = Int(a, 0); y = Int(a, 1); break;
                        case "A0": fontH = Int(a, 1, fontH); break;   // A0N,h,w
                        case "FB": block = (Int(a, 0), Math.Max(1, Int(a, 1, 1)), a.Length > 3 ? a[3] : "L"); break;
                        case "FH": hex = true; break;
                        case "BY": module = Math.Max(1, Int(a, 0, 2)); break;
                        case "BE": barcode = ("EAN13", Int(a, 1)); break;          // BEN,h,…
                        case "BC": barcode = ("CODE128", Int(a, 1)); break;        // BCN,h,…
                        case "GB":
                            using (var pen = new Pen(Color.Black, Math.Max(1, Int(a, 2, 1))) { Alignment = PenAlignment.Inset })
                                g.DrawRectangle(pen, x, y, Int(a, 0), Int(a, 1));
                            break;
                        case "FD":
                            var data = hex ? Unhex(args) : args;
                            if (barcode is { } b) Bars(g, b.Kind, data, x, y, b.Height, module);
                            else Text(g, data, x, y, fontH, block);
                            break;
                        case "FS": block = null; barcode = null; hex = false; break;
                    }
                }
            }
            using var ms = new MemoryStream();
            bmp.Save(ms, ImageFormat.Png);
            return ms.ToArray();
        }

        private static void Text(Graphics g, string text, int x, int y, int fontH, (int Width, int Lines, string Align)? block)
        {
            if (text.Length == 0) return;
            var width = block?.Width ?? 10000;
            var lines = block?.Lines ?? 1;
            using var font = new Font(Font0, fontH * 0.92f, FontStyle.Bold, GraphicsUnit.Pixel);
            using var format = new StringFormat
            {
                Alignment = block?.Align switch { "C" => StringAlignment.Center, "R" => StringAlignment.Far, _ => StringAlignment.Near },
                Trimming = StringTrimming.None
            };
            if (lines == 1) format.FormatFlags |= StringFormatFlags.NoWrap;
            g.DrawString(text, font, Brushes.Black, new RectangleF(x, y, width, fontH * lines + 2), format);
        }

        private static void Bars(Graphics g, string kind, string data, int x, int y, int height, int module)
        {
            var bits = kind == "EAN13" ? Ean13(data) : Code128(data);
            for (var i = 0; i < bits.Length; i++)
                if (bits[i] == '1')
                    g.FillRectangle(Brushes.Black, x + i * module, y, module, height);
        }

        // ── EAN-13: 12 digits in, the printer adds the check digit ──
        private static readonly string[] L = { "0001101", "0011001", "0010011", "0111101", "0100011", "0110001", "0101111", "0111011", "0110111", "0001011" };
        private static readonly string[] Parity = { "LLLLLL", "LLGLGG", "LLGGLG", "LLGGGL", "LGLLGG", "LGGLLG", "LGGGLL", "LGLGLG", "LGLGGL", "LGGLGL" };

        private static string Ean13(string data)
        {
            var d = new string(data.Where(char.IsDigit).ToArray());
            if (d.Length < 12) return "";
            d = d[..12];
            var sum = 0;
            for (var i = 0; i < 12; i++) sum += (d[i] - '0') * (i % 2 == 0 ? 1 : 3);
            d += (char)('0' + (10 - sum % 10) % 10);

            var r = new StringBuilder("101");
            var parity = Parity[d[0] - '0'];
            for (var i = 1; i <= 6; i++)
            {
                var code = L[d[i] - '0'];
                r.Append(parity[i - 1] == 'L' ? code : new string(Invert(code).Reverse().ToArray()));
            }
            r.Append("01010");
            for (var i = 7; i <= 12; i++) r.Append(Invert(L[d[i] - '0']));
            r.Append("101");
            return r.ToString();
        }

        private static string Invert(string s) => new(s.Select(c => c == '1' ? '0' : '1').ToArray());

        // ── Code 128, as the printer's automatic mode: digits in pairs (set C), else set B ──
        private static readonly string[] C128 =
        {
            "212222","222122","222221","121223","121322","131222","122213","122312","132212","221213",
            "221312","231212","112232","122132","122231","113222","123122","123221","223211","221132",
            "221231","213212","223112","312131","311222","321122","321221","312212","322112","322211",
            "212123","212321","232121","111323","131123","131321","112313","132113","132311","211313",
            "231113","231311","112133","112331","132131","113123","113321","133121","313121","211331",
            "231131","213113","213311","213131","311123","311321","331121","312113","312311","332111",
            "314111","221411","431111","111224","111422","121124","121421","141122","141221","112214",
            "112412","122114","122411","142112","142211","241211","221114","413111","241112","134111",
            "111242","121142","121241","114212","124112","124211","411212","421112","421211","212141",
            "214121","412121","111143","111341","131141","114113","114311","411113","411311","113141",
            "114131","311141","411131","211412","211214","211232","2331112"
        };

        private static string Code128(string data)
        {
            var values = new List<int>();
            var digits = data.Length >= 2 && data.All(char.IsDigit);
            if (digits)
            {
                values.Add(105);   // start C
                var i = 0;
                for (; i + 1 < data.Length; i += 2) values.Add(int.Parse(data.Substring(i, 2)));
                if (i < data.Length) { values.Add(100); values.Add(data[i] - 32); }   // odd: last digit in set B
            }
            else
            {
                values.Add(104);   // start B
                values.AddRange(data.Select(c => c is >= ' ' and <= '~' ? c - 32 : 0));
            }
            var check = values[0];
            for (var i = 1; i < values.Count; i++) check += i * values[i];
            values.Add(check % 103);
            values.Add(106);   // stop

            var r = new StringBuilder();
            foreach (var v in values)
            {
                var widths = C128[v];
                for (var i = 0; i < widths.Length; i++) r.Append(i % 2 == 0 ? '1' : '0', widths[i] - '0');
            }
            return r.ToString();
        }

        // _5F → _ (^FH)
        private static string Unhex(string s) =>
            Regex.Replace(s, "_([0-9A-Fa-f]{2})", m => ((char)Convert.ToInt32(m.Groups[1].Value, 16)).ToString());

        private static int Num(string body, string cmd, int fallback) =>
            Regex.Match(body, @"\^" + cmd + @"(\d+)") is { Success: true } m ? int.Parse(m.Groups[1].Value) : fallback;

        private static int Int(string[] a, int i, int fallback = 0) =>
            i < a.Length && int.TryParse(a[i], out var v) ? v : fallback;
    }
}
