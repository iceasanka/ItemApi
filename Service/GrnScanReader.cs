using System.Diagnostics;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using ItemApi.Models;

namespace ItemApi.Service
{
    // GRN scan, step 1 (R&D, Docs/StockSystem.md 6.31): sends invoice photos to Google Gemini (generateContent, JSON
    // answer in a fixed schema) and checks the sums of every line. Config section "GrnScan":
    //   ApiKey       from Google AI Studio, in appsettings.json (an environment variable GrnScan__ApiKey wins over it).
    //                Never sent to the web page.
    //   Model        default gemini-3.5-flash (GET api/GrnScan/Models lists what the key can use; gemini-2.5-flash is
    //                closed to new keys, gemini-flash-latest / gemini-3.8-flash did not answer on 2026-10-29)
    //   SaveFolder   default Uploads/GrnScan - every read is kept there (images + Gemini's answer) to compare
    //                accuracy; "" = nothing kept
    //   TimeoutSeconds  default 120
    // Free tier: Google may use what is sent to improve its products, and has a daily request limit.
    public class GrnScanReader
    {
        public const int MaxImages = 4;
        public const long MaxImageBytes = 10 * 1024 * 1024;
        private const string BaseUrl = "https://generativelanguage.googleapis.com/v1beta/";
        private static readonly Dictionary<string, string> ImageTypes = new(StringComparer.OrdinalIgnoreCase)
        {
            [".jpg"] = "image/jpeg", [".jpeg"] = "image/jpeg", [".png"] = "image/png", [".webp"] = "image/webp",
            [".heic"] = "image/heic", [".heif"] = "image/heif"
        };
        private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web) { WriteIndented = true };

        private readonly HttpClient _http;
        private readonly IConfiguration _config;
        private readonly string _contentRoot;
        private readonly ILogger<GrnScanReader> _log;

        public GrnScanReader(HttpClient http, IConfiguration config, IWebHostEnvironment env, ILogger<GrnScanReader> log)
        {
            _http = http;
            _config = config;
            _contentRoot = env.ContentRootPath;
            _log = log;
            _http.Timeout = TimeSpan.FromSeconds(config.GetValue("GrnScan:TimeoutSeconds", 120));
        }

        private string Model => _config["GrnScan:Model"] is { Length: > 0 } m ? m : "gemini-3.5-flash";

        private string ApiKey => _config["GrnScan:ApiKey"] is { Length: > 0 } k
            ? k
            : throw new GrnScanException("GrnScan:ApiKey is not set - put the key from Google AI Studio in appsettings.json (GrnScan:ApiKey) and restart ItemApi.");

        public static string? ImageType(string fileName) => ImageTypes.GetValueOrDefault(Path.GetExtension(fileName));

        // models this key can call generateContent on (to pick GrnScan:Model)
        public async Task<List<string>> ListModelsAsync(CancellationToken ct)
        {
            using var req = new HttpRequestMessage(HttpMethod.Get, BaseUrl + "models?pageSize=200");
            req.Headers.Add("x-goog-api-key", ApiKey);
            using var res = await _http.SendAsync(req, ct);
            var body = await res.Content.ReadAsStringAsync(ct);
            if (!res.IsSuccessStatusCode)
                throw new GrnScanException($"Gemini: {GoogleError(body) ?? res.StatusCode.ToString()}", 502);
            var models = JsonNode.Parse(body)?["models"]?.AsArray() ?? new JsonArray();
            return models
                .Where(m => m?["supportedGenerationMethods"]?.AsArray().Any(x => x?.GetValue<string>() == "generateContent") == true)
                .Select(m => (m!["name"]?.GetValue<string>() ?? "").Replace("models/", ""))
                .Where(n => n.Length > 0)
                .OrderBy(n => n)
                .ToList();
        }

        // images: the pages of ONE invoice, in order
        public async Task<GrnScanResult> ReadAsync(List<(byte[] Data, string MimeType, string FileName)> images, int? supplierId, CancellationToken ct)
        {
            var key = ApiKey;
            var parts = new JsonArray { new JsonObject { ["text"] = Prompt } };
            foreach (var img in images)
                parts.Add(new JsonObject
                {
                    ["inlineData"] = new JsonObject { ["mimeType"] = img.MimeType, ["data"] = Convert.ToBase64String(img.Data) }
                });
            var body = new JsonObject
            {
                ["contents"] = new JsonArray { new JsonObject { ["role"] = "user", ["parts"] = parts } },
                ["generationConfig"] = new JsonObject
                {
                    ["temperature"] = 0,
                    ["responseMimeType"] = "application/json",
                    ["responseSchema"] = Schema()
                }
            };

            var sw = Stopwatch.StartNew();
            var json = body.ToJsonString();
            HttpResponseMessage res;
            string answer;
            // "high demand" (503) / a server error on Google's side is usually gone in seconds: up to 2 more tries
            for (var attempt = 1; ; attempt++)
            {
                using var req = new HttpRequestMessage(HttpMethod.Post, $"{BaseUrl}models/{Uri.EscapeDataString(Model)}:generateContent");
                req.Headers.Add("x-goog-api-key", key);
                req.Content = new StringContent(json, Encoding.UTF8);
                req.Content.Headers.ContentType = new MediaTypeHeaderValue("application/json");
                try
                {
                    res = await _http.SendAsync(req, ct);
                }
                catch (TaskCanceledException) when (!ct.IsCancellationRequested)
                {
                    throw new GrnScanException("Gemini did not answer in time - try again, or with fewer / smaller photos.", 504);
                }
                answer = await res.Content.ReadAsStringAsync(ct);
                if ((int)res.StatusCode is not (500 or 503) || attempt == 3)
                    break;
                _log.LogInformation("GrnScan: Gemini {Status}, try {Attempt} again", (int)res.StatusCode, attempt + 1);
                res.Dispose();
                await Task.Delay(TimeSpan.FromSeconds(attempt * 10), ct);
            }
            using var _ = res;
            sw.Stop();
            if (!res.IsSuccessStatusCode)
            {
                _log.LogWarning("GrnScan: Gemini {Status} {Body}", (int)res.StatusCode, Trim(answer));
                var why = GoogleError(answer) ?? res.StatusCode.ToString();
                throw new GrnScanException((int)res.StatusCode == 429
                    ? "Gemini: request limit reached (free tier) - wait and try again. " + why
                    : "Gemini: " + why, 502);
            }

            var root = JsonNode.Parse(answer);
            var candidate = root?["candidates"]?[0];
            var text = candidate?["content"]?["parts"]?.AsArray()
                .Where(p => p?["thought"]?.GetValue<bool>() != true)
                .Select(p => p?["text"]?.GetValue<string>())
                .FirstOrDefault(t => !string.IsNullOrWhiteSpace(t));
            if (text == null)
                throw new GrnScanException("Gemini gave no answer (" + (candidate?["finishReason"]?.ToString()
                    ?? root?["promptFeedback"]?["blockReason"]?.ToString() ?? "empty") + ").", 502);

            GrnScanResult result;
            try
            {
                var doc = JsonSerializer.Deserialize<GeminiDoc>(text, Json) ?? new GeminiDoc();
                result = new GrnScanResult { Header = doc.Header ?? new GrnScanHeader(), Lines = doc.Lines ?? new List<GrnScanLine>() };
            }
            catch (JsonException ex)
            {
                _log.LogWarning("GrnScan: answer is not the JSON asked for: {Error} {Text}", ex.Message, Trim(text));
                throw new GrnScanException("Gemini's answer could not be read (" + candidate?["finishReason"] + "). Try again.", 502);
            }

            result.Model = Model;
            result.Images = images.Count;
            result.Ms = sw.ElapsedMilliseconds;
            result.SupplierId = supplierId;
            result.InputTokens = root?["usageMetadata"]?["promptTokenCount"]?.GetValue<int>();
            result.OutputTokens = root?["usageMetadata"]?["candidatesTokenCount"]?.GetValue<int>();
            Check(result);
            result.SavedAs = await SaveAsync(images, answer, result);
            return result;
        }

        // ─── checks ───

        // Qty, unit cost and whether each line adds up; the line sums against the totals printed.
        public static void Check(GrnScanResult r)
        {
            foreach (var l in r.Lines)
            {
                l.Issues.Clear();
                l.Qty = l.SaleQty ?? Pieces(l.SaleCases, l.SalePieces, l.CaseSize, l, "sale");
                l.FreeTotal = l.FreeQty ?? Pieces(l.FreeCases, l.FreePieces, l.CaseSize, l, "free");
                if (string.IsNullOrWhiteSpace(l.SupplierCode) && string.IsNullOrWhiteSpace(l.Barcode))
                    l.Issues.Add("No item code read.");
                l.UnitCost = null;
                l.AmountDiff = null;
                // free goods only (nothing bought): no price or amount to check, the GRN puts them on the item's bought line
                if (l.Qty is null or <= 0 && l.FreeTotal > 0)
                {
                    l.Issues.Add("Free only - goes on the GRN as free qty, nothing to pay.");
                    if (l.Unclear) l.Issues.Add("Hard to read" + (string.IsNullOrWhiteSpace(l.Note) ? "." : ": " + l.Note));
                    l.Status = "check";
                    continue;
                }
                if (l.Qty is null or <= 0) l.Issues.Add("No quantity.");
                if (l.UnitPrice is null or <= 0) l.Issues.Add("No unit price.");
                if (l.GrossAmount is null) l.Issues.Add("No amount.");

                var bad = l.Qty is null or <= 0 || l.UnitPrice is null or <= 0 || l.GrossAmount == null;
                if (!bad)
                {
                    l.AmountDiff = Math.Round(l.Qty!.Value * l.UnitPrice!.Value - l.GrossAmount!.Value, 2);
                    // printed unit prices are rounded to 2 decimals: allow 1 cent a piece (min Rs 1)
                    if (Math.Abs(l.AmountDiff.Value) > Math.Max(1m, l.Qty.Value * 0.01m))
                    {
                        l.Issues.Add($"Qty x price = {l.Qty * l.UnitPrice:0.00}, the paper says {l.GrossAmount:0.00}.");
                        bad = true;
                    }
                }
                if (l.Qty > 0 && l.GrossAmount != null)
                    l.UnitCost = Math.Round((l.GrossAmount.Value - (l.Discount ?? 0)) / l.Qty.Value, 4);
                if (l.Discount < 0 || (l.Discount > 0 && l.GrossAmount != null && l.Discount > l.GrossAmount))
                    l.Issues.Add("Discount looks wrong.");
                if (l.Mrp > 0 && l.UnitCost > l.Mrp)
                    l.Issues.Add($"Cost {l.UnitCost:0.00} is above the MRP {l.Mrp:0.00}.");
                if (l.Unclear) l.Issues.Add("Hard to read" + (string.IsNullOrWhiteSpace(l.Note) ? "." : ": " + l.Note));

                l.Status = bad ? "error" : l.Issues.Count > 0 ? "check" : "ok";
            }

            var c = r.Check;
            c.Lines = r.Lines.Count;
            c.LinesOk = r.Lines.Count(l => l.Status == "ok");
            c.LinesToCheck = r.Lines.Count(l => l.Status == "check");
            c.LinesWithError = r.Lines.Count(l => l.Status == "error");
            c.SumGross = r.Lines.Sum(l => l.GrossAmount ?? 0);
            c.SumDiscount = r.Lines.Sum(l => l.Discount ?? 0);
            if (r.Header.TotalGross != null)
            {
                c.GrossDiff = Math.Round(c.SumGross - r.Header.TotalGross.Value, 2);
                if (Math.Abs(c.GrossDiff.Value) > 1)
                    c.Issues.Add($"The lines add up to {c.SumGross:0.00}, the total printed is {r.Header.TotalGross:0.00} (a line may be missing or misread, or the total is on another page).");
            }
            else c.Issues.Add("No bill total read (it may be on the last page).");
            var nos = r.Lines.Where(l => l.LineNo != null).Select(l => l.LineNo!.Value).OrderBy(n => n).ToList();
            for (var i = 1; i < nos.Count; i++)
                if (nos[i] != nos[i - 1] + 1)
                    c.Issues.Add(nos[i] == nos[i - 1] ? $"Line {nos[i]} is there twice." : $"Line numbers jump from {nos[i - 1]} to {nos[i]} - a line may be missing.");
            var dupCodes = r.Lines.Where(l => !string.IsNullOrWhiteSpace(l.SupplierCode))
                .GroupBy(l => l.SupplierCode!.Trim()).Where(g => g.Count() > 1).Select(g => g.Key).ToList();
            if (dupCodes.Count > 0) c.Issues.Add("Same item code on more than one line: " + string.Join(", ", dupCodes) + ".");
        }

        private static decimal? Pieces(decimal? cases, decimal? pieces, decimal? caseSize, GrnScanLine l, string what)
        {
            if (cases is null or 0) return pieces;
            if (caseSize is null or <= 0)
            {
                l.Issues.Add($"{what} has {cases} case(s) but no case size.");
                return pieces;
            }
            return cases * caseSize + (pieces ?? 0);
        }

        // the folder of a kept read (photos page1.jpg ..., gemini.json, result.json); null = not kept, or not a scan name
        public string? ScanFolder(string? name)
        {
            var folder = _config["GrnScan:SaveFolder"] ?? "Uploads/GrnScan";
            if (folder.Length == 0 || name == null || !System.Text.RegularExpressions.Regex.IsMatch(name, "^[0-9]{8}-[0-9]{6}-[0-9a-f]{6}$"))
                return null;
            return Path.Combine(Path.IsPathRooted(folder) ? folder : Path.Combine(_contentRoot, folder), name);
        }

        // ─── kept for comparing accuracy ───

        private async Task<string?> SaveAsync(List<(byte[] Data, string MimeType, string FileName)> images, string geminiAnswer, GrnScanResult result)
        {
            var folder = _config["GrnScan:SaveFolder"] ?? "Uploads/GrnScan";
            if (folder.Length == 0) return null;
            try
            {
                var name = $"{DateTime.Now:yyyyMMdd-HHmmss}-{Guid.NewGuid().ToString("N")[..6]}";
                var dir = Path.Combine(Path.IsPathRooted(folder) ? folder : Path.Combine(_contentRoot, folder), name);
                Directory.CreateDirectory(dir);
                for (var i = 0; i < images.Count; i++)
                {
                    var ext = Path.GetExtension(images[i].FileName);
                    await File.WriteAllBytesAsync(Path.Combine(dir, $"page{i + 1}{(ext.Length > 0 ? ext.ToLowerInvariant() : ".jpg")}"), images[i].Data);
                }
                await File.WriteAllTextAsync(Path.Combine(dir, "gemini.json"), geminiAnswer);
                result.SavedAs = name;
                await File.WriteAllTextAsync(Path.Combine(dir, "result.json"), JsonSerializer.Serialize(result, Json));
                return name;
            }
            catch (Exception ex)
            {
                // never fail the read because the copy could not be kept
                _log.LogWarning(ex, "GrnScan: could not keep the scan in {Folder}", folder);
                return null;
            }
        }

        // ─── what is asked ───

        private const string Prompt = """
            You read supplier invoices / delivery notes for a retail shop in Sri Lanka (goods received, GRN).
            The images are the pages of ONE invoice, in order. Return the header once and EVERY item line of every page,
            in the printed order. Do not skip, merge or invent lines.

            Rules:
            - Copy numbers exactly as printed. Remove thousand separators ("4,581.84" -> 4581.84). Do not calculate or
              correct anything; a value that is not printed is null.
            - Ignore handwriting, ticks, circles and stamps written on the paper by hand; read only the printed text.
              (If a printed number is overwritten by hand so it cannot be read, give your best reading, set unclear = true
              and say why in note.)
            - supplierCode: the supplier's own item / SKU code at the start of the line (e.g. "3551304" from
              "3551304-SLT NAT LIQUID 450MLX20"). description: the rest of the item text, without the code.
              barcode: only when a separate barcode (EAN, 8-14 digits) is printed.
            - Quantity: when the invoice has case and piece columns (e.g. "Sale Qty CS / Pcs"), fill saleCases and
              salePieces and leave saleQty null. When it has one quantity column, fill saleQty only. Free quantity
              ("Free Qty") the same way in freeCases / freePieces / freeQty.
            - caseSize: pieces per case ("Case Config", "Pack size") when printed as a column.
            - unitPrice: the price per piece ("Price Per Unit"). grossAmount: the line amount before the line discount
              ("Gross Amount", "Value"). discount: the line discount ("Scheme Disc", "Disc") or null. mrp: the printed
              maximum retail price.
            - header: totals only when printed on these pages (the totals are often on the last page).
              invoiceDate as yyyy-MM-dd.
            """;

        private static JsonObject Schema()
        {
            JsonObject Str() => new() { ["type"] = "STRING", ["nullable"] = true };
            JsonObject Num() => new() { ["type"] = "NUMBER", ["nullable"] = true };
            var header = new JsonObject
            {
                ["type"] = "OBJECT",
                ["properties"] = new JsonObject
                {
                    ["supplierName"] = Str(), ["invoiceNo"] = Str(), ["invoiceDate"] = Str(), ["vatNo"] = Str(), ["pageText"] = Str(),
                    ["totalGross"] = Num(), ["totalDiscount"] = Num(), ["netTotal"] = Num()
                }
            };
            var line = new JsonObject
            {
                ["type"] = "OBJECT",
                ["properties"] = new JsonObject
                {
                    ["lineNo"] = new JsonObject { ["type"] = "INTEGER", ["nullable"] = true },
                    ["supplierCode"] = Str(), ["description"] = Str(), ["barcode"] = Str(),
                    ["saleCases"] = Num(), ["salePieces"] = Num(), ["saleQty"] = Num(),
                    ["freeCases"] = Num(), ["freePieces"] = Num(), ["freeQty"] = Num(),
                    ["caseSize"] = Num(), ["unitPrice"] = Num(), ["grossAmount"] = Num(), ["discount"] = Num(), ["mrp"] = Num(),
                    ["unclear"] = new JsonObject { ["type"] = "BOOLEAN" },
                    ["note"] = Str()
                },
                ["required"] = new JsonArray("description", "unclear"),
                ["propertyOrdering"] = new JsonArray("lineNo", "supplierCode", "description", "barcode", "saleCases", "salePieces",
                    "saleQty", "freeCases", "freePieces", "freeQty", "caseSize", "unitPrice", "grossAmount", "discount", "mrp", "unclear", "note")
            };
            return new JsonObject
            {
                ["type"] = "OBJECT",
                ["properties"] = new JsonObject { ["header"] = header, ["lines"] = new JsonObject { ["type"] = "ARRAY", ["items"] = line } },
                ["required"] = new JsonArray("header", "lines"),
                ["propertyOrdering"] = new JsonArray("header", "lines")
            };
        }

        private static string? GoogleError(string body)
        {
            try { return JsonNode.Parse(body)?["error"]?["message"]?.GetValue<string>(); }
            catch (JsonException) { return null; }
        }

        private static string Trim(string s) => s.Length > 2000 ? s[..2000] + "..." : s;

        private class GeminiDoc
        {
            public GrnScanHeader? Header { get; set; }
            public List<GrnScanLine>? Lines { get; set; }
        }
    }
}
