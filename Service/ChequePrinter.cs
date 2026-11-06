using System.ComponentModel;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Drawing.Printing;
using System.Drawing.Text;
using System.Globalization;
using System.Runtime.InteropServices;
using ItemApi.Models;

namespace ItemApi.Service
{
    public class ChequePrintException : Exception
    {
        public ChequePrintException(string message) : base(message) { }
    }

    // Prints the cheque on the general printer (Settings > Printers) - no BarTender, no LocalPrintAgent.
    // The preview picture and the print are drawn by the same code (Draw), so the preview shows what prints.
    // Everything is laid out in mm on the cheque as you read it; for the print the cheque is turned onto the page
    // (Rotation) and moved back by the printer's unprintable margin, so positions are from the paper's edge.
    public static class ChequePrinter
    {
        private const float CapHeight = 0.716f;   // height of a capital letter / digit as part of the font size (Arial)
        private const float PreviewPxPerMm = 8f;

        internal record Item(string Text, float X, float Y, float FontPt, bool Centre, string Part);

        public class Laid
        {
            internal List<Item> Items { get; } = new();
            public List<string> Problems { get; } = new();
            internal HashSet<string> Over { get; } = new();   // parts that do not fit (red in the preview)
            internal bool AcPayee { get; init; }                // draw the "A/C Payee Only" crossing
        }

        // ---- lay out + check ---------------------------------------------------------------------------------------

        public static Laid Lay(ChequeLayout l, ChequePrintData d)
        {
            var laid = new Laid { AcPayee = d.AcPayee };
            using var bmp = new Bitmap(1, 1);
            using var g = Graphics.FromImage(bmp);
            g.PageUnit = GraphicsUnit.Pixel;
            g.ScaleTransform(20, 20);   // measure at 20 px per mm, as fine as a printer (fonts are in mm)
            g.TextRenderingHint = TextRenderingHint.AntiAlias;

            try { using var _ = new FontFamily(l.FontName); }
            catch (ArgumentException) { laid.Problems.Add($"The font '{l.FontName}' is not installed on the server."); }

            var payee = Clean(d.Payee);
            if (payee.Length == 0) laid.Problems.Add("Enter the payee name.");
            else Put(laid, g, l, l.Payee, payee, "Payee", "The payee name is too long for the cheque");

            var amountText = d.Amount > 0 ? l.AmountPrefix + d.Amount.ToString(l.AmountFormat, CultureInfo.InvariantCulture) + l.AmountSuffix : "";
            if (d.Amount <= 0) laid.Problems.Add("Enter the amount.");
            else if (d.Amount > 999_999_999.99m) laid.Problems.Add("The amount is too big.");
            else Put(laid, g, l, l.Amount, amountText, "Amount", "The amount does not fit in the amount box");

            var words = Clean(d.AmountInWords);
            if (words.Length == 0) laid.Problems.Add("Enter the amount in words.");
            else
            {
                var (one, two, rest) = Wrap(words, s => Width(g, l, l.Words.FontPt, s), (float)l.Words.MaxWidthMm,
                                            s => Width(g, l, l.Words2.FontPt, s), (float)l.Words2.MaxWidthMm);
                laid.Items.Add(new Item(one, (float)l.Words.X, (float)l.Words.Y, (float)l.Words.FontPt, false, "Words"));
                if (two.Length > 0)
                    laid.Items.Add(new Item(two, (float)l.Words2.X, (float)l.Words2.Y, (float)l.Words2.FontPt, false, "Words2"));
                if (rest.Length > 0)
                {
                    laid.Over.Add(two.Length > 0 ? "Words2" : "Words");
                    laid.Problems.Add($"The amount in words does not fit on the two lines (left over: \"{rest}\") - shorten it.");
                }
            }

            var date = d.ChequeDate.ToString("ddMMyy", CultureInfo.InvariantCulture);
            if (d.ChequeDate.Year < 2000 || d.ChequeDate.Year > 2099) laid.Problems.Add("Check the cheque date.");
            for (var i = 0; i < 6; i++)
                laid.Items.Add(new Item(date[i].ToString(), (float)l.DateDigitX[i], (float)l.DateY, (float)l.DateFontPt, true, "Date"));
            return laid;
        }

        private static void Put(Laid laid, Graphics g, ChequeLayout l, ChequeTextField f, string text, string part, string tooLong)
        {
            laid.Items.Add(new Item(text, (float)f.X, (float)f.Y, (float)f.FontPt, false, part));
            var w = Width(g, l, f.FontPt, text);
            if (w > (float)f.MaxWidthMm)
            {
                laid.Over.Add(part);
                laid.Problems.Add($"{tooLong} ({w:0} mm, room {f.MaxWidthMm:0} mm) - shorten it.");
            }
        }

        // the most words on line 1, the rest on line 2; rest = what fits nowhere
        private static (string One, string Two, string Left) Wrap(string text, Func<string, float> w1, float max1, Func<string, float> w2, float max2)
        {
            var words = text.Split(' ', StringSplitOptions.RemoveEmptyEntries);
            var i = 0;
            string Take(Func<string, float> w, float max)
            {
                var line = "";
                while (i < words.Length)
                {
                    var next = line.Length == 0 ? words[i] : line + " " + words[i];
                    if (w(next) > max && line.Length > 0) break;
                    line = next;
                    i++;
                    if (w(line) > max) break;   // one word longer than the line
                }
                return line;
            }
            var one = Take(w1, max1);
            var two = Take(w2, max2);
            var rest = string.Join(' ', words.Skip(i));
            if (rest.Length == 0 && w2(two) > max2) rest = two;   // a single word too long for line 2
            return (one, two, rest);
        }

        // ---- draw (cheque mm; the caller sets the transform) -------------------------------------------------------

        private static Font MakeFont(ChequeLayout l, decimal pt) =>
            new(l.FontName, (float)pt * 25.4f / 72f, l.Bold ? FontStyle.Bold : FontStyle.Regular, GraphicsUnit.World);

        private static float Width(Graphics g, ChequeLayout l, decimal pt, string text)
        {
            using var f = MakeFont(l, pt);
            return g.MeasureString(text, f, PointF.Empty, StringFormat.GenericTypographic).Width;
        }

        private static void Draw(Graphics g, ChequeLayout l, Laid laid, Brush ink)
        {
            g.TranslateTransform((float)l.OffsetXMm, (float)l.OffsetYMm);
            foreach (var it in laid.Items)
            {
                using var f = MakeFont(l, (decimal)it.FontPt);
                var em = f.Size;
                var fam = f.FontFamily;
                var ascent = em * fam.GetCellAscent(f.Style) / fam.GetEmHeight(f.Style);
                var top = it.Y + CapHeight * em - ascent;          // so the top of the capitals lands on Y
                var x = it.X;
                if (it.Centre)
                    x -= g.MeasureString(it.Text, f, PointF.Empty, StringFormat.GenericTypographic).Width / 2;
                g.DrawString(it.Text, f, laid.Over.Contains(it.Part) ? Brushes.Red : ink, x, top, StringFormat.GenericTypographic);
            }
            if (laid.AcPayee) DrawAcPayee(g, l, ink);
            g.TranslateTransform(-(float)l.OffsetXMm, -(float)l.OffsetYMm);
        }

        // "A/C Payee Only" between two parallel lines, slanting up to the right, centred on AcPayeeX / AcPayeeY
        private const string AcPayeeText = "A/C Payee Only";
        private static void DrawAcPayee(Graphics g, ChequeLayout l, Brush ink)
        {
            using var f = new Font(l.FontName, (float)l.AcPayeeFontPt * 25.4f / 72f, FontStyle.Bold, GraphicsUnit.World);
            var size = g.MeasureString(AcPayeeText, f, PointF.Empty, StringFormat.GenericTypographic);
            var half = size.Width / 2 + 1.5f;   // the lines a little longer than the words
            var gap = size.Height / 2 + 1.0f;   // from the middle of the words to each line
            var state = g.Save();
            g.TranslateTransform((float)l.AcPayeeX, (float)l.AcPayeeY);
            g.RotateTransform(-30);
            using var pen = new Pen(ink, 0.35f);
            g.DrawLine(pen, -half, -gap, half, -gap);
            g.DrawLine(pen, -half, gap, half, gap);
            g.DrawString(AcPayeeText, f, ink, -size.Width / 2, -size.Height / 2, StringFormat.GenericTypographic);
            g.Restore(state);
        }

        // the cheque's printed parts as faint outlines: lines, amount box, date boxes (preview and test print)
        private static void DrawGuides(Graphics g, ChequeLayout l, bool forPrint)
        {
            using var pen = new Pen(forPrint ? Color.Black : Color.FromArgb(150, 160, 175), forPrint ? 0.2f : 0.25f);
            using var dash = new Pen(forPrint ? Color.Black : Color.FromArgb(170, 180, 195), 0.2f) { DashStyle = DashStyle.Dash };
            using var small = new Font("Arial", 2.4f, FontStyle.Regular, GraphicsUnit.World);
            var label = forPrint ? Brushes.Black : new SolidBrush(Color.FromArgb(120, 130, 145));

            g.DrawRectangle(pen, 0, 0, (float)l.ChequeWidthMm, (float)l.ChequeHeightMm);

            void Line(ChequeTextField f, string name)
            {
                var em = (float)f.FontPt * 25.4f / 72f;
                var baseY = (float)f.Y + CapHeight * em + 0.8f;
                g.DrawLine(dash, (float)f.X, baseY, (float)(f.X + f.MaxWidthMm), baseY);
                g.DrawString(name, small, label, (float)f.X, baseY + 0.3f);
            }
            Line(l.Payee, "payee");
            Line(l.Words, "amount in words");
            Line(l.Words2, "amount in words (line 2)");

            var a = l.Amount;
            var aEm = (float)a.FontPt * 25.4f / 72f;
            g.DrawRectangle(pen, (float)a.X - 2, (float)a.Y - 2, (float)a.MaxWidthMm + 2, CapHeight * aEm + 4);
            g.DrawString("amount", small, label, (float)a.X - 2, (float)a.Y + CapHeight * aEm + 2.4f);

            var dEm = (float)l.DateFontPt * 25.4f / 72f;
            const float box = 5.2f;
            string[] names = { "D", "D", "M", "M", "Y", "Y" };
            for (var i = 0; i < 6; i++)
            {
                var cx = (float)l.DateDigitX[i];
                g.DrawRectangle(pen, cx - box / 2, (float)l.DateY - 1.5f, box, CapHeight * dEm + 3);
                g.DrawString(names[i], small, label, cx - 0.8f, (float)l.DateY + CapHeight * dEm + 1.8f);
            }
        }

        // ---- preview -----------------------------------------------------------------------------------------------

        public static byte[] PreviewPng(ChequeLayout l, Laid laid)
        {
            var w = (int)Math.Ceiling((float)l.ChequeWidthMm * PreviewPxPerMm);
            var h = (int)Math.Ceiling((float)l.ChequeHeightMm * PreviewPxPerMm);
            using var bmp = new Bitmap(w + 1, h + 1);
            using (var g = Graphics.FromImage(bmp))
            {
                g.Clear(Color.FromArgb(250, 248, 240));
                g.SmoothingMode = SmoothingMode.AntiAlias;
                g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
                g.PageUnit = GraphicsUnit.Pixel;
                g.ScaleTransform(PreviewPxPerMm, PreviewPxPerMm);
                DrawGuides(g, l, forPrint: false);
                using var ink = new SolidBrush(Color.FromArgb(20, 30, 90));
                Draw(g, l, laid, ink);
            }
            using var ms = new MemoryStream();
            bmp.Save(ms, ImageFormat.Png);
            return ms.ToArray();
        }

        // ---- print -------------------------------------------------------------------------------------------------

        // Before a cheque is saved: the printer is there and nothing old is waiting (an old job would print on this
        // cheque or the next one). Old jobs are removed, as LocalPrintAgent did; if they cannot be, nothing is printed.
        public static void CheckPrinter(string printer)
        {
            if (string.IsNullOrWhiteSpace(printer))
                throw new ChequePrintException("No general printer (cheques) is chosen - choose it on Settings > Printers.");
            var ps = new PrinterSettings { PrinterName = printer };
            if (!ps.IsValid)
                throw new ChequePrintException($"The cheque printer '{printer}' is not installed on the server.");
            var left = ClearQueue(printer);
            if (left > 0)
                throw new ChequePrintException($"{left} old job(s) are waiting on the cheque printer '{printer}' and could not be removed - clear its queue first (Windows: Printers > {printer} > Open queue). Nothing was saved or printed.");
        }

        // test = the cheque's outlines are printed too: put a plain paper (or a photocopy of a cheque) in the printer
        // the same way as a cheque and lay it over a real cheque to check every part
        public static void Print(string printer, ChequeLayout l, Laid laid, string docName, bool test) =>
            Run(printer, l, laid, docName, test, new StandardPrintController());   // no "Printing..." window on the server

        // the page exactly as the printer driver gets it (paper size, margins, rotation) as a picture - nothing is printed
        public static byte[] PagePng(string printer, ChequeLayout l, Laid laid, bool test)
        {
            var preview = new PreviewPrintController { UseAntiAlias = true };
            Run(printer, l, laid, "Cheque page", test, preview);
            var page = preview.GetPreviewPageInfo()[0];
            using var bmp = new Bitmap(page.PhysicalSize.Width * 2, page.PhysicalSize.Height * 2);
            using (var g = Graphics.FromImage(bmp))
            {
                g.Clear(Color.White);
                g.DrawImage(page.Image, 0, 0, bmp.Width, bmp.Height);
                g.DrawRectangle(Pens.Gray, 0, 0, bmp.Width - 1, bmp.Height - 1);
            }
            using var ms = new MemoryStream();
            bmp.Save(ms, ImageFormat.Png);
            return ms.ToArray();
        }

        private static void Run(string printer, ChequeLayout l, Laid laid, string docName, bool test, PrintController controller)
        {
            using var doc = new PrintDocument();
            doc.PrinterSettings.PrinterName = printer;
            if (!doc.PrinterSettings.IsValid)
                throw new ChequePrintException($"The cheque printer '{printer}' is not installed on the server.");
            doc.PrintController = controller;
            doc.DocumentName = docName;
            doc.OriginAtMargins = false;
            doc.DefaultPageSettings.PaperSize = new PaperSize("Cheque", HundredthsInch(l.PageWidthMm), HundredthsInch(l.PageHeightMm));
            doc.DefaultPageSettings.Landscape = false;
            doc.DefaultPageSettings.Margins = new Margins(0, 0, 0, 0);
            doc.PrinterSettings.Copies = 1;

            Exception? drawError = null;
            doc.PrintPage += (_, e) =>
            {
                try
                {
                    var g = e.Graphics!;
                    g.PageUnit = GraphicsUnit.Millimeter;
                    g.SmoothingMode = SmoothingMode.AntiAlias;
                    // (0,0) is the corner of the printable area: move back so positions are from the paper's edge
                    g.TranslateTransform(-e.PageSettings.HardMarginX * 0.254f, -e.PageSettings.HardMarginY * 0.254f);
                    switch (l.Rotation)
                    {
                        case 90:   // cheque's left edge at the bottom of the page, text reads bottom to top
                            g.TranslateTransform(0, (float)l.PageHeightMm);
                            g.RotateTransform(-90);
                            break;
                        case 270:  // cheque's left edge at the top of the page, text reads top to bottom
                            g.TranslateTransform((float)l.PageWidthMm, 0);
                            g.RotateTransform(90);
                            break;
                    }
                    if (test)
                        DrawGuides(g, l, forPrint: true);
                    Draw(g, l, laid, Brushes.Black);
                }
                catch (Exception ex)
                {
                    drawError = ex;
                }
                e.HasMorePages = false;
            };
            doc.Print();
            if (drawError != null)
                throw new ChequePrintException($"Could not draw the cheque: {drawError.Message}");
        }

        private static int HundredthsInch(decimal mm) => (int)Math.Round(mm / 25.4m * 100m);

        private static string Clean(string? s) => string.Join(' ', (s ?? "").Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries));

        // ---- printer queue (winspool) ------------------------------------------------------------------------------

        // removes the jobs waiting on the printer; returns how many are still there
        private static int ClearQueue(string printer)
        {
            if (!OpenPrinter(printer, out var h, IntPtr.Zero))
                throw new ChequePrintException($"Cannot open the cheque printer '{printer}': {new Win32Exception(Marshal.GetLastWin32Error()).Message}");
            try
            {
                foreach (var id in JobIds(h))
                    SetJob(h, id, 0, IntPtr.Zero, JobControlDelete);   // fails for a job it may not remove - counted below
                for (var i = 0; i < 10; i++)
                {
                    var left = JobIds(h).Count;
                    if (left == 0) return 0;
                    Thread.Sleep(200);   // a removed job leaves the queue a moment later
                }
                return JobIds(h).Count;
            }
            finally
            {
                ClosePrinter(h);
            }
        }

        private static List<int> JobIds(IntPtr h)
        {
            EnumJobs(h, 0, 999, 1, IntPtr.Zero, 0, out var needed, out _);
            if (needed <= 0) return new List<int>();
            var buf = Marshal.AllocHGlobal(needed);
            try
            {
                if (!EnumJobs(h, 0, 999, 1, buf, needed, out _, out var count))
                    throw new ChequePrintException($"Cannot read the cheque printer's queue: {new Win32Exception(Marshal.GetLastWin32Error()).Message}");
                var size = Marshal.SizeOf<JOB_INFO_1>();
                var ids = new List<int>();
                for (var i = 0; i < count; i++)
                    ids.Add(Marshal.PtrToStructure<JOB_INFO_1>(buf + i * size).JobId);
                return ids;
            }
            finally
            {
                Marshal.FreeHGlobal(buf);
            }
        }

        private const int JobControlDelete = 5;

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct JOB_INFO_1
        {
            public int JobId;
            public IntPtr pPrinterName, pMachineName, pUserName, pDocument, pDatatype, pStatus;
            public int Status, Priority, Position, TotalPages, PagesPrinted;
            public short wYear, wMonth, wDayOfWeek, wDay, wHour, wMinute, wSecond, wMilliseconds;
        }

        [DllImport("winspool.drv", EntryPoint = "OpenPrinterW", SetLastError = true, CharSet = CharSet.Unicode)]
        private static extern bool OpenPrinter(string pPrinterName, out IntPtr phPrinter, IntPtr pDefault);

        [DllImport("winspool.drv", SetLastError = true)]
        private static extern bool ClosePrinter(IntPtr hPrinter);

        [DllImport("winspool.drv", EntryPoint = "EnumJobsW", SetLastError = true, CharSet = CharSet.Unicode)]
        private static extern bool EnumJobs(IntPtr hPrinter, int firstJob, int noJobs, int level, IntPtr pJob, int cbBuf, out int pcbNeeded, out int pcReturned);

        [DllImport("winspool.drv", EntryPoint = "SetJobW", SetLastError = true, CharSet = CharSet.Unicode)]
        private static extern bool SetJob(IntPtr hPrinter, int jobId, int level, IntPtr pJob, int command);
    }
}
