using ItemApi.Data;
using ItemApi.Models;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;
using Serilog;

namespace ItemApi.Controllers
{
    // Customer wallet (DBScript/37_BackOffice_Wallet.sql). Its own function (setting Wallet.Enabled), separate from
    // loyalty points; uses the loyalty members. On a bill: payment PayType 9, + paid from the wallet, - change kept.
    // Wallet money is never paid out as cash: there is no pay back or hand change route.
    // Till routes (TillService, no user token - like api/Loyalty): Bill, Cancel, Bills.
    // Back office routes (Loyalty page, Wallet tab): Members, Members/{id}/Txns, Settings.
    // The member lookup of the till is api/Loyalty/Member (it carries the wallet too).
    [Route("api/[controller]")]
    [ApiController]
    public class WalletController : ControllerBase
    {
        private readonly AppDbContext _db;

        public WalletController(AppDbContext db)
        {
            _db = db;
        }

        // ─── Till ────────────────────────────────────────────────────────────────

        // POST: api/Wallet/Bill { walletKey, phone, amount, terminalId, cashierId } — the wallet part of a bill, done now
        // (before the till saves the bill). amount + = paid from the wallet, - = change kept. The same key again changes
        // nothing. → the member: walletBalance (after), balanceBefore
        [AllowAnonymous]
        [HttpPost("Bill")]
        public Task<IActionResult> Bill([FromBody] WalletBillRequest req) => Run(async () =>
        {
            var p = LoyaltyPhone.Normalize(req?.Phone);
            if (req == null || p == null || req.WalletKey == Guid.Empty || req.TerminalId <= 0)
                return BadRequest(new { message = "Phone, wallet key and terminal are required." });
            if (req.Amount == 0 || Math.Abs(req.Amount) > 1_000_000 || decimal.Round(req.Amount, 2) != req.Amount)
                return BadRequest(new { message = "Enter the wallet amount (rupees and cents)." });
            if (req.CashierId?.Length > 20)
                req.CashierId = req.CashierId[..20];
            if (!await _db.HasWalletAsync())
                return BadRequest(new { message = "The back office has no customer wallet yet (run U059)." });
            return Ok(await _db.WalletBillAsync(req, p));
        });

        // POST: api/Wallet/Cancel { walletKey } — the bill was not saved: the wallet part goes back → { returned }
        [AllowAnonymous]
        [HttpPost("Cancel")]
        public Task<IActionResult> Cancel([FromBody] WalletCancelRequest req) => Run(async () =>
        {
            if (req == null || req.WalletKey == Guid.Empty)
                return BadRequest(new { message = "Wallet key is required." });
            return Ok(new { returned = await _db.CancelWalletAsync(req.WalletKey) });
        });

        // POST: api/Wallet/Bills { terminalId, bills: [{ invoiceNo, walletKey, status }] } — links the wallet part to
        // its bill (a voided bill gives it back) → { invoiceNos }
        [AllowAnonymous]
        [HttpPost("Bills")]
        public Task<IActionResult> Bills([FromBody] WalletBillBatch batch) => Run(async () =>
        {
            if (batch == null || batch.TerminalId <= 0)
                return BadRequest(new { message = "TerminalId is required." });
            if (batch.Bills.Count == 0)
                return Ok(new { invoiceNos = new List<string>() });
            if (batch.Bills.Count > 200 || batch.Bills.Any(b => string.IsNullOrWhiteSpace(b.InvoiceNo) || b.InvoiceNo.Length > 30
                                                                || b.WalletKey == Guid.Empty))
                return BadRequest(new { message = "Send 1 to 200 bills, each with its InvoiceNo and wallet key." });
            return Ok(new { invoiceNos = await _db.SyncWalletBillsAsync(batch.TerminalId, batch.Bills) });
        });

        // ─── Back office (Loyalty page, Wallet tab) ──────────────────────────────

        // GET: api/Wallet/Settings
        [HttpGet("Settings")]
        public Task<IActionResult> Settings() => Run(async () => Ok(await _db.GetWalletSettingsAsync()));

        // GET: api/Wallet/Members?text=077&all=false&top=200 → { members, heldForCustomers, owedByCustomers, wallets }
        [HttpGet("Members")]
        public Task<IActionResult> Members([FromQuery] string? text, [FromQuery] bool all = false, [FromQuery] int top = 200) => Run(async () =>
        {
            if (top is < 1 or > 2000)
                return BadRequest(new { message = "Top must be between 1 and 2000." });
            if (!await _db.HasWalletAsync())
                return Ok(new WalletMemberList());
            return Ok(await _db.GetWalletMembersAsync(text?.Trim(), !all, top));
        });

        // GET: api/Wallet/Members/5/Txns — the member's wallet history, newest first
        [HttpGet("Members/{memberId:int}/Txns")]
        public Task<IActionResult> Txns(int memberId) => Run(async () =>
            Ok(await _db.HasWalletAsync() ? await _db.GetWalletTxnsAsync(memberId) : new List<WalletTxn>()));

        private static async Task<IActionResult> Run(Func<Task<IActionResult>> action)
        {
            try
            {
                return await action();
            }
            catch (SqlException ex) when (ex.Number >= 50000)
            {
                return new BadRequestObjectResult(new { message = ex.Message });
            }
            catch (Exception ex)
            {
                Log.Error($"Wallet: {ex}");
                return new ObjectResult(new { message = "Internal Server Error", error = ex.Message }) { StatusCode = 500 };
            }
        }
    }
}
