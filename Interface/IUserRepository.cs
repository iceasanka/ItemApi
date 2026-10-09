using ItemApi.Models;

namespace ItemApi.Interface
{
    public interface IUserRepository
    {
        Task<bool> SetupNeededAsync();
        Task<AppUser> SetupAsync(SetupRequest request);
        Task<AppUser> LoginAsync(LoginRequest request);
        Task<AppUser?> GetActiveAsync(int userId);
        Task ChangePasswordAsync(int userId, ChangePasswordRequest request);

        Task<List<UserInfo>> ListAsync(string? text, bool includeDisabled);
        Task<UserInfo?> GetAsync(int userId);
        Task<UserInfo> CreateAsync(UserCreateRequest request, int byUserId);
        Task<UserInfo> UpdateAsync(int userId, UserUpdateRequest request, int byUserId);
        Task ResetPasswordAsync(int userId, ResetPasswordRequest request, int byUserId);
    }
}
