using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using ItemApi.Models;
using Microsoft.IdentityModel.Tokens;
using Serilog;

namespace ItemApi.Service
{
    // Sign-in tokens for the back office web app (JWT, sent as "Authorization: Bearer <token>").
    // Auth:JwtKey signs them — set a long random value on the server. Without it a new key is made at every start,
    // so a restart signs everyone out (fine for a test PC, not for the shop).
    public class AuthTokenService
    {
        public const string Issuer = "ItemApi";
        public const string RoleIdClaim = "roleId";

        private readonly SymmetricSecurityKey _key;
        private readonly int _hours;

        public AuthTokenService(SymmetricSecurityKey key, int hours)
        {
            _key = key;
            _hours = hours;
        }

        public static SymmetricSecurityKey LoadKey(IConfiguration config)
        {
            var configured = config["Auth:JwtKey"];
            if (!string.IsNullOrWhiteSpace(configured))
            {
                if (configured.Length < 32)
                    throw new InvalidOperationException("Auth:JwtKey must be at least 32 characters.");
                return new SymmetricSecurityKey(Encoding.UTF8.GetBytes(configured));
            }

            Log.Warning("Auth:JwtKey is not set — using a temporary key; everyone is signed out when the API restarts.");
            return new SymmetricSecurityKey(RandomNumberGenerator.GetBytes(64));
        }

        public static TokenValidationParameters Validation(SymmetricSecurityKey key) => new()
        {
            ValidateIssuer = true,
            ValidIssuer = Issuer,
            ValidateAudience = true,
            ValidAudience = Issuer,
            ValidateIssuerSigningKey = true,
            IssuerSigningKey = key,
            ValidateLifetime = true,
            ClockSkew = TimeSpan.FromMinutes(1),
            NameClaimType = ClaimTypes.Name,
            RoleClaimType = ClaimTypes.Role
        };

        public LoginResponse Issue(AppUser user)
        {
            var expires = DateTime.Now.AddHours(_hours);
            var claims = new[]
            {
                new Claim(ClaimTypes.NameIdentifier, user.UserId.ToString()),
                new Claim(ClaimTypes.Name, user.LoginName ?? ""),
                new Claim(ClaimTypes.Role, UserRoles.Name(user.RoleId)),
                new Claim(RoleIdClaim, (user.RoleId ?? 0).ToString())
            };
            var token = new JwtSecurityToken(Issuer, Issuer, claims, DateTime.Now, expires,
                new SigningCredentials(_key, SecurityAlgorithms.HmacSha256));
            return new LoginResponse
            {
                Token = new JwtSecurityTokenHandler().WriteToken(token),
                ExpiresAt = expires,
                User = UserInfo.From(user)
            };
        }

        // the signed-in user's id from the token (0 = none)
        public static int UserId(ClaimsPrincipal principal) =>
            int.TryParse(principal.FindFirstValue(ClaimTypes.NameIdentifier), out var id) ? id : 0;
    }
}
