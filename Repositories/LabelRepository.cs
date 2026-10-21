using System.Drawing.Printing;
using System.Text;
using ItemApi.Data;
using ItemApi.Interface;
using ItemApi.Models;
using ItemApi.Service;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using Serilog;

namespace ItemApi.Repositories
{
    // Labels without BarTender — layouts in z_tb_LabelLayout, items from z_tb_Item / z_tb_ItemDet.
    //   kind 1 barcode labels: ZPL straight to the Zebra (Windows printer name or ip:9100). Docs/StockSystem.md §6.20.
    //   kind 2 price labels: drawn here, printed through the Windows printer driver (Sinhala). §6.21.
    // The printer is on the API server. The old BarTender routes (api/Util/print…) are not used here.
    public class LabelRepository : ILabelRepository
    {
        private const int MaxLabelsPerPrint = 5000;
        private const int MaxPriceLabelsPerPrint = 1000;
        private static readonly string[] BarcodeTypes = { "AUTO", "CODE128", "EAN13" };
        private static readonly string[] PriceStyles = { "AUTO", "PRICE", "DISCOUNT" };
        private static readonly int[] DpiValues = { 203, 300, 600 };

        private readonly AppDbContext _context;
        private readonly int _locationId;
        private readonly string? _zebraPrinter;
        private readonly string? _pricePrinter;

        public LabelRepository(AppDbContext context, IOptions<AppSettings> appSettings)
        {
            _context = context;
            _locationId = appSettings.Value.LocationId;
            _zebraPrinter = appSettings.Value.PrinterZebra;
            // the printer the old BarTender price labels used (PegasusPR8003)
            _pricePrinter = appSettings.Value.PrinterName;
        }

        public async Task<List<LabelLayout>> GetLayoutsAsync(int? kind, bool includeDeleted)
        {
            return await _context.LabelLayouts.AsNoTracking()
                .Where(l => (includeDeleted || l.Status == 1) && (kind == null || l.LabelKind == kind))
                .OrderBy(l => l.LabelKind).ThenByDescending(l => l.IsDefault).ThenBy(l => l.Name)
                .ToListAsync();
        }

        public async Task<LabelLayout?> GetLayoutAsync(int labelLayoutId)
        {
            return await _context.LabelLayouts.AsNoTracking().FirstOrDefaultAsync(l => l.LabelLayoutId == labelLayoutId);
        }

        // null id = new layout. The kind of a layout never changes.
        public async Task<LabelLayout> SaveLayoutAsync(int? labelLayoutId, LabelLayout request)
        {
            LabelLayout layout;
            if (labelLayoutId == null)
            {
                layout = new LabelLayout { LabelKind = request.LabelKind, CDate = DateTime.Now, Status = 1 };
                _context.LabelLayouts.Add(layout);
            }
            else
            {
                layout = await _context.LabelLayouts.FirstOrDefaultAsync(l => l.LabelLayoutId == labelLayoutId && l.Status == 1)
                         ?? throw new KeyNotFoundException();
            }
            request.LabelKind = layout.LabelKind;
            Validate(request);

            var name = request.Name.Trim();
            if (await _context.LabelLayouts.AnyAsync(l => l.Status == 1 && l.LabelKind == layout.LabelKind && l.Name == name
                                                          && l.LabelLayoutId != (labelLayoutId ?? 0)))
                throw new LabelException($"A label layout named '{name}' already exists.");

            layout.Name = name;
            layout.PrinterName = Blank(request.PrinterName);
            layout.PrinterAddress = layout.LabelKind == LabelLayout.Barcode ? Blank(request.PrinterAddress) : null;
            layout.Dpi = request.Dpi;
            layout.LabelWidthMm = request.LabelWidthMm;
            layout.LabelHeightMm = request.LabelHeightMm;
            layout.LabelsAcross = request.LabelsAcross;
            layout.RowsPerPage = request.RowsPerPage;
            layout.GapXMm = request.GapXMm;
            layout.GapYMm = request.GapYMm;
            layout.MarginLeftMm = request.MarginLeftMm;
            layout.MarginTopMm = request.MarginTopMm;
            layout.BarcodeType = (request.BarcodeType ?? "AUTO").Trim().ToUpperInvariant();
            layout.BarcodeHeightMm = request.BarcodeHeightMm;
            layout.ShowName = request.ShowName;
            layout.ShowPrice = request.ShowPrice;
            layout.ShowItemCode = request.ShowItemCode;
            layout.ShowDates = request.ShowDates;
            layout.Darkness = request.Darkness;
            layout.Language = request.Language;
            layout.Rotate = request.Rotate;
            layout.SinhalaFont = Blank(request.SinhalaFont);
            layout.EnglishFont = Blank(request.EnglishFont);
            layout.FooterText = Blank(request.FooterText);
            layout.UserId = request.UserId;
            layout.UDate = DateTime.Now;

            // one default per kind; the first layout of a kind is its default
            var others = await _context.LabelLayouts
                .Where(l => l.Status == 1 && l.LabelKind == layout.LabelKind && l.LabelLayoutId != layout.LabelLayoutId)
                .ToListAsync();
            layout.IsDefault = request.IsDefault || others.All(l => !l.IsDefault);
            if (layout.IsDefault)
                others.ForEach(l => l.IsDefault = false);

            await _context.SaveChangesAsync();
            return layout;
        }

        // Status 0. When it was the default, the next one of its kind (by name) becomes the default.
        public async Task DeleteLayoutAsync(int labelLayoutId, int? userId)
        {
            var layout = await _context.LabelLayouts.FirstOrDefaultAsync(l => l.LabelLayoutId == labelLayoutId && l.Status == 1)
                         ?? throw new KeyNotFoundException();
            layout.Status = 0;
            layout.UserId = userId;
            layout.UDate = DateTime.Now;
            if (layout.IsDefault)
            {
                layout.IsDefault = false;
                var next = await _context.LabelLayouts
                    .Where(l => l.Status == 1 && l.LabelKind == layout.LabelKind && l.LabelLayoutId != labelLayoutId)
                    .OrderBy(l => l.Name).FirstOrDefaultAsync();
                if (next != null) next.IsDefault = true;
            }
            await _context.SaveChangesAsync();
        }

        // Windows printers installed on the API server
        public List<string> GetPrinters()
        {
            return PrinterSettings.InstalledPrinters.Cast<string>().OrderBy(p => p).ToList();
        }

        // ---------------------------------------------------------------- barcode labels (kind 1)

        public async Task<(LabelLayout Layout, string Zpl, LabelPrintResult Result)> BuildAsync(LabelPrintRequest request)
        {
            var layout = await GetLayoutForPrintAsync(LabelLayout.Barcode, request.LabelLayoutId);
            var labels = await ReadLabelsAsync(request);

            CheckSkip(layout, request.Skip);
            ZplLabelBuilder.CheckFits(layout, labels);

            var slots = Enumerable.Repeat<LabelData?>(null, request.Skip).Concat(labels).ToList();
            var (zpl, pages) = ZplLabelBuilder.Build(layout, slots);
            return (layout, zpl, new LabelPrintResult
            {
                Labels = labels.Count,
                Pages = pages,
                Printer = PrinterOf(layout),
                LayoutName = layout.Name
            });
        }

        public async Task<LabelPrintResult> PrintAsync(LabelPrintRequest request)
        {
            var (layout, zpl, result) = await BuildAsync(request);
            await SendAsync(layout, zpl, "Labels");
            Log.Information("Labels printed: {Labels} on {Pages} pages, layout {Layout}, printer {Printer}, user {UserId}",
                result.Labels, result.Pages, layout.Name, result.Printer, request.UserId);
            return result;
        }

        // ---------------------------------------------------------------- price labels (kind 2)

        public async Task<LabelPrintResult> PrintPriceAsync(PriceLabelRequest request)
        {
            var (layout, slots, count) = await BuildPriceAsync(request);
            var printer = PrinterOf(layout);
            var pages = await PrintPriceSlotsAsync(layout, slots, printer, "Price labels", false);
            Log.Information("Price labels printed: {Labels} on {Pages} pages, layout {Layout}, printer {Printer}, user {UserId}",
                count, pages, layout.Name, printer, request.UserId);
            return new LabelPrintResult { Labels = count, Pages = pages, Printer = printer, LayoutName = layout.Name };
        }

        // One page as PNG — what Print would send (page 0 = the first)
        public async Task<byte[]> PreviewPriceAsync(PriceLabelRequest request, int page)
        {
            var (layout, slots, _) = await BuildPriceAsync(request);
            var pages = PriceLabelRenderer.PageCount(layout, slots.Count);
            if (page < 0 || page >= pages)
                throw new LabelException($"Page must be 0 to {pages - 1}.");
            return PriceLabelRenderer.Preview(layout, slots, page, borders: true);
        }

        private async Task<(LabelLayout Layout, List<PriceLabelData?> Slots, int Count)> BuildPriceAsync(PriceLabelRequest request)
        {
            var layout = await GetLayoutForPrintAsync(LabelLayout.Price, request.LabelLayoutId);
            if (request.Language is { } language)
            {
                if (language is < 1 or > 3)
                    throw new LabelException("Language must be 1 English, 2 Sinhala or 3 both.");
                layout.Language = language;   // not tracked: only for this print
            }
            CheckSkip(layout, request.Skip);
            CheckFonts(layout);
            var labels = await ReadPriceLabelsAsync(request);
            var slots = Enumerable.Repeat<PriceLabelData?>(null, request.Skip).Concat(labels).ToList();
            return (layout, slots, labels.Count);
        }

        private async Task<List<PriceLabelData>> ReadPriceLabelsAsync(PriceLabelRequest request)
        {
            var lines = request.Items ?? new();
            if (lines.Count == 0)
                throw new LabelException("Add at least one item.");
            if (lines.Any(l => l.Qty < 1 || l.Qty > 500))
                throw new LabelException("Labels per item must be 1 to 500.");
            if (lines.Sum(l => l.Qty) > MaxPriceLabelsPerPrint)
                throw new LabelException($"At most {MaxPriceLabelsPerPrint} price labels at once.");
            if (lines.Any(l => !PriceStyles.Contains((l.Style ?? "AUTO").Trim().ToUpperInvariant())))
                throw new LabelException("Style must be AUTO, PRICE or DISCOUNT.");
            if (lines.Any(l => l.Price is < 0 || l.DiscountAmount is < 0 || l.DiscountPercent is < 0 or > 100))
                throw new LabelException("Price and discount cannot be negative; discount % is 0 to 100.");

            var ids = lines.Select(l => l.ItemId).Distinct().ToList();
            var items = await (from i in _context.Itemzs.AsNoTracking()
                               join d in _context.ItemzDets.AsNoTracking().Where(d => d.LocationId == _locationId)
                                   on i.ItemId equals d.ItemId into dets
                               from d in dets.DefaultIfEmpty()
                               where ids.Contains(i.ItemId)
                               select new
                               {
                                   i.ItemId, i.RefCode, i.Descrip, i.Inv_Descrip, i.SinhalaDescrip,
                                   RetailPrice = d != null ? d.RetailPrice : null,
                                   DiscountAmount = d != null ? d.DiscountAmount : null,
                                   DiscountPercent = d != null ? d.DiscountPercent : null
                               })
                .ToDictionaryAsync(x => x.ItemId);

            var missing = ids.Where(id => !items.ContainsKey(id)).ToList();
            if (missing.Count > 0)
                throw new LabelException($"Item(s) not found: {string.Join(", ", missing)}.");

            var labels = new List<PriceLabelData>();
            foreach (var line in lines)
            {
                var item = items[line.ItemId];
                var name = (line.Name ?? (string.IsNullOrWhiteSpace(item.Inv_Descrip) ? item.Descrip : item.Inv_Descrip) ?? "").Trim();
                var price = line.Price ?? item.RetailPrice
                            ?? throw new LabelException($"'{name}' has no retail price at this location - type the price.");
                var amount = line.DiscountAmount ?? item.DiscountAmount;
                var percent = line.DiscountPercent ?? item.DiscountPercent;

                // as the old Discount print: an amount wins over a %
                var style = (line.Style ?? "AUTO").Trim().ToUpperInvariant();
                decimal? useAmount = null, usePercent = null;
                if (style != "PRICE")
                {
                    if (amount is > 0) useAmount = amount;
                    else if (percent is > 0) usePercent = percent;
                    else if (style == "DISCOUNT")
                        throw new LabelException($"'{name}' has no discount - enter a discount amount or %, or print a price label.");
                }
                if (useAmount > price)
                    throw new LabelException($"Discount of '{name}' (Rs {useAmount:0.00}) is more than its price (Rs {price:0.00}).");

                var label = new PriceLabelData
                {
                    ItemCode = (item.RefCode ?? "").Trim(),
                    Name = name,
                    SinhalaName = (line.SinhalaName ?? item.SinhalaDescrip ?? "").Trim(),
                    Price = price,
                    DiscountAmount = useAmount,
                    DiscountPercent = usePercent
                };
                labels.AddRange(Enumerable.Repeat(label, line.Qty));
            }
            return labels;
        }

        private static async Task<int> PrintPriceSlotsAsync(LabelLayout layout, List<PriceLabelData?> slots, string printer,
                                                            string docName, bool borders)
        {
            if (string.IsNullOrWhiteSpace(printer))
                throw new LabelException("No printer: set one on the label layout (or AppSettings:PrinterName).");
            try
            {
                return await Task.Run(() => PriceLabelRenderer.Print(printer, layout, slots, docName, borders));
            }
            catch (InvalidPrinterException ex)
            {
                throw new LabelException(ex.Message + " (on the API server).");
            }
            catch (System.ComponentModel.Win32Exception ex)
            {
                throw new LabelException($"Printer '{printer}': {ex.Message} (on the API server).");
            }
        }

        // ---------------------------------------------------------------- both

        // One page with a frame round every label and sample text — to check the size, gaps and margins.
        public async Task<LabelPrintResult> PrintTestAsync(int labelLayoutId)
        {
            var layout = await GetLayoutAsync(labelLayoutId);
            if (layout == null || layout.Status != 1)
                throw new KeyNotFoundException();
            var perPage = layout.LabelsAcross * layout.RowsPerPage;

            if (layout.LabelKind == LabelLayout.Price)
            {
                CheckFonts(layout);
                var printer = PrinterOf(layout);
                var pages = await PrintPriceSlotsAsync(layout, Enumerable.Repeat<PriceLabelData?>(PriceSample(layout), perPage).ToList(),
                    printer, "Price label test", true);
                return new LabelPrintResult { Labels = perPage, Pages = pages, Printer = printer, LayoutName = layout.Name };
            }

            var sample = new LabelData
            {
                Name = "TEST LABEL " + layout.Name,
                Barcode = "4796000000001",
                ItemCode = "000123",
                Price = 1234.50m,
                MfdDate = DateTime.Today,
                ExpDate = DateTime.Today.AddYears(1)
            };
            ZplLabelBuilder.CheckFits(layout, new[] { sample });
            var (zpl, zplPages) = ZplLabelBuilder.Build(layout, Enumerable.Repeat<LabelData?>(sample, perPage).ToList(), borders: true);
            await SendAsync(layout, zpl, "Label test");
            return new LabelPrintResult { Labels = perPage, Pages = zplPages, Printer = PrinterOf(layout), LayoutName = layout.Name };
        }

        // The test page of a price layout as PNG (no printer needed) — for the layout dialog's preview
        public async Task<byte[]> PreviewTestAsync(int labelLayoutId)
        {
            var layout = await GetLayoutAsync(labelLayoutId);
            if (layout == null || layout.Status != 1)
                throw new KeyNotFoundException();
            if (layout.LabelKind != LabelLayout.Price)
                throw new LabelException("Preview is for price label layouts.");
            CheckFonts(layout);
            var perPage = layout.LabelsAcross * layout.RowsPerPage;
            return PriceLabelRenderer.Preview(layout, Enumerable.Repeat<PriceLabelData?>(PriceSample(layout), perPage).ToList(), 0, true);
        }

        // Sinhala "Sample" (ආදර්ශය); with a discount so every part of the label shows
        private static PriceLabelData PriceSample(LabelLayout layout) => new()
        {
            ItemCode = "000123",
            Name = "TEST LABEL " + layout.Name,
            SinhalaName = "ආදර්ශය",
            Price = 1234.50m,
            DiscountAmount = 100m
        };

        private async Task<LabelLayout> GetLayoutForPrintAsync(int kind, int? labelLayoutId)
        {
            var layout = labelLayoutId == null
                ? await _context.LabelLayouts.AsNoTracking().FirstOrDefaultAsync(l => l.Status == 1 && l.LabelKind == kind && l.IsDefault)
                : await _context.LabelLayouts.AsNoTracking().FirstOrDefaultAsync(l => l.Status == 1 && l.LabelLayoutId == labelLayoutId);
            if (layout == null)
                throw new LabelException(labelLayoutId == null
                    ? $"No default {KindName(kind)} layout - add one on the Label layouts page."
                    : "This label layout was not found or was deleted.");
            if (layout.LabelKind != kind)
                throw new LabelException($"'{layout.Name}' is a {KindName(layout.LabelKind)} layout - pick a {KindName(kind)} layout.");
            return layout;
        }

        private static string KindName(int kind) => kind == LabelLayout.Price ? "price label" : "barcode label";

        private static void CheckSkip(LabelLayout layout, int skip)
        {
            var perPage = layout.LabelsAcross * layout.RowsPerPage;
            if (skip < 0 || skip >= perPage)
                throw new LabelException(perPage == 1
                    ? "Skip must be 0 for this layout (one label per page)."
                    : $"Skip must be 0 to {perPage - 1} (labels on one page).");
        }

        private static void CheckFonts(LabelLayout layout)
        {
            foreach (var font in new[] { layout.SinhalaFont ?? PriceLabelRenderer.DefaultSinhalaFont,
                                         layout.EnglishFont ?? PriceLabelRenderer.DefaultEnglishFont })
                if (!PriceLabelRenderer.FontExists(font))
                    throw new LabelException($"Font '{font}' is not installed on the API server.");
        }

        // One LabelData per label, in the order of the request (item 1 × qty, item 2 × qty …)
        private async Task<List<LabelData>> ReadLabelsAsync(LabelPrintRequest request)
        {
            var lines = request.Items ?? new();
            if (lines.Count == 0)
                throw new LabelException("Add at least one item.");
            if (lines.Any(l => l.Qty < 1 || l.Qty > 1000))
                throw new LabelException("Labels per item must be 1 to 1000.");
            if (lines.Any(l => l.Price is < 0))
                throw new LabelException("Price cannot be negative.");
            if (lines.Sum(l => l.Qty) > MaxLabelsPerPrint)
                throw new LabelException($"At most {MaxLabelsPerPrint} labels at once.");

            var ids = lines.Select(l => l.ItemId).Distinct().ToList();
            var items = await (from i in _context.Itemzs.AsNoTracking()
                               join d in _context.ItemzDets.AsNoTracking().Where(d => d.LocationId == _locationId)
                                   on i.ItemId equals d.ItemId into dets
                               from d in dets.DefaultIfEmpty()
                               where ids.Contains(i.ItemId)
                               select new { i.ItemId, i.RefCode, i.Barcode, i.Descrip, i.Inv_Descrip, RetailPrice = d != null ? d.RetailPrice : null })
                .ToDictionaryAsync(x => x.ItemId);

            var missing = ids.Where(id => !items.ContainsKey(id)).ToList();
            if (missing.Count > 0)
                throw new LabelException($"Item(s) not found: {string.Join(", ", missing)}.");

            var labels = new List<LabelData>();
            foreach (var line in lines)
            {
                var item = items[line.ItemId];
                var refCode = (item.RefCode ?? "").Trim();
                // no barcode: the item code — the till finds an item by its RefCode too
                var barcode = string.IsNullOrWhiteSpace(item.Barcode) ? refCode : item.Barcode.Trim();
                if (barcode.Length == 0)
                    throw new LabelException($"Item {item.ItemId} '{item.Descrip}' has no barcode and no item code.");
                if (barcode.Any(c => c < 32 || c > 126))
                    throw new LabelException($"Barcode '{barcode}' of '{item.Descrip}' has characters a barcode cannot hold.");

                var label = new LabelData
                {
                    // Inv_Descrip = the English print name (receipts use it too); the label font has no Sinhala
                    Name = (string.IsNullOrWhiteSpace(item.Inv_Descrip) ? item.Descrip ?? "" : item.Inv_Descrip).Trim(),
                    Barcode = barcode,
                    ItemCode = refCode,
                    Price = line.Price ?? item.RetailPrice,
                    MfdDate = line.MfdDate?.Date,
                    ExpDate = line.ExpDate?.Date
                };
                labels.AddRange(Enumerable.Repeat(label, line.Qty));
            }
            return labels;
        }

        private string PrinterOf(LabelLayout layout) => layout.LabelKind == LabelLayout.Price
            ? layout.PrinterName ?? _pricePrinter ?? ""
            : layout.PrinterName ?? layout.PrinterAddress ?? _zebraPrinter ?? "";

        private async Task SendAsync(LabelLayout layout, string zpl, string docName)
        {
            var data = Encoding.UTF8.GetBytes(zpl);
            if (layout.PrinterName == null && layout.PrinterAddress != null)
            {
                await RawPrinter.SendToNetworkAsync(layout.PrinterAddress, data, TimeSpan.FromSeconds(10));
                return;
            }
            var printer = layout.PrinterName ?? _zebraPrinter;
            if (string.IsNullOrWhiteSpace(printer))
                throw new LabelException("No printer: set one on the label layout (or AppSettings:PrinterZebra).");
            try
            {
                await Task.Run(() => RawPrinter.SendToWindowsPrinter(printer, data, docName));
            }
            catch (System.ComponentModel.Win32Exception ex)
            {
                throw new LabelException(ex.Message + " (on the API server).");
            }
        }

        private static void Validate(LabelLayout l)
        {
            if (l.LabelKind is not (LabelLayout.Barcode or LabelLayout.Price))
                throw new LabelException("Label kind must be 1 (barcode) or 2 (price).");
            if (string.IsNullOrWhiteSpace(l.Name) || l.Name.Trim().Length > 50)
                throw new LabelException("Name is required, max 50 characters.");
            if (l.LabelWidthMm is < 10 or > 200 || l.LabelHeightMm is < 8 or > 300)
                throw new LabelException("Label width must be 10 to 200 mm and height 8 to 300 mm.");
            if (l.LabelsAcross is < 1 or > 10 || l.RowsPerPage is < 1 or > 50)
                throw new LabelException("Labels across must be 1 to 10 and rows per page 1 to 50.");
            if (l.GapXMm is < 0 or > 50 || l.GapYMm is < 0 or > 50 || l.MarginLeftMm is < 0 or > 50 || l.MarginTopMm is < 0 or > 50)
                throw new LabelException("Gaps and margins must be 0 to 50 mm.");
            if ((l.PrinterName?.Trim().Length ?? 0) > 100 || (l.PrinterAddress?.Trim().Length ?? 0) > 50)
                throw new LabelException("Printer name max 100 and printer address max 50 characters.");

            if (l.LabelKind == LabelLayout.Price)
            {
                // A4 is 210 × 297
                var (w, h) = PriceLabelRenderer.PageSize(l);
                if (w > 220 || h > 300)
                    throw new LabelException("Margin + labels + gaps is bigger than an A4 page (210 × 297 mm).");
                if (l.Language is < 1 or > 3)
                    throw new LabelException("Language must be 1 English, 2 Sinhala or 3 both.");
                if ((l.SinhalaFont?.Trim().Length ?? 0) > 50 || (l.EnglishFont?.Trim().Length ?? 0) > 50 || (l.FooterText?.Trim().Length ?? 0) > 100)
                    throw new LabelException("Font names max 50 and footer text max 100 characters.");
                CheckFonts(new LabelLayout { SinhalaFont = Blank(l.SinhalaFont), EnglishFont = Blank(l.EnglishFont) });
                return;
            }

            if (!DpiValues.Contains(l.Dpi))
                throw new LabelException("DPI must be 203, 300 or 600 (it is in the printer's name, e.g. ZD220 203DPI).");
            if (l.MarginLeftMm + l.LabelsAcross * l.LabelWidthMm + (l.LabelsAcross - 1) * l.GapXMm > 220)
                throw new LabelException("Margin + labels across + gaps is wider than 220 mm - no label printer is that wide.");
            if (!BarcodeTypes.Contains((l.BarcodeType ?? "").Trim().ToUpperInvariant()))
                throw new LabelException("Barcode type must be AUTO, CODE128 or EAN13.");
            if (l.BarcodeHeightMm is < 0 or > 100)
                throw new LabelException("Barcode height must be 0 (fit the label) to 100 mm.");
            if (l.Darkness is < 0 or > 30)
                throw new LabelException("Darkness must be 0 to 30, or empty for the printer's own setting.");
        }

        private static string? Blank(string? s) => string.IsNullOrWhiteSpace(s) ? null : s.Trim();
    }
}
