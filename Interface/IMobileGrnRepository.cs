using ItemApi.Models;

namespace ItemApi.Interface
{
    public interface IMobileGrnRepository
    {
        Task<List<MobileGrnLine>> GetAsync(int suppId);
        Task<MobileGrnLineRef> AddLineAsync(MobileGrnAddRequest request);
        Task<MobileGrnLineRef> UpdateLineAsync(int idx, MobileGrnUpdateRequest request);
        Task<MobileGrnDeleteResult> DeleteLineAsync(int idx);
    }
}
