using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

namespace ItemApi.Service
{
    // GRN scan: every page (a photo uploaded or a page from the scanner) is made small before it goes to Gemini (U061).
    // Why: 3-4 phone photos / 300 DPI scans are 5-15 MB each; Gemini takes at most 20 MB in one request (base64 adds a
    // third), so a read with 3 pages failed. Gemini does not need more: it scales every image down itself (to about
    // 1-2 thousand pixels a side), so a long side of 2400 px (= an A4 page at about 200 DPI) keeps every printed digit.
    //   - turned upright (phone photo EXIF orientation), long side down to MaxSide (never up), high quality resampling
    //   - colour: "color" kept, "gray" grayscale (default - what OCR uses anyway; the file is about a third smaller),
    //     "bw" black & white (Otsu threshold, 1-bit PNG - the smallest, but faint / shaded print can disappear)
    //   - saved as JPEG quality 88 (PNG for black & white). An image that needs none of this is sent as it came.
    // An image GDI+ cannot open (WEBP, HEIC) is sent as it came.
    public static class GrnScanImage
    {
        public const string Color = "color", Gray = "gray", Bw = "bw";
        private const int JpegQuality = 88;
        // a JPEG / PNG at most this big and already small enough is sent as it came (no second JPEG pass)
        private const int KeepBytes = 1_500_000;

        public sealed record Page(byte[] Data, string MimeType, string Ext, int Width, int Height, bool Changed);

        // maxSide 0 = the size is kept
        public static Page Prepare(byte[] data, string mimeType, string ext, int maxSide, string color)
        {
            var asIs = new Page(data, mimeType, ext, 0, 0, false);
            using var ms = new MemoryStream(data);
            Image src;
            try { src = Image.FromStream(ms, useEmbeddedColorManagement: false, validateImageData: true); }
            catch (Exception) { return asIs; }
            using (src)
            {
                var flip = Orientation(src);
                if (flip != RotateFlipType.RotateNoneFlipNone) src.RotateFlip(flip);
                int w = src.Width, h = src.Height;
                var scale = maxSide > 0 && Math.Max(w, h) > maxSide ? maxSide / (double)Math.Max(w, h) : 1d;
                var simple = mimeType is "image/jpeg" or "image/png";
                if (scale >= 1 && color == Color && flip == RotateFlipType.RotateNoneFlipNone && simple && data.Length <= KeepBytes)
                    return asIs with { Width = w, Height = h };

                int nw = Math.Max(1, (int)Math.Round(w * scale)), nh = Math.Max(1, (int)Math.Round(h * scale));
                using var bmp = new Bitmap(nw, nh, PixelFormat.Format24bppRgb);
                using (var g = Graphics.FromImage(bmp))
                using (var attrs = new ImageAttributes())
                {
                    g.Clear(System.Drawing.Color.White);   // a transparent PNG on white, not black
                    g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                    g.PixelOffsetMode = PixelOffsetMode.HighQuality;
                    g.CompositingQuality = CompositingQuality.HighQuality;
                    g.SmoothingMode = SmoothingMode.HighQuality;
                    attrs.SetWrapMode(WrapMode.TileFlipXY);   // no grey line along the edges
                    if (color != Color)
                    {
                        // luminance (ITU-R BT.601), the same weights OCR engines use
                        float r = 0.299f, gr = 0.587f, b = 0.114f;
                        attrs.SetColorMatrix(new ColorMatrix(new[]
                        {
                            new[] { r, r, r, 0f, 0f }, new[] { gr, gr, gr, 0f, 0f }, new[] { b, b, b, 0f, 0f },
                            new[] { 0f, 0f, 0f, 1f, 0f }, new[] { 0f, 0f, 0f, 0f, 1f },
                        }));
                    }
                    g.DrawImage(src, new Rectangle(0, 0, nw, nh), 0, 0, w, h, GraphicsUnit.Pixel, attrs);
                }

                byte[] outData;
                string outType, outExt;
                if (color == Bw)
                {
                    using var bw = ToBlackWhite(bmp);
                    using var o = new MemoryStream();
                    bw.Save(o, ImageFormat.Png);
                    (outData, outType, outExt) = (o.ToArray(), "image/png", ".png");
                }
                else
                {
                    (outData, outType, outExt) = (Jpeg(bmp, JpegQuality), "image/jpeg", ".jpg");
                }
                // only a re-encode (nothing smaller, no colour change, upright already) that came out bigger: keep the original
                if (outData.Length >= data.Length && scale >= 1 && color == Color && flip == RotateFlipType.RotateNoneFlipNone && simple)
                    return asIs with { Width = w, Height = h };
                return new Page(outData, outType, outExt, nw, nh, true);
            }
        }

        private static byte[] Jpeg(Bitmap bmp, long quality)
        {
            var codec = ImageCodecInfo.GetImageEncoders().First(c => c.FormatID == ImageFormat.Jpeg.Guid);
            using var p = new EncoderParameters(1);
            p.Param[0] = new EncoderParameter(System.Drawing.Imaging.Encoder.Quality, quality);
            using var o = new MemoryStream();
            bmp.Save(o, codec, p);
            return o.ToArray();
        }

        // a gray 24-bit bitmap → 1-bit black / white at the Otsu threshold of its histogram
        private static Bitmap ToBlackWhite(Bitmap gray)
        {
            int w = gray.Width, h = gray.Height;
            var src = gray.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.ReadOnly, PixelFormat.Format24bppRgb);
            var rows = new byte[src.Stride * h];
            Marshal.Copy(src.Scan0, rows, 0, rows.Length);
            var stride = src.Stride;
            gray.UnlockBits(src);

            var hist = new long[256];
            for (var y = 0; y < h; y++)
                for (int x = 0, i = y * stride; x < w; x++, i += 3) hist[rows[i]]++;
            var t = Otsu(hist, (long)w * h);

            var bw = new Bitmap(w, h, PixelFormat.Format1bppIndexed);   // palette: 0 black, 1 white
            var dst = bw.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.WriteOnly, PixelFormat.Format1bppIndexed);
            var line = new byte[dst.Stride];
            for (var y = 0; y < h; y++)
            {
                Array.Clear(line);
                for (int x = 0, i = y * stride; x < w; x++, i += 3)
                    if (rows[i] > t) line[x >> 3] |= (byte)(0x80 >> (x & 7));
                Marshal.Copy(line, 0, dst.Scan0 + y * dst.Stride, line.Length);
            }
            bw.UnlockBits(dst);
            return bw;
        }

        private static int Otsu(long[] hist, long total)
        {
            double sum = 0;
            for (var i = 0; i < 256; i++) sum += i * (double)hist[i];
            double sumB = 0, best = -1;
            long wB = 0;
            var t = 128;
            for (var i = 0; i < 256; i++)
            {
                wB += hist[i];
                if (wB == 0) continue;
                var wF = total - wB;
                if (wF == 0) break;
                sumB += i * (double)hist[i];
                double mB = sumB / wB, mF = (sum - sumB) / wF;
                var between = (double)wB * wF * (mB - mF) * (mB - mF);
                if (between > best) { best = between; t = i; }
            }
            return t;
        }

        // EXIF orientation (0x0112) of a phone photo → the turn that makes it upright
        private static RotateFlipType Orientation(Image img)
        {
            try
            {
                if (!img.PropertyIdList.Contains(0x0112)) return RotateFlipType.RotateNoneFlipNone;
                var v = img.GetPropertyItem(0x0112)?.Value;
                return v is { Length: > 0 } ? v[0] switch
                {
                    2 => RotateFlipType.RotateNoneFlipX,
                    3 => RotateFlipType.Rotate180FlipNone,
                    4 => RotateFlipType.RotateNoneFlipY,
                    5 => RotateFlipType.Rotate90FlipX,
                    6 => RotateFlipType.Rotate90FlipNone,
                    7 => RotateFlipType.Rotate270FlipX,
                    8 => RotateFlipType.Rotate270FlipNone,
                    _ => RotateFlipType.RotateNoneFlipNone,
                } : RotateFlipType.RotateNoneFlipNone;
            }
            catch (Exception) { return RotateFlipType.RotateNoneFlipNone; }
        }
    }
}
