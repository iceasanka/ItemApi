using ItemApi.Models;
using ItemApi.Service;
using Microsoft.AspNetCore.Mvc;

namespace ItemApi.Controllers
{
    // "Print 80mm" on the back office pages (Day Reports summary, Paid in / out, Z report): the page sends the report as
    // slip lines and it is printed straight on the bill printer (thermal) of Settings > Printers - no print preview.
    [Route("api/[controller]")]
    [ApiController]
    public class SlipPrintController : ControllerBase
    {
        private readonly PrinterConfig _printers;

        public SlipPrintController(PrinterConfig printers) => _printers = printers;

        // POST: api/SlipPrint  { docName, items: [{ kind, text, align, bold, tall, rows: [{ cells, bold, head }] }] }
        [HttpPost]
        public async Task<IActionResult> Print([FromBody] SlipPrintRequest request)
        {
            if (request == null || request.Items.Count == 0)
                return BadRequest(new { message = "Nothing to print." });

            try
            {
                var p = await _printers.GetAsync();
                var slip = new ReceiptSlip(p.BillChars);
                foreach (var it in request.Items)
                {
                    switch (it.Kind?.ToLowerInvariant())
                    {
                        case "blank":
                            slip.Line();
                            break;
                        case "divider":
                            slip.Divider(string.IsNullOrEmpty(it.Text) ? '-' : it.Text[0]);
                            break;
                        case "table":
                            slip.Table((it.Rows ?? new()).Select(r => ((IReadOnlyList<string>)r.Cells, r.Bold, r.Head)).ToList());
                            break;
                        default:
                            var align = it.Align?.ToLowerInvariant() switch
                            {
                                "center" => SlipAlign.Center,
                                "right" => SlipAlign.Right,
                                _ => SlipAlign.Left,
                            };
                            // a long text wraps over more lines instead of being cut
                            foreach (var part in Wrap(it.Text ?? "", slip.Width))
                                slip.Line(part, align, it.Bold, it.Tall);
                            break;
                    }
                }
                await slip.PrintAsync(p.NeedBill(), string.IsNullOrWhiteSpace(request.DocName) ? "Report" : request.DocName.Trim(), p.BillEscPos);
                return Ok(new { message = "Sent to the bill printer." });
            }
            catch (InvalidOperationException ex)
            {
                // no bill printer chosen, or it is not installed on the server
                return BadRequest(new { message = ex.Message });
            }
            catch (Exception ex)
            {
                Serilog.Log.Error(ex, "Slip {Doc} not printed", request.DocName);
                return StatusCode(500, new { message = $"Not printed: {ex.Message}" });
            }
        }

        private static IEnumerable<string> Wrap(string text, int width)
        {
            text = text.Trim();
            if (text.Length == 0)
            {
                yield return "";
                yield break;
            }
            while (text.Length > width)
            {
                var cut = text.LastIndexOf(' ', width);
                if (cut <= 0) cut = width;
                yield return text[..cut].TrimEnd();
                text = text[cut..].TrimStart();
            }
            if (text.Length > 0)
                yield return text;
        }
    }
}
