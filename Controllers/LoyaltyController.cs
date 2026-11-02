using ItemApi.Common;
using ItemApi.Data;
using ItemApi.Models;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;
using Serilog;

namespace ItemApi.Controllers
{
    // Customer loyalty points (DBScript/27_BackOffice_Loyalty.sql, Docs/StockSystem.md 6.33).
    // Till routes (TillService, no user token - like api/Sync): Member, Redeem, RedeemCancel, Bills.
    // Back office routes (Loyalty page): Members, Members/{id}/Txns, PUT Members/{id}, Members/{id}/Adjust (admin), Settings.
    // The settings themselves are saved with api/Settings (admins) and reach the tills with api/Sync/Settings.
    [Route("api/[controller]")]
    [ApiController]
    public class LoyaltyController : ControllerBase
    {
        private readonly AppDbContext _db;

        public LoyaltyController(AppDbContext db)
        {
            _db = db;
        }

        // ─── Till ────────────────────────────────────────────────────────────────

        // GET: api/Loyalty/Member?phone=0771234567 → { found, member, settings }
        [AllowAnonymous]
        [HttpGet("Member")]
        public Task<IActionResult> Member([FromQuery] string? phone) => Run(async () =>
        {
            var p = LoyaltyPhone.Normalize(phone);
            if (p == null)
                return BadRequest(new { message = "Enter the phone number as 10 digits, e.g. 0771234567." });
            var member = await _db.GetLoyaltyMemberAsync(p);
            return Ok(new LoyaltyLookup { Found = member != null, Member = member, Settings = await _db.GetLoyaltySettingsAsync() });
        });

        // POST: api/Loyalty/Member { phone, name, terminalId, cashierId } — a new member from a till (Menu > Add loyalty
        // member), only while loyalty is on → the member
        [AllowAnonymous]
        [HttpPost("Member")]
        public Task<IActionResult> AddMemberFromTill([FromBody] LoyaltyAddMemberRequest req) => Run(async () =>
        {
            if (req == null || req.TerminalId is null or <= 0)
                return BadRequest(new { message = "TerminalId is required." });
            if (!(await _db.GetLoyaltySettingsAsync()).Enabled)
                return BadRequest(new { message = "Loyalty points are switched off on the back office." });
            return await AddMember(req, req.TerminalId, Cut(req.CashierId, 50));
        });

        // POST: api/Loyalty/Redeem { redeemKey, phone, points, terminalId, cashierId } — points taken off now, before the
        // till saves the bill. The same key again changes nothing. → the member after it
        [AllowAnonymous]
        [HttpPost("Redeem")]
        public Task<IActionResult> Redeem([FromBody] LoyaltyRedeemRequest req) => Run(async () =>
        {
            var p = LoyaltyPhone.Normalize(req?.Phone);
            if (req == null || p == null || req.RedeemKey == Guid.Empty || req.TerminalId <= 0)
                return BadRequest(new { message = "Phone, redeem key and terminal are required." });
            return Ok(await _db.RedeemLoyaltyAsync(req, p));
        });

        // POST: api/Loyalty/RedeemCancel { redeemKey } — the bill was not saved: the points go back → { returned }
        [AllowAnonymous]
        [HttpPost("RedeemCancel")]
        public Task<IActionResult> RedeemCancel([FromBody] LoyaltyRedeemCancelRequest req) => Run(async () =>
        {
            if (req == null || req.RedeemKey == Guid.Empty)
                return BadRequest(new { message = "Redeem key is required." });
            return Ok(new { returned = await _db.CancelLoyaltyRedeemAsync(req.RedeemKey) });
        });

        // POST: api/Loyalty/Bills { terminalId, bills } — bills with a member (earn, refund, redeem link) → { invoiceNos }
        [AllowAnonymous]
        [HttpPost("Bills")]
        public Task<IActionResult> Bills([FromBody] LoyaltyBillBatch batch) => Run(async () =>
        {
            if (batch == null || batch.TerminalId <= 0)
                return BadRequest(new { message = "TerminalId is required." });
            if (batch.Bills.Count == 0)
                return Ok(new { invoiceNos = new List<string>() });
            if (batch.Bills.Count > 200 || batch.Bills.Any(b => string.IsNullOrWhiteSpace(b.InvoiceNo) || b.InvoiceNo.Length > 30))
                return BadRequest(new { message = "Send 1 to 200 bills, each with its InvoiceNo." });
            // a phone the db would refuse can never be a member: sent as it is (skipped there)
            foreach (var b in batch.Bills)
                b.Phone = LoyaltyPhone.Normalize(b.Phone) ?? Cut(b.Phone?.Trim(), 15) ?? "";
            return Ok(new { invoiceNos = await _db.SyncLoyaltyBillsAsync(batch.TerminalId, batch.Bills) });
        });

        // ─── Back office (Loyalty page) ──────────────────────────────────────────

        // GET: api/Loyalty/Settings — the loyalty settings as numbers
        [HttpGet("Settings")]
        public Task<IActionResult> Settings() => Run(async () => Ok(await _db.GetLoyaltySettingsAsync()));

        // GET: api/Loyalty/Members?text=077&top=200 → { members, totalMembers, activeMembers, pointsOutstanding }
        [HttpGet("Members")]
        public Task<IActionResult> Members([FromQuery] string? text, [FromQuery] int top = 200) => Run(async () =>
        {
            if (top is < 1 or > 2000)
                return BadRequest(new { message = "Top must be between 1 and 2000." });
            return Ok(await _db.GetLoyaltyMembersAsync(text?.Trim(), top));
        });

        // POST: api/Loyalty/Members { phone, name } — a new member made on the Loyalty page (also while loyalty is off)
        [HttpPost("Members")]
        public Task<IActionResult> AddMemberFromBackOffice([FromBody] LoyaltyAddMemberRequest req) =>
            Run(() => AddMember(req, null, User.CurrentUserId()?.ToString()));

        // GET: api/Loyalty/Members/5/Txns — the member's points history, newest first
        [HttpGet("Members/{memberId:int}/Txns")]
        public Task<IActionResult> Txns(int memberId) => Run(async () => Ok(await _db.GetLoyaltyTxnsAsync(memberId)));

        // PUT: api/Loyalty/Members/5 { phone, name, status }
        [HttpPut("Members/{memberId:int}")]
        public Task<IActionResult> Update(int memberId, [FromBody] LoyaltyUpdateMemberRequest req) => Run(async () =>
        {
            var p = LoyaltyPhone.Normalize(req?.Phone);
            if (p == null)
                return BadRequest(new { message = "Enter the phone number as 10 digits, e.g. 0771234567." });
            var name = req!.Name?.Trim();
            if (string.IsNullOrEmpty(name) || name.Length > 100)
                return BadRequest(new { message = "Enter the member's name (max 100)." });
            await _db.UpdateLoyaltyMemberAsync(memberId, p, name, req.Status, User.CurrentUserId());
            return Ok(new { message = "Member saved." });
        });

        // POST: api/Loyalty/Members/5/Adjust { points, remark } — admins: points added (+) or taken off (-) by hand
        [Authorize(Roles = UserRoles.AdminName)]
        [HttpPost("Members/{memberId:int}/Adjust")]
        public Task<IActionResult> Adjust(int memberId, [FromBody] LoyaltyAdjustRequest req) => Run(async () =>
        {
            if (req == null || req.Points == 0)
                return BadRequest(new { message = "Enter the points to add (+) or take off (-)." });
            var points = await _db.AdjustLoyaltyAsync(memberId, req.Points, req.Remark?.Trim(), User.CurrentUserId());
            return Ok(new { message = "Points changed.", points });
        });

        private async Task<IActionResult> AddMember(LoyaltyAddMemberRequest? req, int? terminalId, string? createdBy)
        {
            var p = LoyaltyPhone.Normalize(req?.Phone);
            if (p == null)
                return BadRequest(new { message = "Enter the phone number as 10 digits, e.g. 0771234567." });
            var name = req!.Name?.Trim();
            if (string.IsNullOrEmpty(name) || name.Length > 100)
                return BadRequest(new { message = "Enter the member's name (max 100)." });
            return Ok(await _db.AddLoyaltyMemberAsync(p, name, terminalId, createdBy));
        }

        private static string? Cut(string? s, int max) => s == null ? null : s.Length > max ? s[..max] : s;

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
                Log.Error($"Loyalty: {ex}");
                return new ObjectResult(new { message = "Internal Server Error", error = ex.Message }) { StatusCode = 500 };
            }
        }
    }
}
