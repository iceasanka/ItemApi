using ItemApi.Interface;
using ItemApi.Models;
using ItemApi.Service;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;
using Serilog;

namespace ItemApi.Controllers
{
    // Settings page — admins only, ALWAYS (also while Auth:Enforce is false). Docs/StockSystem.md §6.28.
    // General settings for the whole system, and per-user settings (a user's own value instead of the general one).
    // Till settings reach the tills on their next download (≤ 5 min / Reload) — api/Sync/Settings.
    [Route("api/[controller]")]
    [ApiController]
    [Authorize(Roles = UserRoles.AdminName)]
    public class SettingsController : ControllerBase
    {
        private readonly ISettingRepository _settings;

        public SettingsController(ISettingRepository settings)
        {
            _settings = settings;
        }

        // GET: api/Settings — every setting with its general value
        [HttpGet]
        public async Task<IActionResult> List()
        {
            return await Run(async () => Ok(await _settings.ListAsync()));
        }

        // PUT: api/Settings/Till.BillDiscSkipItemDisc { value } — value null = back to the default
        [HttpPut("{key}")]
        public async Task<IActionResult> Set(string key, [FromBody] SettingValueRequest request)
        {
            return await Run(async () =>
            {
                await _settings.SetAsync(key, request?.Value, Me);
                return Ok(new { message = "Setting saved." });
            });
        }

        // GET: api/Settings/Users — the per-user settings and each user's own values
        [HttpGet("Users")]
        public async Task<IActionResult> Users()
        {
            return await Run(async () => Ok(await _settings.ListUsersAsync()));
        }

        // PUT: api/Settings/User/5/Till.ProfitView { value } — value null = the user gets the general value again
        [HttpPut("User/{userId:int}/{key}")]
        public async Task<IActionResult> SetUser(int userId, string key, [FromBody] SettingValueRequest request)
        {
            return await Run(async () =>
            {
                await _settings.SetUserAsync(userId, key, request?.Value, Me);
                return Ok(new { message = "Setting saved." });
            });
        }

        private int Me => AuthTokenService.UserId(User);

        private async Task<IActionResult> Run(Func<Task<IActionResult>> action)
        {
            try
            {
                return await action();
            }
            catch (SqlException ex) when (ex.Number >= 50000)
            {
                return BadRequest(new { message = ex.Message });
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex}");
                return StatusCode(500, new { message = "Internal Server Error", error = ex.Message });
            }
        }
    }
}
