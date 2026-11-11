using ItemApi.Common;
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

        private readonly IServiceScopeFactory _scopes;

        public SyncController(ISyncRepository repository, IHubContext<SalesHub> salesHub, IConfiguration config, IServiceScopeFactory scopes)
        {
            _repository = repository;
            _scopes = scopes;
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

        // GET: api/Sync/CashSettlement/123?terminalId=1   header X-Terminal-Key = Sync:TerminalKey
        // A Cash Management slip scanned on the till (barcode CS-<till>-123): its counted cash (day end) and the cash
        // returned to the till (opening cash). 404 not found / a db without U055; 400 another till's slip or cancelled.
        // Whether it was already used on this till is checked by the till itself (its own Z / opening cash).
        [AllowAnonymous]
        [HttpGet("CashSettlement/{settlementId:int}")]
        public async Task<IActionResult> CashSettlement(int settlementId, [FromQuery] int terminalId,
                                                        [FromServices] ItemApi.Data.AppDbContext db)
        {
            if (string.IsNullOrEmpty(_terminalKey))
                return StatusCode(403, new { message = "Set Sync:TerminalKey on the back office API (and the same key on each till)." });
            var sent = Request.Headers[TerminalKeyHeader].ToString();
            if (!CryptographicOperations.FixedTimeEquals(Encoding.UTF8.GetBytes(sent), Encoding.UTF8.GetBytes(_terminalKey)))
                return StatusCode(403, new { message = "Wrong terminal key (Sync:TerminalKey)." });

            try
            {
                var s = await db.GetCashSettlementAsync(settlementId);
                if (s == null)
                    return NotFound(new { message = $"Cash slip {settlementId} not found on the back office." });
                if (s.TerminalId != terminalId)
                    return BadRequest(new { message = $"Cash slip {settlementId} is for till {s.TerminalCode}, not this till." });
                if (s.Status != 1)
                    return BadRequest(new { message = $"Cash slip {settlementId} was cancelled on the back office." });
                return Ok(new TillCashSettlement
                {
                    SettlementId = s.SettlementId, TerminalId = s.TerminalId, TerminalCode = s.TerminalCode,
                    CountedCash = s.CountedCash, ReturnedCash = s.ReturnedCash, BankCash = s.BankCash,
                    ZNo = s.ZNo, Status = s.Status, OpeningUsed = s.OpeningUsed, CreatedAt = s.CreatedAt
                });
            }
            catch (SqlException ex) when (ex.Number == 2812)
            {
                return NotFound(new { message = "The back office has no cash slips yet (run U055)." });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = "Internal Server Error", error = ex.Message });
            }
        }

        // GET: api/Sync/Settings?terminalId=1 — general settings and users' own values (§6.28), the whole list every
        // time (a few rows); the till replaces its copy. No secrets in it, so no terminal key.
        [AllowAnonymous]
        [HttpGet("Settings")]
        public async Task<IActionResult> Settings([FromQuery] int terminalId)
        {
            try
            {
                return Ok(await _repository.GetSettingsAsync());
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

        // POST: api/Sync/CashMovements — opening cash / paid in / paid out of a till (new rows, and an opening cash that
        // was replaced). A resend replaces the row. → { received }
        [AllowAnonymous]
        [HttpPost("CashMovements")]
        public async Task<IActionResult> CashMovements([FromBody] SyncCashMovementBatch batch)
        {
            if (batch == null || batch.TerminalId <= 0)
                return BadRequest(new { message = "TerminalId is required." });

            try
            {
                return Ok(await _repository.UploadCashMovementsAsync(batch));
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

        // GET: api/Sync/TillPayRequests?terminalId=1 — supplier payments this till may pay now (waiting, for it or any
        // till), the whole list every download (U032)
        [AllowAnonymous]
        [HttpGet("TillPayRequests")]
        public async Task<IActionResult> TillPayRequests([FromQuery] int terminalId, [FromServices] ItemApi.Data.AppDbContext db)
        {
            try
            {
                return Ok(await db.GetTillPayRequestsForSyncAsync(terminalId));
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

        // POST: api/Sync/TillPayRequests { terminalId, rows: [{ requestId, moveId, zNo, amount, cashierId, paidAt }] } — the
        // paid outs made for requests: each is booked once as a PAYMENT on the supplier ledger (a resend is skipped)
        // → { received }
        [AllowAnonymous]
        [HttpPost("TillPayRequests")]
        public async Task<IActionResult> TillPayRequestsPaid([FromBody] SyncTillPayPaidBatch batch, [FromServices] ItemApi.Data.AppDbContext db)
        {
            if (batch == null || batch.TerminalId <= 0)
                return BadRequest(new { message = "TerminalId is required." });
            try
            {
                return Ok(new SyncTillPayPaidResult { Received = batch.Rows.Count == 0 ? 0 : await db.TillPayRequestsPaidAsync(batch.TerminalId, batch.Rows) });
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

        // POST: api/Sync/TillLog — void lines (taken off a bill before payment) and cash drawer openings of a till.
        // A resend is skipped. → { voids, drawer }
        [AllowAnonymous]
        [HttpPost("TillLog")]
        public async Task<IActionResult> TillLog([FromBody] SyncTillLogBatch batch)
        {
            if (batch == null || batch.TerminalId <= 0)
                return BadRequest(new { message = "TerminalId is required." });

            try
            {
                return Ok(await _repository.UploadTillLogAsync(batch));
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

        // POST: api/Sync/AbandonedBills — bills a till found still open after a restart (power cut, crash), with their
        // lines. A resend updates how the bill ended. → { bills }
        [AllowAnonymous]
        [HttpPost("AbandonedBills")]
        public async Task<IActionResult> AbandonedBills([FromBody] SyncAbandonedBatch batch)
        {
            if (batch == null || batch.TerminalId <= 0)
                return BadRequest(new { message = "TerminalId is required." });

            try
            {
                return Ok(await _repository.UploadAbandonedBillsAsync(batch));
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
                // dated by the day end (ZDay), whatever date the till gave it - a Z opened the night before and
                // balanced the next night belongs to the next day
                var tillDate = z.BusinessDate.Date;
                if (z.ClosedAt is DateTime closedAt)
                    z.BusinessDate = ZDay.FromDayEnd(closedAt, z.OpenedAt);
                var result = await _repository.SubmitZReportAsync(z);
                UpdateTakingsSheetLater(z.BusinessDate.Date);
                if (tillDate != z.BusinessDate.Date)
                    UpdateTakingsSheetLater(tillDate, clearIfNone: true);   // the till's date may have this Z on the sheet
                return Ok(result);
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

        // A Z report arrived: the day's Avg_Cash (cash to bank of every Z: the Cash Management slip scanned at its day
        // end (U055), else counted cash - opening cash, else cash sales + paid in - paid out) and Card (card sales) of
        // all tills go to the cheque Google
        // sheet. In the background with its own scope: the till never waits for Google, and a sheet failure (no row
        // for the day, no credential, Google down) never fails the Z - only logged.
        // clearIfNone: a Z moved off this day (dated by its day end) - write 0 when no Z is left on it
        private void UpdateTakingsSheetLater(DateTime day, bool clearIfNone = false)
        {
            _ = Task.Run(async () =>
            {
                try
                {
                    await WriteTakingsSheetAsync(day, clearIfNone);
                }
                catch (Exception ex)
                {
                    Log.Error($"Takings sheet {day:yyyy-MM-dd} not updated: {ex.Message}");
                }
            });
        }

        // the day's row of the cheque sheet from the Zs dated that day; returns what was done
        private async Task<string> WriteTakingsSheetAsync(DateTime day, bool clearIfNone)
        {
            using var scope = _scopes.CreateScope();
            var sp = scope.ServiceProvider;
            var db = sp.GetRequiredService<ItemApi.Data.AppDbContext>();
            var locationId = sp.GetRequiredService<Microsoft.Extensions.Options.IOptions<AppSettings>>().Value.LocationId;
            var t = await db.GetDayTakingsAsync(day, locationId);
            if (t.ZCount == 0 && !clearIfNone)
                return "no Z - not changed";
            bool done = await sp.GetRequiredService<ItemApi.Service.IGoogleSheetService>()
                .UpdateDayTakingsAsync(day, t.BankCash, t.Card);
            var what = $"Avg_Cash {t.BankCash:N2} ({t.SlipZCount} of {t.ZCount} Z from a cash slip, {t.CountedZCount} counted on the till), Card {t.Card:N2}";
            if (done)
                Log.Information($"Takings sheet {day:yyyy-MM-dd}: {what}");
            else
                Log.Warning($"Takings sheet: no row for {day:yyyy-MM-dd} (month block / day not in the sheet)");
            return done ? what : "no row for this day in the sheet";
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
