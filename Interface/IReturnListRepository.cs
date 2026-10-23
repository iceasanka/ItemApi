using ItemApi.Models;

namespace ItemApi.Interface
{
    public interface IReturnListRepository
    {
        Task<List<ReturnListRow>> GetListAsync(int? suppId, int? status, int days);
        Task<ReturnListRow?> AddAsync(ReturnListAddRequest request);
        Task UpdateAsync(int returnId, ReturnListUpdateRequest request);
        Task<int> SetStatusAsync(List<int> ids, int status, string? userId);
        Task<int> DeleteAsync(List<int> ids);
        Task<ReturnListPrnResult> ToPrnAsync(ReturnListProcessRequest request);
        Task<List<ReturnListRow>> GetByIdsAsync(List<int> ids, int? status);
    }
}
