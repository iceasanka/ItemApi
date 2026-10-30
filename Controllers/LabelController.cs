using ItemApi.Common;
using ItemApi.Interface;
using ItemApi.Models;
using ItemApi.Service;
using Microsoft.AspNetCore.Mvc;
using Serilog;

namespace ItemApi.Controllers
{
    // Barcode labels straight to the Zebra as ZPL, with label layouts for each sticker size (back office
    // "Barcode labels" page). Docs/StockSystem.md §6.20, DBScript/16_BackOffice_LabelLayout.sql.
    // The old barcode page (api/Util/printbarcode → LocalPrintAgent → BarTender) is separate and unchanged.
    [Route("api/[controller]")]
    [ApiController]
    public class LabelController : ControllerBase
    {
        private readonly ILabelRepository _repository;

        public LabelController(ILabelRepository repository)
        {
            _repository = repository;
        }

        // GET: api/Label/Layouts?kind=2&all=true — kind 1 barcode, 2 price, none = both; the default first;
        // all=true also lists deleted ones
        [HttpGet("Layouts")]
        public async Task<IActionResult> GetLayouts([FromQuery] int? kind = null, [FromQuery] bool all = false)
        {
            return await Run(async () => Ok(await _repository.GetLayoutsAsync(kind, all)));
        }

        // GET: api/Label/Layouts/3
        [HttpGet("Layouts/{id:int}")]
        public async Task<IActionResult> GetLayout(int id)
        {
            return await Run(async () =>
            {
                var layout = await _repository.GetLayoutAsync(id);
                return layout == null ? NotFound(new { message = "Label layout not found." }) : Ok(layout);
            });
        }

        // POST: api/Label/Layouts { labelKind, name, labelWidthMm, labelHeightMm, labelsAcross, rowsPerPage, … }
        [HttpPost("Layouts")]
        public async Task<IActionResult> AddLayout([FromBody] LabelLayout request)
        {
            if (request == null)
                return BadRequest(new { message = "Layout is required." });
            request.UserId = User.CurrentUserId(request.UserId);
            return await Run(async () =>
                Ok(new { message = "Label layout added.", data = await _repository.SaveLayoutAsync(null, request) }));
        }

        // PUT: api/Label/Layouts/3
        [HttpPut("Layouts/{id:int}")]
        public async Task<IActionResult> UpdateLayout(int id, [FromBody] LabelLayout request)
        {
            if (request == null)
                return BadRequest(new { message = "Layout is required." });
            request.UserId = User.CurrentUserId(request.UserId);
            return await Run(async () =>
                Ok(new { message = "Label layout saved.", data = await _repository.SaveLayoutAsync(id, request) }));
        }

        // DELETE: api/Label/Layouts/3 — Status 0
        [HttpDelete("Layouts/{id:int}")]
        public async Task<IActionResult> DeleteLayout(int id)
        {
            return await Run(async () =>
            {
                await _repository.DeleteLayoutAsync(id, User.CurrentUserId());
                return Ok(new { message = "Label layout deleted." });
            });
        }

        // POST: api/Label/Layouts/3/Test — one page with a frame round every label, to check size, gaps and margins
        [HttpPost("Layouts/{id:int}/Test")]
        public async Task<IActionResult> TestLayout(int id)
        {
            return await Run(async () =>
            {
                var result = await _repository.PrintTestAsync(id);
                return Ok(new { message = $"Test page sent to {result.Printer}.", data = result });
            });
        }

        // GET: api/Label/Layouts/3/Preview — a price layout's test page as PNG (nothing is printed)
        [HttpGet("Layouts/{id:int}/Preview")]
        public async Task<IActionResult> PreviewLayout(int id)
        {
            return await Run(async () => File(await _repository.PreviewTestAsync(id), "image/png"));
        }

        // POST: api/Label/Layouts/Preview?discount=true — body = a price layout as it is on the page, not saved yet (the
        // designer); one label with the sample item as PNG. discount=false = the sample without a discount (footer shows).
        [HttpPost("Layouts/Preview")]
        public async Task<IActionResult> PreviewDesign([FromBody] LabelLayout request, [FromQuery] bool discount = true)
        {
            if (request == null)
                return BadRequest(new { message = "The layout is required." });
            return await Run(() => Task.FromResult<IActionResult>(File(_repository.PreviewDesign(request, discount), "image/png")));
        }

        // GET: api/Label/Printers — Windows printers on the API server (for the layout's printer list)
        [HttpGet("Printers")]
        public async Task<IActionResult> GetPrinters()
        {
            return await Run(() => Task.FromResult<IActionResult>(Ok(_repository.GetPrinters())));
        }

        // GET: api/Label/Fonts — fonts installed on the API server (the price label designer's font list)
        [HttpGet("Fonts")]
        public async Task<IActionResult> GetFonts()
        {
            return await Run(() => Task.FromResult<IActionResult>(Ok(PriceLabelRenderer.Fonts())));
        }

        // POST: api/Label/Print { labelLayoutId, skip, items: [{ itemId, qty, price, mfdDate, expDate }] }
        [HttpPost("Print")]
        public async Task<IActionResult> Print([FromBody] LabelPrintRequest request)
        {
            if (request == null)
                return BadRequest(new { message = "Items are required." });
            request.UserId = User.CurrentUserId(request.UserId);
            return await Run(async () =>
            {
                var result = await _repository.PrintAsync(request);
                return Ok(new { message = $"{result.Labels} labels sent to {result.Printer}.", data = result });
            });
        }

        // POST: api/Label/Zpl — same body as Print; returns the ZPL instead of printing (to check / save it)
        [HttpPost("Zpl")]
        public async Task<IActionResult> Zpl([FromBody] LabelPrintRequest request)
        {
            if (request == null)
                return BadRequest(new { message = "Items are required." });
            return await Run(async () =>
            {
                var (_, zpl, _) = await _repository.BuildAsync(request);
                return Content(zpl, "text/plain");
            });
        }

        // POST: api/Label/Preview?page=0 — same body as Print; that page as PNG, drawn from the ZPL (label frames in).
        // one=true: only the first item's label, on its own (the page's preview of the item picked)
        [HttpPost("Preview")]
        public async Task<IActionResult> Preview([FromBody] LabelPrintRequest request, [FromQuery] int page = 0,
                                                 [FromQuery] bool one = false)
        {
            if (request == null)
                return BadRequest(new { message = "Items are required." });
            return await Run(async () => File(await _repository.PreviewAsync(request, page, one), "image/png"));
        }

        // POST: api/Label/Price/Print { labelLayoutId, language, skip,
        //   items: [{ itemId, qty, style: AUTO|PRICE|DISCOUNT, price, discountAmount, discountPercent, name, sinhalaName }] }
        // Price labels through the Windows printer driver. The old api/Util/printprice … routes are not changed.
        [HttpPost("Price/Print")]
        public async Task<IActionResult> PrintPrice([FromBody] PriceLabelRequest request)
        {
            if (request == null)
                return BadRequest(new { message = "Items are required." });
            request.UserId = User.CurrentUserId(request.UserId);
            return await Run(async () =>
            {
                var result = await _repository.PrintPriceAsync(request);
                return Ok(new { message = $"{result.Labels} price labels sent to {result.Printer}.", data = result });
            });
        }

        // POST: api/Label/Price/Preview?page=0 — same body as Print; the page as PNG (label frames drawn in).
        // one=true: only the first item's label, on its own (the page's preview of the item picked)
        [HttpPost("Price/Preview")]
        public async Task<IActionResult> PreviewPrice([FromBody] PriceLabelRequest request, [FromQuery] int page = 0,
                                                      [FromQuery] bool one = false)
        {
            if (request == null)
                return BadRequest(new { message = "Items are required." });
            return await Run(async () => File(await _repository.PreviewPriceAsync(request, page, one), "image/png"));
        }

        private async Task<IActionResult> Run(Func<Task<IActionResult>> action)
        {
            try
            {
                return await action();
            }
            catch (LabelException ex)
            {
                return BadRequest(new { message = ex.Message });
            }
            catch (KeyNotFoundException)
            {
                return NotFound(new { message = "Label layout not found. Run DBScript/Updates/U010_BackOffice_LabelLayout.sql." });
            }
            catch (IOException ex)
            {
                return BadRequest(new { message = ex.Message });
            }
            catch (System.Net.Sockets.SocketException ex)
            {
                return BadRequest(new { message = "Printer not reachable: " + ex.Message });
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex}");
                return StatusCode(500, new { message = "Internal Server Error", error = ex.Message });
            }
        }
    }
}
