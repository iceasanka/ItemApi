using ItemApi.Interface;
using ItemApi.Models;
using ItemApi.Service;
using Microsoft.AspNetCore.Mvc;
using Serilog;

namespace ItemApi.Controllers
{
    // Back office quotations (DocType 1) and invoices (DocType 2), printed as A4 PDF. Document only — no stock or
    // customer balance effect, no tax. Docs/StockSystem.md §6.11, DBScript/06_BackOffice_SalesDoc.sql.
    [Route("api/[controller]")]
    [ApiController]
    public class SalesDocController : ControllerBase
    {
        private const long MaxLogoBytes = 2 * 1024 * 1024;
        private static readonly string[] LogoExtensions = { ".png", ".jpg", ".jpeg" };

        private readonly ISalesDocRepository _repository;
        private readonly SalesDocPdfService _pdf;

        public SalesDocController(ISalesDocRepository repository, SalesDocPdfService pdf)
        {
            _repository = repository;
            _pdf = pdf;
        }

        // POST: api/SalesDoc/Search { docType, fromDate, toDate, customerId, text, status, page, pageSize } → { total, rows }
        [HttpPost("Search")]
        public async Task<IActionResult> Search([FromBody] SalesDocSearchRequest request)
        {
            return await Run(async () => Ok(await _repository.SearchAsync(request ?? new SalesDocSearchRequest())));
        }

        // GET: api/SalesDoc/12 → { doc (with items), fromDocNo, invoiceDocId, invoiceDocNo }
        [HttpGet("{docId:int}")]
        public async Task<IActionResult> Get(int docId)
        {
            return await Run(async () =>
            {
                var detail = await _repository.GetAsync(docId);
                return detail == null ? NotFound(new { message = "Document not found." }) : Ok(detail);
            });
        }

        // POST: api/SalesDoc { docType, docDate, validUntil, customerId | custName+custAddress+custPhone, reference,
        //                      notes, discount, userId, items:[{ itemId (0 = typed), descrip, qty, unitPrice, discount }] }
        [HttpPost]
        public async Task<IActionResult> Create([FromBody] SalesDocRequest request)
        {
            if (request == null) return BadRequest(new { message = "Document is required." });
            return await Run(async () =>
            {
                var doc = await _repository.CreateAsync(request);
                return Ok(new { message = $"{Name(doc)} {doc.DocNo} saved.", data = doc });
            });
        }

        // PUT: api/SalesDoc/12 — open quotations and invoices (same body as POST; docType is ignored)
        [HttpPut("{docId:int}")]
        public async Task<IActionResult> Update(int docId, [FromBody] SalesDocRequest request)
        {
            if (request == null) return BadRequest(new { message = "Document is required." });
            return await Run(async () =>
            {
                var doc = await _repository.UpdateAsync(docId, request);
                return Ok(new { message = $"{Name(doc)} {doc.DocNo} saved.", data = doc });
            });
        }

        // POST: api/SalesDoc/12/Cancel { reason, userId }
        [HttpPost("{docId:int}/Cancel")]
        public async Task<IActionResult> Cancel(int docId, [FromBody] SalesDocCancelRequest request)
        {
            return await Run(async () =>
            {
                var doc = await _repository.CancelAsync(docId, request ?? new SalesDocCancelRequest());
                return Ok(new { message = $"{Name(doc)} {doc.DocNo} cancelled.", data = doc });
            });
        }

        // POST: api/SalesDoc/12/ToInvoice { docDate, userId } — new invoice with the quotation's lines
        [HttpPost("{docId:int}/ToInvoice")]
        public async Task<IActionResult> ToInvoice(int docId, [FromBody] SalesDocToInvoiceRequest? request)
        {
            return await Run(async () =>
            {
                var invoice = await _repository.ToInvoiceAsync(docId, request ?? new SalesDocToInvoiceRequest());
                return Ok(new { message = $"Invoice {invoice.DocNo} made.", data = invoice });
            });
        }

        // GET: api/SalesDoc/12/Pdf?download=false — A4 PDF (inline to view / print, download=true to save)
        [HttpGet("{docId:int}/Pdf")]
        public async Task<IActionResult> Pdf(int docId, [FromQuery] bool download = false)
        {
            return await Run(async () =>
            {
                var detail = await _repository.GetAsync(docId);
                if (detail == null) return NotFound(new { message = "Document not found." });
                var bytes = _pdf.Build(detail, await _repository.GetSettingAsync());
                var fileName = $"{detail.Doc.DocNo}.pdf";
                if (download) return File(bytes, "application/pdf", fileName);
                Response.Headers.ContentDisposition = $"inline; filename=\"{fileName}\"";
                return File(bytes, "application/pdf");
            });
        }

        // ─── Settings: company details and terms printed on the PDF ───

        // GET: api/SalesDoc/Settings
        [HttpGet("Settings")]
        public async Task<IActionResult> GetSettings()
        {
            return await Run(async () => Ok(await _repository.GetSettingAsync()));
        }

        // PUT: api/SalesDoc/Settings { companyName, companyAddress, companyPhone, companyEmail, quotationValidDays,
        //                              quotationTerms, invoiceTerms, userId }
        [HttpPut("Settings")]
        public async Task<IActionResult> UpdateSettings([FromBody] SalesDocSetting request)
        {
            if (request == null) return BadRequest(new { message = "Settings are required." });
            return await Run(async () =>
                Ok(new { message = "Settings saved.", data = await _repository.UpdateSettingAsync(request) }));
        }

        // GET: api/SalesDoc/Settings/Logo — the logo image (404 when none)
        [HttpGet("Settings/Logo")]
        public async Task<IActionResult> GetLogo()
        {
            return await Run(async () =>
            {
                var s = await _repository.GetSettingAsync();
                var path = s.LogoFile == null ? null : Path.Combine(_pdf.UploadsPath, s.LogoFile);
                if (path == null || !System.IO.File.Exists(path)) return NotFound(new { message = "No logo." });
                var type = Path.GetExtension(path).Equals(".png", StringComparison.OrdinalIgnoreCase) ? "image/png" : "image/jpeg";
                return PhysicalFile(path, type);
            });
        }

        // POST: api/SalesDoc/Settings/Logo (multipart: file, userId) — PNG or JPG, max 2 MB
        [HttpPost("Settings/Logo")]
        public async Task<IActionResult> UploadLogo(IFormFile file, [FromForm] int? userId)
        {
            if (file == null || file.Length == 0) return BadRequest(new { message = "Choose a logo file." });
            if (file.Length > MaxLogoBytes) return BadRequest(new { message = "Logo must be 2 MB or smaller." });
            var ext = Path.GetExtension(file.FileName).ToLowerInvariant();
            if (!LogoExtensions.Contains(ext)) return BadRequest(new { message = "Logo must be a PNG or JPG file." });

            return await Run(async () =>
            {
                Directory.CreateDirectory(_pdf.UploadsPath);
                var old = (await _repository.GetSettingAsync()).LogoFile;
                // a new name each time, so a browser never shows the old cached logo
                var name = $"company-logo-{DateTime.Now:yyyyMMddHHmmss}{ext}";
                await using (var stream = System.IO.File.Create(Path.Combine(_pdf.UploadsPath, name)))
                    await file.CopyToAsync(stream);
                var s = await _repository.SetLogoAsync(name, userId);
                DeleteLogoFile(old);
                return Ok(new { message = "Logo saved.", data = s });
            });
        }

        // DELETE: api/SalesDoc/Settings/Logo?userId=3
        [HttpDelete("Settings/Logo")]
        public async Task<IActionResult> DeleteLogo([FromQuery] int? userId)
        {
            return await Run(async () =>
            {
                var old = (await _repository.GetSettingAsync()).LogoFile;
                var s = await _repository.SetLogoAsync(null, userId);
                DeleteLogoFile(old);
                return Ok(new { message = "Logo removed.", data = s });
            });
        }

        private void DeleteLogoFile(string? fileName)
        {
            if (string.IsNullOrEmpty(fileName)) return;
            try
            {
                System.IO.File.Delete(Path.Combine(_pdf.UploadsPath, fileName));
            }
            catch (Exception ex)
            {
                Log.Warning($"Could not delete old logo {fileName}: {ex.Message}");
            }
        }

        private static string Name(SalesDoc doc) => doc.DocType == SalesDocType.Quotation ? "Quotation" : "Invoice";

        private async Task<IActionResult> Run(Func<Task<IActionResult>> action)
        {
            try
            {
                return await action();
            }
            catch (SalesDocException ex)
            {
                return BadRequest(new { message = ex.Message });
            }
            catch (KeyNotFoundException)
            {
                return NotFound(new { message = "Document not found." });
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex}");
                return StatusCode(500, new { message = "Internal Server Error", error = ex.Message });
            }
        }
    }
}
