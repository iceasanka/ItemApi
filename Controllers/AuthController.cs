using ItemApi.Interface;
using ItemApi.Models;
using ItemApi.Service;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Serilog;

namespace ItemApi.Controllers
{
    // Back office sign-in. The web app sends the token as "Authorization: Bearer <token>" on every call.
    // Cashiers sign in at the till (TillService), not here. Docs/StockSystem.md §6.12.
    [Route("api/[controller]")]
    [ApiController]
    public class AuthController : ControllerBase
    {
        private readonly IUserRepository _users;
        private readonly AuthTokenService _tokens;
        private readonly bool _enforced;

        public AuthController(IUserRepository users, AuthTokenService tokens, IConfiguration config)
        {
            _users = users;
            _tokens = tokens;
            _enforced = config.GetValue("Auth:Enforce", false);
        }

        // GET: api/Auth/Status → { setupNeeded, enforced } — the sign-in page asks first
        [AllowAnonymous]
        [HttpGet("Status")]
        public async Task<IActionResult> Status()
        {
            return await Run(async () => Ok(new AuthStatus { SetupNeeded = await _users.SetupNeededAsync(), Enforced = _enforced }));
        }

        // POST: api/Auth/Setup { loginName, userName, password } — the first admin; only while there is no active admin.
        // Signs the new admin in.
        [AllowAnonymous]
        [HttpPost("Setup")]
        public async Task<IActionResult> Setup([FromBody] SetupRequest request)
        {
            if (request == null) return BadRequest(new { message = "User name and password are required." });
            return await Run(async () => Ok(_tokens.Issue(await _users.SetupAsync(request))));
        }

        // POST: api/Auth/Login { loginName, password } → { token, expiresAt, user }; 401 { message } when refused
        [AllowAnonymous]
        [HttpPost("Login")]
        public async Task<IActionResult> Login([FromBody] LoginRequest request)
        {
            if (request == null) return BadRequest(new { message = "User name and password are required." });
            return await Run(async () => Ok(_tokens.Issue(await _users.LoginAsync(request))));
        }

        // GET: api/Auth/Me — who the token belongs to (401 when the token is missing, expired or the user was disabled)
        [Authorize]
        [HttpGet("Me")]
        public async Task<IActionResult> Me()
        {
            return await Run(async () =>
            {
                var user = await _users.GetActiveAsync(AuthTokenService.UserId(User));
                return user == null ? Unauthorized(new { message = "Sign in again." }) : Ok(UserInfo.From(user));
            });
        }

        // POST: api/Auth/ChangePassword { currentPassword, newPassword } — the signed-in user's own password
        [Authorize]
        [HttpPost("ChangePassword")]
        public async Task<IActionResult> ChangePassword([FromBody] ChangePasswordRequest request)
        {
            if (request == null) return BadRequest(new { message = "Passwords are required." });
            return await Run(async () =>
            {
                await _users.ChangePasswordAsync(AuthTokenService.UserId(User), request);
                return Ok(new { message = "Password changed." });
            });
        }

        private async Task<IActionResult> Run(Func<Task<IActionResult>> action)
        {
            try
            {
                return await action();
            }
            catch (LoginFailedException ex)
            {
                return Unauthorized(new { message = ex.Message });
            }
            catch (UserException ex)
            {
                return BadRequest(new { message = ex.Message });
            }
            catch (KeyNotFoundException)
            {
                return Unauthorized(new { message = "Sign in again." });
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex}");
                return StatusCode(500, new { message = "Internal Server Error", error = ex.Message });
            }
        }
    }
}
