using ItemApi.Common;
using ItemApi.Data;
using ItemApi.Models;
using ItemApi.Service;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace ItemApi.Controllers
{
    // Cheque Writer: the cheque preview, the cheque layout (where each part prints) and its test print, and printing
    // a saved cheque again. The cheque itself is printed by api/Util/printCheque (save + print). No BarTender.
    // DBScript/29_BackOffice_ChequeLayout.sql (U049), Service/ChequePrinter.cs, StockSystem.md 6.36.
    [ApiController]
    [Route("api/[controller]")]
    public class ChequePrintController : ControllerBase
    {
        private readonly AppDbContext _context;
        private readonly PrinterConfig _printers;

        public ChequePrintController(AppDbContext context, PrinterConfig printers)
        {
            _context = context;
            _printers = printers;
        }

        // the general printer of Settings > Printers; empty = refused by ChequePrinter.CheckPrinter
        private async Task<string> PrinterAsync() => (await _printers.GetAsync()).General;

        // GET api/ChequePrint/layout -> { layout, saved, hasPrevious, updatedAt, updatedBy, printer }
        [HttpGet("layout")]
        public async Task<IActionResult> GetLayout()
        {
            var info = await _context.GetChequeLayoutAsync();
            info.Printer = await PrinterAsync();
            return Ok(info);
        }

        // the positions measured from the old BarTender template
        [HttpGet("layout/defaults")]
        public IActionResult Defaults() => Ok(new ChequeLayout());

        [HttpPut("layout")]
        [Authorize(Roles = UserRoles.AdminName)]
        public async Task<IActionResult> SaveLayout([FromBody] ChequeLayout layout)
        {
            var error = layout.Error();
            if (error != null) return BadRequest(new { message = error });
            await _context.SaveChequeLayoutAsync(layout, Who());
            return Ok(new { ok = true });
        }

        [HttpPost("layout/undo")]
        [Authorize(Roles = UserRoles.AdminName)]
        public async Task<IActionResult> UndoLayout()
        {
            if (await _context.UndoChequeLayoutAsync(Who()) == 0)
                return BadRequest(new { message = "There is no earlier layout." });
            return Ok(new { ok = true });
        }

        // POST api/ChequePrint/preview { payee, amount, amountInWords, chequeDate, layout? } -> { image (png, base64), problems }
        // the picture is drawn by the same code that prints the cheque; problems = why it would not print
        [HttpPost("preview")]
        public async Task<IActionResult> Preview([FromBody] ChequePreviewRequest req)
        {
            var layout = req.Layout ?? (await _context.GetChequeLayoutAsync()).Layout;
            var error = layout.Error();
            if (error != null) return BadRequest(new { message = error });
            var laid = ChequePrinter.Lay(layout, req);
            return Ok(new { image = Convert.ToBase64String(ChequePrinter.PreviewPng(layout, laid)), problems = laid.Problems });
        }

        // test print with the cheque's outlines, on plain paper (or a photocopy of a cheque) put in like a cheque.
        // Nothing is saved. Uses the layout sent (being adjusted) or the saved one.
        [HttpPost("test")]
        public async Task<IActionResult> Test([FromBody] ChequePreviewRequest req)
        {
            var layout = req.Layout ?? (await _context.GetChequeLayoutAsync()).Layout;
            var error = layout.Error();
            if (error != null) return BadRequest(new { message = error });
            if (req.Amount <= 0) req.Amount = 123456.78m;
            if (string.IsNullOrWhiteSpace(req.Payee)) req.Payee = "TEST PRINT - NOT A CHEQUE";
            if (string.IsNullOrWhiteSpace(req.AmountInWords)) req.AmountInWords = "One Hundred Twenty Three Thousand Four Hundred Fifty Six Rupees and Seventy Eight Cents Only";
            if (req.ChequeDate == default) req.ChequeDate = DateTime.Today;
            var laid = ChequePrinter.Lay(layout, req);
            try
            {
                var printer = await PrinterAsync();
                ChequePrinter.CheckPrinter(printer);
                await Task.Run(() => ChequePrinter.Print(printer, layout, laid, "Cheque layout test", test: true));
            }
            catch (ChequePrintException ex)
            {
                return BadRequest(new { message = ex.Message });
            }
            return Ok(new { message = "Test page sent to " + await PrinterAsync(), problems = laid.Problems });
        }

        // POST api/ChequePrint/reprint { chequeNumber, payee, amount, amountInWords, chequeDate }
        // only for a cheque already saved with that number, amount and date (it was saved but did not print)
        [HttpPost("reprint")]
        public async Task<IActionResult> Reprint([FromBody] ChequeReprintRequest req)
        {
            var saved = await _context.Cheques.AsNoTracking().FirstOrDefaultAsync(c => c.ChequeNumber == req.ChequeNumber);
            if (saved == null)
                return BadRequest(new { message = $"Cheque {req.ChequeNumber} is not saved - write it again." });
            if (saved.Amount != req.Amount || saved.ChequeDate.Date != req.ChequeDate.Date)
                return BadRequest(new { message = $"Cheque {req.ChequeNumber} was saved with Rs {saved.Amount:0.00} on {saved.ChequeDate:yyyy-MM-dd} - the amount / date here differ. Nothing printed." });

            var layout = (await _context.GetChequeLayoutAsync()).Layout;
            var laid = ChequePrinter.Lay(layout, req);
            if (laid.Problems.Count > 0)
                return BadRequest(new { message = string.Join(" ", laid.Problems) });
            try
            {
                var printer = await PrinterAsync();
                ChequePrinter.CheckPrinter(printer);
                await Task.Run(() => ChequePrinter.Print(printer, layout, laid, $"Cheque {req.ChequeNumber}", test: false));
            }
            catch (Exception ex)
            {
                Serilog.Log.Error(ex, "Cheque {No} reprint failed", req.ChequeNumber);
                return BadRequest(new { message = $"Cheque {req.ChequeNumber} did not print: {ex.Message}" });
            }
            Serilog.Log.Information("Cheque {No} printed again (Rs {Amount})", req.ChequeNumber, req.Amount);
            return Ok(new { message = $"Cheque {req.ChequeNumber} printed." });
        }

        private string? Who() => User.Identity?.Name ?? (User.CurrentUserId() is int id ? $"user {id}" : null);
    }

    public class ChequeReprintRequest : ChequePrintData
    {
        public int ChequeNumber { get; set; }
    }
}
