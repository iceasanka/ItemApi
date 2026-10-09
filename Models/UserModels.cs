using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace ItemApi.Models
{
    // Users and sign-in (DBScript/07_BackOffice_Users.sql, Docs/StockSystem.md §6.12).

    [Table("z_tb_User")]
    public class AppUser
    {
        [Key]
        [DatabaseGenerated(DatabaseGeneratedOption.Identity)]
        public int UserId { get; set; }
        // = LoginName (the column is unique, so it is always filled)
        public string? UserCode { get; set; }
        // display name
        public string? UserName { get; set; }
        // what the user types to sign in; also the CashierId on till bills, so it never changes
        public string? LoginName { get; set; }
        public string? PasswordHash { get; set; }
        public string? Email { get; set; }
        public string? Phone { get; set; }
        public int? RoleId { get; set; }
        // 1 active, 0 disabled
        public int? Status { get; set; }
        public DateTime? CreatedDate { get; set; }
        public int? CreatedBy { get; set; }
        public DateTime? UpdatedDate { get; set; }
        public int? UpdatedBy { get; set; }
        public DateTime? LastLoginAt { get; set; }
        public int FailedLogins { get; set; }
        public DateTime? LockedUntil { get; set; }
    }

    [Table("z_tb_Role")]
    public class AppRole
    {
        [Key]
        public int RoleId { get; set; }
        public string RoleName { get; set; } = "";
        public int Status { get; set; }
    }

    // z_tb_Role.RoleId; the names are also the role claims in the token
    public static class UserRoles
    {
        public const int Admin = 1;
        public const int BackOffice = 2;
        public const int Cashier = 3;

        public const string AdminName = "Admin";
        public const string BackOfficeName = "BackOffice";
        public const string CashierName = "Cashier";

        public static string Name(int? roleId) => roleId switch
        {
            Admin => AdminName,
            BackOffice => BackOfficeName,
            Cashier => CashierName,
            _ => ""
        };

        public static string Label(int? roleId) => roleId switch
        {
            Admin => "Admin",
            BackOffice => "Back office",
            Cashier => "Cashier",
            _ => ""
        };

        public static bool IsValid(int roleId) => roleId is Admin or BackOffice or Cashier;
        public static bool CanUseBackOffice(int? roleId) => roleId is Admin or BackOffice;
        public static bool CanUseTill(int? roleId) => roleId is Admin or Cashier;
    }

    // ─── Requests ───

    public class LoginRequest
    {
        public string? LoginName { get; set; }
        public string? Password { get; set; }
    }

    public class SetupRequest
    {
        public string? LoginName { get; set; }
        public string? UserName { get; set; }
        public string? Password { get; set; }
    }

    public class ChangePasswordRequest
    {
        public string? CurrentPassword { get; set; }
        public string? NewPassword { get; set; }
    }

    public class UserCreateRequest
    {
        public string? LoginName { get; set; }
        public string? UserName { get; set; }
        public int RoleId { get; set; }
        public string? Password { get; set; }
        public string? Phone { get; set; }
        public string? Email { get; set; }
    }

    // LoginName can't change (it is on the bills)
    public class UserUpdateRequest
    {
        public string? UserName { get; set; }
        public int RoleId { get; set; }
        public int Status { get; set; } = 1;
        public string? Phone { get; set; }
        public string? Email { get; set; }
    }

    public class ResetPasswordRequest
    {
        public string? NewPassword { get; set; }
    }

    // ─── Responses ───

    // never carries the password hash
    public class UserInfo
    {
        public int UserId { get; set; }
        public string LoginName { get; set; } = "";
        public string UserName { get; set; } = "";
        public int RoleId { get; set; }
        public string RoleName { get; set; } = "";
        public int Status { get; set; }
        public string? Phone { get; set; }
        public string? Email { get; set; }
        public DateTime? LastLoginAt { get; set; }
        public bool IsLocked { get; set; }
        public DateTime? CreatedDate { get; set; }

        public static UserInfo From(AppUser u) => new()
        {
            UserId = u.UserId,
            LoginName = u.LoginName ?? "",
            UserName = u.UserName ?? u.LoginName ?? "",
            RoleId = u.RoleId ?? 0,
            RoleName = UserRoles.Label(u.RoleId),
            Status = u.Status ?? 0,
            Phone = u.Phone,
            Email = u.Email,
            LastLoginAt = u.LastLoginAt,
            IsLocked = u.LockedUntil > DateTime.Now,
            CreatedDate = u.CreatedDate
        };
    }

    public class LoginResponse
    {
        public string Token { get; set; } = "";
        public DateTime ExpiresAt { get; set; }
        public UserInfo User { get; set; } = new();
    }

    public class AuthStatus
    {
        // no active admin yet → the sign-in page shows "Create the first admin"
        public bool SetupNeeded { get; set; }
        // Auth:Enforce — false = the API still answers without a token (while the web pages are being switched over)
        public bool Enforced { get; set; }
    }

    // api/Sync/Cashiers → till zf_tb_Cashier
    public class SyncCashier
    {
        public int UserId { get; set; }
        public string LoginName { get; set; } = "";
        public string? UserName { get; set; }
        public int? RoleId { get; set; }
        public bool CanUseTill { get; set; }
        public string? PasswordHash { get; set; }
        public DateTime? UpdatedDate { get; set; }
    }

    // Business errors (bad password, last admin, ...) → HTTP 400 { message }
    public class UserException : Exception
    {
        public UserException(string message) : base(message) { }
    }

    // Wrong name / password, locked, disabled → HTTP 401 { message }
    public class LoginFailedException : Exception
    {
        public LoginFailedException(string message) : base(message) { }
    }
}
