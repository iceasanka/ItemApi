using ItemApi.Interface;
using ItemApi.Models;
using ItemApi.Service;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Serilog;

namespace ItemApi.Controllers
{
    // Users page — admins only, ALWAYS (also while Auth:Enforce is false). Docs/StockSystem.md §6.12.
    // Users are never deleted, only disabled; cashier changes reach the tills on their next download (≤ 5 min / Reload).
    [Route("api/[controller]")]
    [ApiController]
    [Authorize(Roles = UserRoles.AdminName)]
    public class UsersController : ControllerBase
    {
        private readonly IUserRepository _users;

        public UsersController(IUserRepository users)
        {
            _users = users;
        }

        // GET: api/Users?text=&includeDisabled=false
        [HttpGet]
        public async Task<IActionResult> List([FromQuery] string? text, [FromQuery] bool includeDisabled = false)
        {
            return await Run(async () => Ok(await _users.ListAsync(text, includeDisabled)));
        }

        // GET: api/Users/5
        [HttpGet("{userId:int}")]
        public async Task<IActionResult> Get(int userId)
        {
            return await Run(async () =>
            {
                var user = await _users.GetAsync(userId);
                return user == null ? NotFound(new { message = "User not found." }) : Ok(user);
            });
        }

        // POST: api/Users { loginName, userName, roleId (1 Admin, 2 Back office, 3 Cashier), password, phone, email }
        [HttpPost]
        public async Task<IActionResult> Create([FromBody] UserCreateRequest request)
        {
            if (request == null) return BadRequest(new { message = "User is required." });
            return await Run(async () =>
            {
                var user = await _users.CreateAsync(request, Me);
                return Ok(new { message = $"User {user.LoginName} saved.", data = user });
            });
        }

        // PUT: api/Users/5 { userName, roleId, status (1 active / 0 disabled), phone, email } — the user name can't change
        [HttpPut("{userId:int}")]
        public async Task<IActionResult> Update(int userId, [FromBody] UserUpdateRequest request)
        {
            if (request == null) return BadRequest(new { message = "User is required." });
            return await Run(async () =>
            {
                var user = await _users.UpdateAsync(userId, request, Me);
                return Ok(new { message = $"User {user.LoginName} saved.", data = user });
            });
        }

        // POST: api/Users/5/ResetPassword { newPassword } — also unlocks after too many wrong passwords
        [HttpPost("{userId:int}/ResetPassword")]
        public async Task<IActionResult> ResetPassword(int userId, [FromBody] ResetPasswordRequest request)
        {
            if (request == null) return BadRequest(new { message = "New password is required." });
            return await Run(async () =>
            {
                await _users.ResetPasswordAsync(userId, request, Me);
                return Ok(new { message = "Password reset." });
            });
        }

        private int Me => AuthTokenService.UserId(User);

        private async Task<IActionResult> Run(Func<Task<IActionResult>> action)
        {
            try
            {
                return await action();
            }
            catch (UserException ex)
            {
                return BadRequest(new { message = ex.Message });
            }
            catch (KeyNotFoundException)
            {
                return NotFound(new { message = "User not found." });
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex}");
                return StatusCode(500, new { message = "Internal Server Error", error = ex.Message });
            }
        }
    }
}
