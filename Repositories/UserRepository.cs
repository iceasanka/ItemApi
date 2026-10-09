using System.Text.RegularExpressions;
using ItemApi.Common;
using ItemApi.Data;
using ItemApi.Interface;
using ItemApi.Models;
using Microsoft.EntityFrameworkCore;

namespace ItemApi.Repositories
{
    // Users and sign-in (z_tb_User). Docs/StockSystem.md §6.12.
    //   - LoginName: 3–20 letters/digits/. _ -; never changes (it is the CashierId on till bills).
    //   - Password: at least 6 characters for Admin / Back office, 4 for cashiers (they type it at the till many times a day).
    //   - 5 wrong passwords → locked 5 minutes. An admin's password reset unlocks.
    //   - Never deleted, only disabled. There is always at least one active admin.
    //   - UpdatedDate moves on every change the tills need (name, role, status, password) — they download by it.
    //     Sign-in bookkeeping (last login, wrong-password count, lock) does not move it.
    public class UserRepository : IUserRepository
    {
        public const int MaxFailedLogins = 5;
        public static readonly TimeSpan LockTime = TimeSpan.FromMinutes(5);

        private static readonly Regex LoginNamePattern = new("^[A-Za-z0-9._-]{3,20}$");
        private const string WrongLogin = "Wrong user name or password.";

        private readonly AppDbContext _context;

        public UserRepository(AppDbContext context)
        {
            _context = context;
        }

        public async Task<bool> SetupNeededAsync()
        {
            return !await _context.AppUsers.AnyAsync(u => u.RoleId == UserRoles.Admin && u.Status == 1);
        }

        // The first admin, from the sign-in page of a new system. Refused once an active admin exists.
        public async Task<AppUser> SetupAsync(SetupRequest request)
        {
            if (!await SetupNeededAsync())
                throw new UserException("Setup is already done — sign in instead.");
            var user = await AddAsync(request.LoginName, request.UserName, UserRoles.Admin, request.Password, null, null, null);
            user.LastLoginAt = DateTime.Now;
            await _context.SaveChangesAsync();
            return user;
        }

        // Back office sign-in (tills check passwords themselves, offline)
        public async Task<AppUser> LoginAsync(LoginRequest request)
        {
            var login = (request.LoginName ?? "").Trim();
            var password = request.Password ?? "";
            if (login.Length == 0 || password.Length == 0)
                throw new LoginFailedException("Type your user name and password.");

            var user = await FindByLoginAsync(login);
            if (user == null)
            {
                // same work as a real check, so the answer time doesn't tell which user names exist
                PasswordHasher.Verify(password, DummyHash);
                throw new LoginFailedException(WrongLogin);
            }

            var now = DateTime.Now;
            if (user.LockedUntil > now)
                throw new LoginFailedException($"Too many wrong passwords. Try again after {user.LockedUntil:HH:mm}.");

            if (!PasswordHasher.Verify(password, user.PasswordHash))
            {
                user.FailedLogins++;
                if (user.FailedLogins >= MaxFailedLogins)
                {
                    user.FailedLogins = 0;
                    user.LockedUntil = now + LockTime;
                    await _context.SaveChangesAsync();
                    throw new LoginFailedException($"Too many wrong passwords. Try again after {user.LockedUntil:HH:mm}.");
                }
                await _context.SaveChangesAsync();
                throw new LoginFailedException(WrongLogin);
            }

            if (user.Status != 1)
                throw new LoginFailedException("This user is disabled. Ask an admin.");
            if (!UserRoles.CanUseBackOffice(user.RoleId))
                throw new LoginFailedException("Cashiers sign in at the till, not the back office.");

            user.FailedLogins = 0;
            user.LockedUntil = null;
            user.LastLoginAt = now;
            await _context.SaveChangesAsync();
            return user;
        }

        public async Task<AppUser?> GetActiveAsync(int userId)
        {
            return await _context.AppUsers.AsNoTracking().FirstOrDefaultAsync(u => u.UserId == userId && u.Status == 1);
        }

        public async Task ChangePasswordAsync(int userId, ChangePasswordRequest request)
        {
            var user = await _context.AppUsers.FirstOrDefaultAsync(u => u.UserId == userId && u.Status == 1)
                       ?? throw new KeyNotFoundException();
            if (!PasswordHasher.Verify(request.CurrentPassword ?? "", user.PasswordHash))
                throw new UserException("Current password is wrong.");
            var newPassword = request.NewPassword ?? "";
            CheckPassword(newPassword, user.RoleId ?? 0);
            if (newPassword == request.CurrentPassword)
                throw new UserException("The new password must be different.");

            user.PasswordHash = PasswordHasher.Hash(newPassword);
            user.UpdatedDate = DateTime.Now;
            user.UpdatedBy = userId;
            await _context.SaveChangesAsync();
        }

        // ─── Users page (admin) ───

        public async Task<List<UserInfo>> ListAsync(string? text, bool includeDisabled)
        {
            var q = _context.AppUsers.AsNoTracking().Where(u => u.LoginName != null);
            if (!includeDisabled) q = q.Where(u => u.Status == 1);
            var t = (text ?? "").Trim();
            if (t.Length > 0)
                q = q.Where(u => u.LoginName!.Contains(t) || (u.UserName != null && u.UserName.Contains(t)));
            var users = await q.OrderBy(u => u.UserName).ThenBy(u => u.LoginName).ToListAsync();
            return users.Select(UserInfo.From).ToList();
        }

        public async Task<UserInfo?> GetAsync(int userId)
        {
            var user = await _context.AppUsers.AsNoTracking().FirstOrDefaultAsync(u => u.UserId == userId && u.LoginName != null);
            return user == null ? null : UserInfo.From(user);
        }

        public async Task<UserInfo> CreateAsync(UserCreateRequest r, int byUserId)
        {
            var user = await AddAsync(r.LoginName, r.UserName, r.RoleId, r.Password, r.Phone, r.Email, byUserId);
            return UserInfo.From(user);
        }

        public async Task<UserInfo> UpdateAsync(int userId, UserUpdateRequest r, int byUserId)
        {
            var user = await _context.AppUsers.FirstOrDefaultAsync(u => u.UserId == userId && u.LoginName != null)
                       ?? throw new KeyNotFoundException();
            if (!UserRoles.IsValid(r.RoleId)) throw new UserException("Choose a role: Admin, Back office or Cashier.");
            if (r.Status is not (0 or 1)) throw new UserException("Status must be 1 (active) or 0 (disabled).");
            var name = CheckName(r.UserName);
            CheckContact(r.Phone, r.Email);

            var stillAdmin = r.RoleId == UserRoles.Admin && r.Status == 1;
            if (user.RoleId == UserRoles.Admin && user.Status == 1 && !stillAdmin)
            {
                if (userId == byUserId)
                    throw new UserException("You can't disable yourself or take away your own Admin role.");
                if (!await _context.AppUsers.AnyAsync(u => u.UserId != userId && u.RoleId == UserRoles.Admin && u.Status == 1))
                    throw new UserException("This is the last active admin. Make another admin first.");
            }

            user.UserName = name;
            user.RoleId = r.RoleId;
            user.Status = r.Status;
            user.Phone = Blank(r.Phone);
            user.Email = Blank(r.Email);
            user.UpdatedDate = DateTime.Now;
            user.UpdatedBy = byUserId;
            await _context.SaveChangesAsync();
            return UserInfo.From(user);
        }

        public async Task ResetPasswordAsync(int userId, ResetPasswordRequest request, int byUserId)
        {
            var user = await _context.AppUsers.FirstOrDefaultAsync(u => u.UserId == userId && u.LoginName != null)
                       ?? throw new KeyNotFoundException();
            var password = request.NewPassword ?? "";
            CheckPassword(password, user.RoleId ?? 0);
            user.PasswordHash = PasswordHasher.Hash(password);
            user.FailedLogins = 0;
            user.LockedUntil = null;
            user.UpdatedDate = DateTime.Now;
            user.UpdatedBy = byUserId;
            await _context.SaveChangesAsync();
        }

        // ─── Rules ───

        private async Task<AppUser> AddAsync(string? loginName, string? userName, int roleId, string? password,
                                             string? phone, string? email, int? byUserId)
        {
            var login = (loginName ?? "").Trim();
            if (!LoginNamePattern.IsMatch(login))
                throw new UserException("User name: 3 to 20 letters, digits, dot, dash or underscore (no spaces).");
            if (!UserRoles.IsValid(roleId)) throw new UserException("Choose a role: Admin, Back office or Cashier.");
            var name = CheckName(userName);
            CheckPassword(password ?? "", roleId);
            CheckContact(phone, email);
            if (await FindByLoginAsync(login) != null || await _context.AppUsers.AnyAsync(u => u.UserCode == login))
                throw new UserException($"User name '{login}' is already taken.");

            var now = DateTime.Now;
            var user = new AppUser
            {
                UserCode = login,
                LoginName = login,
                UserName = name,
                PasswordHash = PasswordHasher.Hash(password!),
                RoleId = roleId,
                Status = 1,
                Phone = Blank(phone),
                Email = Blank(email),
                CreatedDate = now,
                CreatedBy = byUserId,
                UpdatedDate = now,
                UpdatedBy = byUserId
            };
            _context.AppUsers.Add(user);
            await _context.SaveChangesAsync();
            return user;
        }

        private async Task<AppUser?> FindByLoginAsync(string login)
        {
            var lower = login.ToLower();
            return await _context.AppUsers.FirstOrDefaultAsync(u => u.LoginName != null && u.LoginName.ToLower() == lower);
        }

        private static string CheckName(string? userName)
        {
            var name = (userName ?? "").Trim();
            if (name.Length == 0) throw new UserException("Name is required.");
            if (name.Length > 100) throw new UserException("Name: max 100 characters.");
            return name;
        }

        private static void CheckPassword(string password, int roleId)
        {
            var min = UserRoles.CanUseBackOffice(roleId) ? 6 : 4;
            if (password.Length < min) throw new UserException($"Password must be at least {min} characters.");
            if (password.Length > 100) throw new UserException("Password: max 100 characters.");
        }

        private static void CheckContact(string? phone, string? email)
        {
            if (phone?.Trim().Length > 20) throw new UserException("Phone: max 20 characters.");
            var e = email?.Trim();
            if (e?.Length > 150) throw new UserException("Email: max 150 characters.");
            if (!string.IsNullOrEmpty(e) && !e.Contains('@')) throw new UserException("Email is not valid.");
        }

        private static string? Blank(string? s) => string.IsNullOrWhiteSpace(s) ? null : s.Trim();

        // a real hash of a random password, checked when the user name doesn't exist
        private static readonly string DummyHash = PasswordHasher.Hash(Guid.NewGuid().ToString());
    }
}
