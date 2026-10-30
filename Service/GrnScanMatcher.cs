using System.Text;
using System.Text.RegularExpressions;
using ItemApi.Data;
using ItemApi.Models;

namespace ItemApi.Service
{
    // GRN scan, step 2 (Docs/StockSystem.md 6.31): our item for each invoice line.
    //   1. a saved match of the supplier (z_tb_SupplierItemMap): by the supplier's code, else by their item name;
    //      else a printed barcode of one active item (z_sp_GrnScanMatch)
    //   2. no match: the closest item names (Suggestions) - the user picks on the review page, and the pick is saved
    //      (SaveAsync) so the line matches by itself next time.
    // Closeness: letter triples shared by the two names (spaces and signs left out, so "SUNLIGHTYELLOW" and
    // "SUNLIGHT YELLOW" are alike), more when the pack size is the same (500G, 1KG, 450ML), when the item's first word
    // starts the supplier's name, and when the item's supplier is the invoice's supplier.
    public class GrnScanMatcher
    {
        private const int SuggestCount = 5;
        private const decimal MinScore = 0.15m;
        // unit cost this far from our cost price → the line is marked to check
        private const decimal CostChangeCheckPct = 10m;

        private static readonly Regex SizePattern = new(@"(\d+(?:\.\d+)?)\s*(KG|KGS|G|GM|GMS|GR|ML|L|LTR|LTRS)(?![A-WYZ])", RegexOptions.Compiled);
        private static readonly object CacheLock = new();
        private static (DateTime At, List<IndexedItem> Items)? _cache;

        private readonly AppDbContext _db;

        public GrnScanMatcher(AppDbContext db)
        {
            _db = db;
        }

        // capitals, letters and digits only (z_tb_SupplierItemMap.DescripKey)
        public static string NameKey(string? s)
        {
            var sb = new StringBuilder();
            foreach (var ch in (s ?? "").ToUpperInvariant())
                if (char.IsLetterOrDigit(ch)) sb.Append(ch);
            return sb.Length > 200 ? sb.ToString(0, 200) : sb.ToString();
        }

        private static string? Clean(string? s, int max)
        {
            var t = s?.Trim();
            return string.IsNullOrEmpty(t) ? null : t.Length > max ? t[..max] : t;
        }

        public async Task MatchAsync(int suppId, List<GrnScanLine> lines)
        {
            if (lines.Count == 0) return;
            var rows = await _db.GrnScanMatchAsync(suppId,
                lines.Select((l, i) => (i + 1, Clean(l.SupplierCode, 50), NameKey(l.Description) is { Length: > 0 } k ? k : null, Clean(l.Barcode, 100))));
            var byKey = rows.ToDictionary(r => r.LineKey);
            List<IndexedItem>? index = null;

            for (var i = 0; i < lines.Count; i++)
            {
                var l = lines[i];
                l.ItemId = null; l.MatchedBy = null; l.MapId = null; l.Item = null; l.CostChangePct = null;
                l.Suggestions = new List<GrnScanItemHit>();
                l.Issues.RemoveAll(x => x.StartsWith(MatchNote));

                if (byKey.TryGetValue(i + 1, out var m) && m.ItemId != null)
                {
                    l.ItemId = m.ItemId;
                    l.MatchedBy = m.MatchedBy;
                    l.MapId = m.MapId;
                    l.Item = new GrnScanItemHit
                    {
                        ItemId = m.ItemId.Value, RefCode = m.RefCode, Barcode = m.ItemBarcode, Descrip = m.ItemDescrip,
                        RetailPrice = m.RetailPrice, CostPrice = m.CostPrice, Status = m.ItemStatus
                    };
                    l.CaseSize ??= m.MapCaseSize;
                    if (m.ItemStatus != 1)
                        AddIssue(l, MatchNote + "the matched item is not active - pick another.");
                    PriceChecks(l);
                }
                else
                {
                    index ??= await IndexAsync();
                    l.Suggestions = Rank(index, l.Description, suppId, SuggestCount);
                }
            }
        }

        // the item picker: closest names (codes and barcodes typed are found as they are)
        public async Task<List<GrnScanItemHit>> SearchAsync(int suppId, string text, int count = 15)
        {
            var index = await IndexAsync();
            var t = text.Trim();
            var exact = index.Where(x => x.Row.RefCode == t || x.Row.Barcode == t || x.Row.ItemId.ToString() == t)
                .Select(x => Hit(x, suppId, 1m)).ToList();
            // every word typed must be in the name (any order), like the till search
            var words = Regex.Matches(t.ToUpperInvariant(), "[A-Z0-9]+").Select(m => m.Value).ToList();
            var ranked = Rank(index, t, suppId, count, words.Count > 0 ? words : null);
            return exact.Concat(ranked.Where(r => exact.All(e => e.ItemId != r.ItemId))).Take(count).ToList();
        }

        // the matches confirmed on the review page (one per supplier code, or per name without a code)
        public async Task<int> SaveAsync(GrnScanSaveRequest r, int? userId)
        {
            var rows = r.Lines
                .Where(l => l.ItemId > 0 && (Clean(l.SupplierCode, 50) != null || NameKey(l.Description).Length > 0))
                .Select(l => new GrnScanMapRow
                {
                    SupplierCode = Clean(l.SupplierCode, 50),
                    SupplierDescrip = Clean(l.Description, 200) ?? Clean(l.SupplierCode, 50)!,
                    DescripKey = NameKey(l.Description) is { Length: > 0 } k ? k : NameKey(l.SupplierCode),
                    ItemId = l.ItemId,
                    CaseSize = l.CaseSize > 0 ? l.CaseSize : null
                })
                // the same supplier item twice on one invoice: the last pick counts
                .GroupBy(x => x.SupplierCode != null ? "C:" + x.SupplierCode : "N:" + x.DescripKey)
                .Select(g => g.Last())
                .ToList();
            return rows.Count == 0 ? 0 : await _db.GrnScanSaveMapsAsync(r.SupplierId, rows, userId);
        }

        // The confirmed lines become a suspended GRN (z_sp_GrnScanMakeDraft); their matches are kept for next time.
        // Cost a piece = (gross - discount) / (qty + free): the GRN commit takes the line cost for the stock cost.
        // Qty = bought + free, FreeQty = the free ones. A free line (nothing bought, e.g. "2 free" printed on a line of its
        // own) goes onto the bought line of the same item and lowers its cost; with no bought line of that item it is a
        // line of its own at the item's cost now, amount 0 (what the paper prints for it is not paid).
        public async Task<(GrnScanDraftResult Draft, int MatchesSaved)> MakeDraftAsync(GrnScanDraftRequest r, int? userId)
        {
            if (r.Lines.Count == 0) throw new GrnScanException("Choose the lines to put on the GRN.");
            var mrp = string.Equals(r.SellPrice, "mrp", StringComparison.OrdinalIgnoreCase);
            var rows = new List<GrnScanDraftRow>();
            var freeLines = new List<(int Key, GrnScanDraftLine Line)>();
            for (var i = 0; i < r.Lines.Count; i++)
            {
                var l = r.Lines[i];
                var net = l.GrossAmount - (l.Discount ?? 0);
                if (l.ItemId <= 0) throw new GrnScanException($"Line {i + 1}: choose our item.");
                if (l.Qty < 0 || l.FreeQty < 0) throw new GrnScanException($"Line {i + 1}: a qty below 0.");
                if (l.Qty == 0 && l.FreeQty > 0)
                {
                    freeLines.Add((i + 1, l));
                    continue;
                }
                if (l.Qty == 0) throw new GrnScanException($"Line {i + 1}: no qty.");
                if (net < 0) throw new GrnScanException($"Line {i + 1}: the discount is more than the amount.");
                rows.Add(new GrnScanDraftRow
                {
                    LineKey = i + 1, ItemId = l.ItemId, Qty = l.Qty + (l.FreeQty ?? 0), FreeQty = l.FreeQty > 0 ? l.FreeQty : null,
                    SellPrice = mrp && l.Mrp > 0 ? l.Mrp : null, GAmount = net
                });
            }
            var bought = rows.ToList();
            foreach (var (key, l) in freeLines)
            {
                var to = bought.FirstOrDefault(x => x.ItemId == l.ItemId);
                if (to != null)
                {
                    to.Qty += l.FreeQty!.Value;
                    to.FreeQty = (to.FreeQty ?? 0) + l.FreeQty.Value;
                }
                else
                    rows.Add(new GrnScanDraftRow
                    {
                        LineKey = key, ItemId = l.ItemId, Qty = l.FreeQty!.Value, FreeQty = l.FreeQty, CostPrice = null,
                        SellPrice = mrp && l.Mrp > 0 ? l.Mrp : null, GAmount = 0
                    });
            }
            foreach (var x in bought) x.CostPrice = Math.Round(x.GAmount / x.Qty, 2);
            foreach (var x in rows)
            {
                x.Qty = Math.Round(x.Qty, 2);
                x.FreeQty = x.FreeQty is { } f ? Math.Round(f, 2) : null;
                x.GAmount = Math.Round(x.GAmount, 2);
            }
            rows = rows.OrderBy(x => x.LineKey).ToList();
            var invoiceNo = Clean(r.InvoiceNo, 30);
            var remark = "GRN scan" + (invoiceNo != null ? " - invoice " + invoiceNo : "") +
                         (Clean(r.InvoiceDate, 20) is { } d ? " of " + d : "");
            var draft = await _db.GrnScanMakeDraftAsync(r.SupplierId, invoiceNo, remark, r.AllowSameInvoice, rows);

            // every line again: a code / name already saved only counts one more use
            var saved = await SaveAsync(new GrnScanSaveRequest
            {
                SupplierId = r.SupplierId,
                Lines = r.Lines.Select(l => new GrnScanSaveLine { SupplierCode = l.SupplierCode, Description = l.Description, ItemId = l.ItemId, CaseSize = l.CaseSize }).ToList()
            }, userId);
            return (draft, saved);
        }

        // ─── price checks of a matched line ───

        private const string MatchNote = "Item: ";

        private static void PriceChecks(GrnScanLine l)
        {
            var it = l.Item!;
            if (l.UnitCost > 0 && it.CostPrice > 0)
            {
                l.CostChangePct = Math.Round((l.UnitCost.Value - it.CostPrice.Value) / it.CostPrice.Value * 100, 1);
                if (Math.Abs(l.CostChangePct.Value) >= CostChangeCheckPct)
                    AddIssue(l, $"{MatchNote}cost {l.UnitCost:0.00} is {l.CostChangePct:+0.#;-0.#}% from our cost {it.CostPrice:0.00} - right item? right qty?");
            }
            if (l.Mrp > 0 && it.RetailPrice > 0 && l.Mrp != it.RetailPrice)
                AddIssue(l, $"{MatchNote}MRP {l.Mrp:0.00}, our price {it.RetailPrice:0.00}.");
        }

        private static void AddIssue(GrnScanLine l, string issue)
        {
            l.Issues.Add(issue);
            if (l.Status == "ok") l.Status = "check";
        }

        // ─── closest names ───

        private sealed class IndexedItem
        {
            public GrnScanItemRow Row = new();
            public HashSet<string> Grams = new();
            public HashSet<decimal> Sizes = new();
            public string FirstWord = "";
            public string Key = "";
        }

        // active items, kept 5 minutes
        private async Task<List<IndexedItem>> IndexAsync()
        {
            lock (CacheLock)
                if (_cache is { } c && c.At > DateTime.Now.AddMinutes(-5))
                    return c.Items;
            var items = (await _db.GrnScanItemsAsync()).Select(r =>
            {
                var upper = (r.Descrip ?? "").ToUpperInvariant();
                return new IndexedItem
                {
                    Row = r,
                    Key = NameKey(upper),
                    Grams = Grams(NameKey(upper)),
                    Sizes = Sizes(upper),
                    FirstWord = Regex.Match(upper, "[A-Z0-9]{3,}").Value
                };
            }).ToList();
            lock (CacheLock)
                _cache = (DateTime.Now, items);
            return items;
        }

        private static List<GrnScanItemHit> Rank(List<IndexedItem> index, string? text, int suppId, int count, List<string>? mustContain = null)
        {
            var upper = (text ?? "").ToUpperInvariant();
            var key = NameKey(upper);
            if (key.Length < 2) return new List<GrnScanItemHit>();
            var grams = Grams(key);
            var sizes = Sizes(upper);

            return index
                .Where(x => mustContain == null || mustContain.All(w => x.Key.Contains(w)))
                .Select(x =>
                {
                    var shared = x.Grams.Count == 0 ? 0 : x.Grams.Count(grams.Contains);
                    var score = grams.Count + x.Grams.Count == 0 ? 0m : 2m * shared / (grams.Count + x.Grams.Count);
                    if (sizes.Count > 0 && x.Sizes.Count > 0)
                        score += sizes.Overlaps(x.Sizes) ? 0.25m : -0.1m;
                    if (x.FirstWord.Length >= 3 && key.StartsWith(x.FirstWord)) score += 0.1m;
                    if (suppId > 0 && x.Row.SupId == suppId) score += 0.1m;
                    return (Item: x, Score: score);
                })
                .Where(s => mustContain != null || s.Score >= MinScore)
                .OrderByDescending(s => s.Score)
                .Take(count)
                .Select(s => Hit(s.Item, suppId, Math.Min(1m, Math.Round(s.Score, 2))))
                .ToList();
        }

        private static GrnScanItemHit Hit(IndexedItem x, int suppId, decimal score) => new()
        {
            ItemId = x.Row.ItemId, RefCode = x.Row.RefCode, Barcode = x.Row.Barcode, Descrip = x.Row.Descrip,
            RetailPrice = x.Row.RetailPrice, CostPrice = x.Row.CostPrice, Status = 1,
            SameSupplier = suppId > 0 && x.Row.SupId == suppId, Score = score
        };

        private static HashSet<string> Grams(string key)
        {
            var set = new HashSet<string>();
            for (var i = 0; i + 3 <= key.Length; i++) set.Add(key.Substring(i, 3));
            return set;
        }

        // pack sizes in grams / ml: 500G → 500, 1KG → 1000, 1L → 1000 ("500GX36" = 500G a piece, 36 in a case)
        private static HashSet<decimal> Sizes(string upper)
        {
            var set = new HashSet<decimal>();
            foreach (Match m in SizePattern.Matches(upper))
            {
                if (!decimal.TryParse(m.Groups[1].Value, System.Globalization.NumberStyles.Number, System.Globalization.CultureInfo.InvariantCulture, out var n)) continue;
                var unit = m.Groups[2].Value;
                set.Add(unit.StartsWith("K") || unit.StartsWith("L") ? n * 1000 : n);
            }
            return set;
        }
    }
}
