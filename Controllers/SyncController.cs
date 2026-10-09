using ItemApi.Hubs;
using ItemApi.Interface;
using ItemApi.Models;
using System.Security.Cryptography;
using System.Text;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.SignalR;
using Microsoft.Data.SqlClient;
using Serilog;

namespace ItemApi.Controllers
{
    // Cashier till sync + Z report reconcile. Called by the till app (DOWN: items, stock; UP: invoices, Z)
    // and by the back office UI (terminals, Z report screens). See Docs/StockSystem.md.
    // The till-called routes are [AllowAnonymous] (tills have no user token). Cashiers needs the shared terminal key;
    // TODO: the other till routes are still open — add a per-terminal API key before going live.
    [Route("api/[controller]")]
    [ApiController]
    public class SyncController : ControllerBase
    {
        private readonly ISyncRepository _repository;
        private readonly IHubContext<SalesHub> _salesHub;
        private readonly bool _livePush;
        private readonly string? _terminalKey;

        public const string TerminalKeyHeader = "X-Terminal-Key";

        public SyncController(ISyncRepository repository, IHubContext<SalesHub> salesHub, IConfiguration config)
        {
            _repository = repository;
            _salesHub = salesHub;
            _livePush = config.GetValue("Dashboard:LivePush", true);
            _terminalKey = config["Sync:TerminalKey"];
        }

        // ─── Terminals (back office) ─────────────────────────────────────────────

        // POST: api/Sync/Terminal
        [HttpPost("Terminal")]
        public async Task<IActionResult> RegisterTerminal([FromBody] TerminalRegisterRequest request)
        {
            if (request == null || request.TerminalId <= 0 || string.IsNullOrWhiteSpace(request.TerminalCode))
                return BadRequest(new { message = "TerminalId and TerminalCode are required." });

            try
            {
                var result = await _repository.RegisterTerminalAsync(request);
                return Ok(new { message = "Terminal saved.", data = result });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = "Internal Server Error", error = ex.Message });
            }
        }

        // GET: api/Sync/Terminals
        [HttpGet("Terminals")]
        public async Task<IActionResult> Terminals()
        {
            try
            {
                return Ok(await _repository.GetTerminalsAsync());
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = "Internal Server Error", error = ex.Message });
            }
        }

        // ─── Download (till) ─────────────────────────────────────────────────────

        // GET: api/Sync/Items?terminalId=1&since=2026-09-30T10:00:00   (no since = everything)
        [AllowAnonymous]
        [HttpGet("Items")]
        public async Task<IActionResult> Items([FromQuery] int terminalId, [FromQuery] DateTime? since)
        {
            try
            {
                return Ok(await _repository.GetItemsAsync(terminalId, since));
            }
            catch (SqlException ex) when (ex.Number >= 50000)
            {
                return BadRequest(new { message = ex.Message });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = "Internal Server Error", error = ex.Message });
            }
        }

        // GET: api/Sync/StockBalances?terminalId=1&since=...
        [AllowAnonymous]
        [HttpGet("StockBalances")]
        public async Task<IActionResult> StockBalances([FromQuery] int terminalId, [FromQuery] DateTime? since)
        {
            try
            {
                return Ok(await _repository.GetStockBalancesAsync(terminalId, since));
            }
            catch (SqlException ex) when (ex.Number >= 50000)
            {
                return BadRequest(new { message = ex.Message });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = "Internal Server Error", error = ex.Message });
            }
        }

        // GET: api/Sync/PriceLinks?terminalId=1&since=...   (deleted links come back with status 0)
        [AllowAnonymous]
        [HttpGet("PriceLinks")]
        public async Task<IActionResult> PriceLinks([FromQuery] int terminalId, [FromQuery] DateTime? since)
        {
            try
            {
                return Ok(await _repository.GetPriceLinksAsync(terminalId, since));
            }
            catch (SqlException ex) when (ex.Number >= 50000)
            {
                return BadRequest(new { message = ex.Message });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = "Internal Server Error", error = ex.Message });
            }
        }

        // GET: api/Sync/Cashiers?terminalId=1&since=...   header X-Terminal-Key = Sync:TerminalKey
        // Users for the till's offline sign-in, WITH their password hashes — so unlike the other till downloads it needs
        // the shared terminal key (same value in each TillService's Sync:TerminalKey). No key set here → refused.
        [AllowAnonymous]
        [HttpGet("Cashiers")]
        public async Task<IActionResult> Cashiers([FromQuery] int terminalId, [FromQuery] DateTime? since)
        {
            if (string.IsNullOrEmpty(_terminalKey))
                return StatusCode(403, new { message = "Set Sync:TerminalKey on the back office API (and the same key on each till)." });
            var sent = Request.Headers[TerminalKeyHeader].ToString();
            if (!CryptographicOperations.FixedTimeEquals(Encoding.UTF8.GetBytes(sent), Encoding.UTF8.GetBytes(_terminalKey)))
                return StatusCode(403, new { message = "Wrong terminal key (Sync:TerminalKey)." });

            try
            {
                return Ok(await _repository.GetCashiersAsync(terminalId, since));
            }
            catch (SqlException ex) when (ex.Number >= 50000)
            {
                return BadRequest(new { message = ex.Message });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = "Internal Server Error", error = ex.Message });
            }
        }

        // ─── Upload (till) ───────────────────────────────────────────────────────

        // POST: api/Sync/Invoices — send up to ~50 at a time; an empty list is a heartbeat
        [AllowAnonymous]
        [HttpPost("Invoices")]
        public async Task<IActionResult> Invoices([FromBody] SyncInvoiceBatch batch)
        {
            if (batch == null || batch.TerminalId <= 0)
                return BadRequest(new { message = "TerminalId is required." });

            try
            {
                var results = await _repository.UploadInvoicesAsync(batch);

                // home page live sales: tell open dashboards to reload. Never fails the upload.
                var newBills = results.Count(r => r.Result == "Inserted");
                if (_livePush && newBills > 0)
                {
                    try
                    {
                        await _salesHub.Clients.All.SendAsync(SalesHub.SalesChanged,
                            new SalesChangedEvent { TerminalId = batch.TerminalId, NewBills = newBills, At = DateTime.Now });
                    }
                    catch (Exception ex)
                    {
                        Log.Warning($"salesChanged not sent: {ex.Message}");
                    }
                }
                return Ok(results);
            }
            catch (SqlException ex) when (ex.Number >= 50000)
            {
                return BadRequest(new { message = ex.Message });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = "Internal Server Error", error = ex.Message });
            }
        }

        // POST: api/Sync/ZReport — Status 3 reconciled; 4 mismatch → resend MissingInvoiceNos, then submit again
        [AllowAnonymous]
        [HttpPost("ZReport")]
        public async Task<IActionResult> ZReport([FromBody] ZReportSubmit z)
        {
            if (z == null || z.TerminalId <= 0 || z.ZNo <= 0)
                return BadRequest(new { message = "TerminalId and ZNo are required." });

            try
            {
                return Ok(await _repository.SubmitZReportAsync(z));
            }
            catch (SqlException ex) when (ex.Number >= 50000)
            {
                return BadRequest(new { message = ex.Message });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = "Internal Server Error", error = ex.Message });
            }
        }

        // ─── Z reports (back office) ─────────────────────────────────────────────

        // GET: api/Sync/ZReport/1/15
        [HttpGet("ZReport/{terminalId}/{zNo}")]
        public async Task<IActionResult> GetZReport(int terminalId, int zNo)
        {
            try
            {
                var result = await _repository.GetZReportAsync(terminalId, zNo);
                if (result == null)
                    return NotFound(new { message = $"Z {zNo} of terminal {terminalId} not found.", status = false });

                return Ok(result);
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = "Internal Server Error", error = ex.Message });
            }
        }

        // POST: api/Sync/ZReport/1/15/Reconcile — check again (e.g. after missing bills arrived)
        [HttpPost("ZReport/{terminalId}/{zNo}/Reconcile")]
        public async Task<IActionResult> Reconcile(int terminalId, int zNo)
        {
            try
            {
                return Ok(await _repository.ReconcileZReportAsync(terminalId, zNo));
            }
            catch (SqlException ex) when (ex.Number >= 50000)
            {
                return BadRequest(new { message = ex.Message });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = "Internal Server Error", error = ex.Message });
            }
        }

        // POST: api/Sync/ZReports/Search
        [HttpPost("ZReports/Search")]
        public async Task<IActionResult> SearchZReports([FromBody] ZReportSearchRequest request)
        {
            try
            {
                return Ok(await _repository.SearchZReportsAsync(request));
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = "Internal Server Error", error = ex.Message });
            }
        }
    }
}
