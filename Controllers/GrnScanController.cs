using ItemApi.Common;
using ItemApi.Models;
using ItemApi.Service;
using Microsoft.AspNetCore.Mvc;
using Serilog;

namespace ItemApi.Controllers
{
    // GRN scan (R&D, Docs/StockSystem.md 6.31): read a supplier invoice photo with Google Gemini → header + lines with
    // the sums checked (step 1), each line matched to one of our items, and the matches confirmed on the review page
    // kept for next time (step 2, z_tb_SupplierItemMap), the lines in use made into a suspended GRN (step 3,
    // z_sp_GrnScanMakeDraft - committed on GRN Entry). The request body (photos) is not written to the request log.
    [Route("api/[controller]")]
    [ApiController]
    public class GrnScanController : ControllerBase
    {
        private readonly GrnScanReader _reader;
        private readonly GrnScanMatcher _matcher;
        private readonly GrnScanStore _store;

        public GrnScanController(GrnScanReader reader, GrnScanMatcher matcher, GrnScanStore store)
        {
            _reader = reader;
            _matcher = matcher;
            _store = store;
        }

        // POST: api/GrnScan/Read (multipart: files = 1-4 pages of ONE invoice, in order - photos and / or scanned pages;
        // supplierId) → { model, images, ms, supplierId, header, lines: [{ ..., qty, freeTotal, unitCost, amountDiff,
        //     status, issues, itemId, matchedBy, item, suggestions, costChangePct }], check, inputTokens, outputTokens, savedAs }.
        // Without supplierId the lines are read only (not matched). Every page is made small first (Settings > Scanner:
        // GrnScan.ImageSize / ImageColor, U061) - 3-4 big pages were more than Gemini takes in one request.
        [HttpPost("Read")]
        [RequestSizeLimit(110 * 1024 * 1024)]
        [RequestFormLimits(MultipartBodyLengthLimit = 110 * 1024 * 1024)]
        public async Task<IActionResult> Read([FromForm] List<IFormFile> files, [FromForm] int? supplierId,
            [FromServices] ItemApi.Data.AppDbContext db, CancellationToken ct)
        {
            files = files?.Where(f => f.Length > 0).ToList() ?? new List<IFormFile>();
            if (files.Count == 0) return BadRequest(new { message = "Choose a photo of the invoice." });
            if (files.Count > GrnScanReader.MaxImages) return BadRequest(new { message = $"At most {GrnScanReader.MaxImages} pages at a time." });

            var cfg = await GrnScanConfig.LoadAsync(db);
            var images = new List<(byte[] Data, string MimeType, string FileName)>();
            long came = 0;
            foreach (var f in files)
            {
                var type = GrnScanReader.ImageType(f.FileName);
                if (type == null) return BadRequest(new { message = $"{f.FileName}: send a JPG, PNG, WEBP, HEIC, BMP or TIFF image." });
                if (f.Length > GrnScanReader.MaxImageBytes)
                    return BadRequest(new { message = $"{f.FileName}: a page must be {GrnScanReader.MaxImageBytes / 1024 / 1024} MB or smaller." });
                using var ms = new MemoryStream();
                await f.CopyToAsync(ms, ct);
                came += ms.Length;
                var page = GrnScanImage.Prepare(ms.ToArray(), type, Path.GetExtension(f.FileName), cfg.MaxSide, cfg.Color);
                if (page.MimeType is "image/bmp" or "image/tiff")   // Gemini does not take these: it had to be converted
                    return BadRequest(new { message = $"{f.FileName}: this image could not be opened - send it as a JPG or PNG." });
                images.Add((page.Data, page.MimeType, Path.ChangeExtension(f.FileName, page.Ext)));
            }
            Log.Information("GrnScan: {Pages} page(s), {Came} KB came, {Sent} KB to Gemini (long side {Side}, {Color})",
                images.Count, came / 1024, images.Sum(i => (long)i.Data.Length) / 1024, cfg.MaxSide, cfg.Color);
            return await Run(async () =>
            {
                var result = await _reader.ReadAsync(images, supplierId, ct);
                if (supplierId > 0)
                    await _matcher.MatchAsync(supplierId.Value, result.Lines);
                // kept (z_tb_GrnScan), so the matching can go on another day without reading again
                result.ScanId = await _store.AddAsync(result, supplierId, User.CurrentUserId());
                return Ok(result);
            });
        }

        // GET: api/GrnScan/Scanner → { ready, feeder, dpi, imageSize, imageColor } - whether the page shows Scan
        [HttpGet("Scanner")]
        public async Task<IActionResult> Scanner([FromServices] ItemApi.Data.AppDbContext db)
        {
            var c = await GrnScanConfig.LoadAsync(db);
            return Ok(new { ready = c.Device.Length > 0, feeder = c.Feeder, dpi = c.Dpi, imageSize = c.MaxSide, imageColor = c.Color });
        }

        // POST: api/GrnScan/Scan?maxPages=4 — scan on the scanner of Settings > Scanner (flatbed: one page; feeder: every
        // page in it, up to maxPages), each page made small as for Read → { pages: [{ data (base64), mimeType, ext, width,
        // height, bytes }], cameBytes, ms }. The page adds them to its pages; they go to Gemini with Read.
        [HttpPost("Scan")]
        public async Task<IActionResult> Scan([FromQuery] int? maxPages, [FromServices] ItemApi.Data.AppDbContext db, CancellationToken ct)
        {
            return await Run(async () =>
            {
                var cfg = await GrnScanConfig.LoadAsync(db);
                var sw = System.Diagnostics.Stopwatch.StartNew();
                var raw = await GrnScanner.ScanAsync(cfg, Math.Clamp(maxPages ?? GrnScanReader.MaxImages, 1, GrnScanReader.MaxImages), ct);
                var pages = raw.Select(r => GrnScanImage.Prepare(r, "image/bmp", ".bmp", cfg.MaxSide, cfg.Color)).ToList();
                if (pages.Any(p => p.MimeType is not ("image/jpeg" or "image/png")))
                    throw new GrnScanException("The scanner sent an image that could not be opened.", 502);
                var came = raw.Sum(r => (long)r.Length);
                Log.Information("GrnScan: scanned {Pages} page(s) at {Dpi} DPI, {Came} KB → {Kept} KB in {Ms} ms",
                    pages.Count, cfg.Dpi, came / 1024, pages.Sum(p => (long)p.Data.Length) / 1024, sw.ElapsedMilliseconds);
                return Ok(new
                {
                    pages = pages.Select(p => new { data = Convert.ToBase64String(p.Data), mimeType = p.MimeType, ext = p.Ext, width = p.Width, height = p.Height, bytes = p.Data.Length }),
                    cameBytes = came,
                    ms = sw.ElapsedMilliseconds,
                });
            });
        }

        // POST: api/GrnScan/Match { supplierId, lines } — the lines of a read again: checks + matching (no new AI read, e.g.
        // after the supplier was changed or a qty fixed) → { lines, check }
        [HttpPost("Match")]
        public async Task<IActionResult> Match([FromBody] GrnScanMatchRequest request)
        {
            if (request == null) return BadRequest(new { message = "Lines are required." });
            if (request.SupplierId <= 0) return BadRequest(new { message = "Choose the supplier." });
            return await Run(async () =>
            {
                var result = new GrnScanResult { Lines = request.Lines ?? new List<GrnScanLine>() };
                GrnScanReader.Check(result);
                await _matcher.MatchAsync(request.SupplierId, result.Lines);
                return Ok(new { lines = result.Lines, check = result.Check });
            });
        }

        // GET: api/GrnScan/Items?supplierId=79&text=sunlight 500g — item picker: closest names first (a code / barcode typed
        // exactly comes first)
        [HttpGet("Items")]
        public async Task<IActionResult> Items([FromQuery] int supplierId, [FromQuery] string? text)
        {
            if (string.IsNullOrWhiteSpace(text)) return Ok(new List<GrnScanItemHit>());
            return await Run(async () => Ok(await _matcher.SearchAsync(supplierId, text)));
        }

        // POST: api/GrnScan/SaveMatches { supplierId, userId, lines: [{ supplierCode, description, itemId, caseSize }] } —
        // the matches confirmed on the review page; next time these lines match by themselves → { message, saved }
        [HttpPost("SaveMatches")]
        public async Task<IActionResult> SaveMatches([FromBody] GrnScanSaveRequest request)
        {
            if (request == null) return BadRequest(new { message = "Matches are required." });
            if (request.SupplierId <= 0) return BadRequest(new { message = "Choose the supplier." });
            return await Run(async () =>
            {
                var saved = await _matcher.SaveAsync(request, User.CurrentUserId(request.UserId));
                return Ok(new { message = saved == 0 ? "Nothing to save." : $"{saved} match(es) saved.", saved });
            });
        }

        // POST: api/GrnScan/MakeDraft { supplierId, invoiceNo, invoiceDate, sellPrice: "ours" | "mrp", allowSameInvoice,
        //   lines: [{ itemId, qty, freeQty, grossAmount, discount, mrp, supplierCode, description, caseSize }] } — a suspended
        //   GRN (open it on GRN Entry, check, commit) → { message, grnNo, lines, qty, amount, matchesSaved }.
        //   409 { message, sameInvoice: true } = this invoice no of the supplier is already on another GRN.
        [HttpPost("MakeDraft")]
        public async Task<IActionResult> MakeDraft([FromBody] GrnScanDraftRequest request)
        {
            if (request == null) return BadRequest(new { message = "Lines are required." });
            if (request.SupplierId <= 0) return BadRequest(new { message = "Choose the supplier." });
            try
            {
                return await Run(async () =>
                {
                    var userId = User.CurrentUserId(request.UserId);
                    var (d, saved, sup, notSet) = await _matcher.MakeDraftAsync(request, userId);
                    if (request.ScanId > 0)
                        await _store.MarkDraftAsync(request.ScanId.Value, d.GrnNo, userId);
                    var note = notSet ? " Item suppliers NOT set (run U062 on the db)."
                        : sup == null ? ""
                        : $" Item supplier set on {sup.Filled + sup.Replaced} item(s)" +
                          (sup.Replaced > 0 ? $" ({sup.Replaced} changed from another supplier)" : "") +
                          (sup.Other > 0 ? $"; {sup.Other} kept their other supplier" : "") + ".";
                    return Ok(new
                    {
                        message = $"{d.GrnNo} made - open it on GRN Entry to check and commit." + note,
                        grnNo = d.GrnNo, lines = d.Lines, qty = d.Qty, amount = d.Amount, matchesSaved = saved,
                        itemSupplier = sup, itemSupplierNotSet = notSet
                    });
                }, rethrowSameInvoice: true);
            }
            catch (Microsoft.Data.SqlClient.SqlException ex) when (ex.State == 2)
            {
                return Conflict(new { message = ex.Message, sameInvoice = true });
            }
        }

        // ─── saved scans (z_tb_GrnScan, U031) ───

        // GET: api/GrnScan/Scans?all=false — newest first: open ones (all = also those made into a GRN)
        [HttpGet("Scans")]
        public async Task<IActionResult> Scans([FromQuery] bool all = false)
        {
            return await Run(async () => Ok(await _store.ListAsync(all)));
        }

        // GET: api/GrnScan/Scans/5 → { scanId, suppId, suppName, status, grnNo, pages, result, state: { picks, skip } }
        [HttpGet("Scans/{scanId:int}")]
        public async Task<IActionResult> GetScan(int scanId)
        {
            return await Run(async () => await _store.GetAsync(scanId) is { } s ? Ok(s) : NotFound(new { message = "Scan not found (flushed?)." }));
        }

        // PUT: api/GrnScan/Scans/5 { supplierId, result, state: { picks, skip } } — the page keeps its work as it goes
        [HttpPut("Scans/{scanId:int}")]
        public async Task<IActionResult> SaveScan(int scanId, [FromBody] GrnScanSaveStateRequest request)
        {
            if (request == null) return BadRequest(new { message = "Nothing to save." });
            return await Run(async () =>
            {
                await _store.SaveStateAsync(scanId, request, User.CurrentUserId(request.UserId));
                return Ok(new { message = "Saved." });
            });
        }

        // DELETE: api/GrnScan/Scans/5/Draft — the GRN draft made from this scan is deleted (not once committed to stock);
        // the scan is open again to correct and make the draft again → { message, grnNo }
        [HttpDelete("Scans/{scanId:int}/Draft")]
        public async Task<IActionResult> DeleteDraft(int scanId)
        {
            return await Run(async () =>
            {
                var grnNo = await _store.DeleteDraftAsync(scanId, User.CurrentUserId());
                Log.Information($"GrnScan: draft {grnNo} of scan {scanId} deleted");
                return Ok(new { message = $"{grnNo} deleted - correct the scan and make the GRN draft again.", grnNo });
            });
        }

        // GET: api/GrnScan/Scans/5/Photo/1 — a page of the invoice
        [HttpGet("Scans/{scanId:int}/Photo/{page:int}")]
        public async Task<IActionResult> Photo(int scanId, int page)
        {
            return await Run(async () => await _store.PhotoAsync(scanId, page) is { } path
                ? PhysicalFile(path, GrnScanReader.ImageType(path) ?? "image/jpeg")
                : NotFound(new { message = "No such photo." }));
        }

        // POST: api/GrnScan/Scans/Flush { scanIds } — done with these scans: deleted with their photos → { message, flushed }
        [HttpPost("Scans/Flush")]
        public async Task<IActionResult> Flush([FromBody] GrnScanFlushRequest request)
        {
            if (request == null || request.ScanIds.Count == 0) return BadRequest(new { message = "Choose the scans to flush." });
            return await Run(async () =>
            {
                var n = await _store.FlushAsync(request.ScanIds);
                return Ok(new { message = $"{n} scan(s) flushed.", flushed = n });
            });
        }

        // GET: api/GrnScan/Maps?supplierId=79 — the saved matches of a supplier
        [HttpGet("Maps")]
        public async Task<IActionResult> Maps([FromQuery] int supplierId, [FromServices] ItemApi.Data.AppDbContext db)
        {
            return await Run(async () => Ok(await db.GrnScanGetMapsAsync(supplierId)));
        }

        // DELETE: api/GrnScan/Maps/12 — a wrong saved match (the line is matched by hand again next time)
        [HttpDelete("Maps/{mapId:int}")]
        public async Task<IActionResult> DeleteMap(int mapId, [FromServices] ItemApi.Data.AppDbContext db)
        {
            return await Run(async () => await db.GrnScanDeleteMapAsync(mapId) == 0
                ? NotFound(new { message = "Match not found." })
                : Ok(new { message = "Match removed." }));
        }

        // GET: api/GrnScan/Models — the Gemini models the key can use (for GrnScan:Model)
        [HttpGet("Models")]
        public async Task<IActionResult> Models(CancellationToken ct)
        {
            return await Run(async () => Ok(await _reader.ListModelsAsync(ct)));
        }

        private async Task<IActionResult> Run(Func<Task<IActionResult>> action, bool rethrowSameInvoice = false)
        {
            try
            {
                return await action();
            }
            catch (Microsoft.Data.SqlClient.SqlException ex) when (rethrowSameInvoice && ex.State == 2)
            {
                throw;
            }
            catch (GrnScanException ex)
            {
                return StatusCode(ex.StatusCode, new { message = ex.Message });
            }
            catch (KeyNotFoundException)
            {
                return NotFound(new { message = "Scan not found (flushed?)." });
            }
            catch (Microsoft.Data.SqlClient.SqlException ex) when (ex.Number == 50000)
            {
                return BadRequest(new { message = ex.Message });
            }
            catch (Microsoft.Data.SqlClient.SqlException ex) when (ex.Number == 2812 || ex.Number == 208)
            {
                Log.Error($"GrnScan: {ex.Message}");
                return StatusCode(500, new { message = "Run DBScript/Updates/U029_BackOffice_GrnScan.sql on the back office db first." });
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex}");
                return StatusCode(500, new { message = "Internal Server Error", error = ex.Message });
            }
        }
    }
}
