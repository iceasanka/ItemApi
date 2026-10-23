using ItemApi.Data;
using ItemApi.Interface;
using ItemApi.Models;

namespace ItemApi.Repositories
{
    // Return Items list on the new system (U016)
    public class ReturnListRepository : IReturnListRepository
    {
        private readonly AppDbContext _context;

        public ReturnListRepository(AppDbContext context)
        {
            _context = context;
        }

        public Task<List<ReturnListRow>> GetListAsync(int? suppId, int? status, int days) =>
            _context.GetReturnListAsync(suppId, status, days);

        // the saved row as the list shows it
        public async Task<ReturnListRow?> AddAsync(ReturnListAddRequest request)
        {
            var id = await _context.AddReturnListItemAsync(request);
            var rows = await _context.GetReturnListAsync(request.SuppId, 1, 0);
            return rows.FirstOrDefault(r => r.ReturnId == id);
        }

        public Task UpdateAsync(int returnId, ReturnListUpdateRequest request) =>
            _context.UpdateReturnListItemAsync(returnId, request);

        public Task<int> SetStatusAsync(List<int> ids, int status, string? userId) =>
            _context.SetReturnListStatusAsync(ids, status, userId);

        public Task<int> DeleteAsync(List<int> ids) => _context.DeleteReturnListItemsAsync(ids);

        public Task<ReturnListPrnResult> ToPrnAsync(ReturnListProcessRequest request) => _context.ReturnListToPrnAsync(request);

        // open rows (status null) or PRN made (3) with these ids — for printing
        public async Task<List<ReturnListRow>> GetByIdsAsync(List<int> ids, int? status)
        {
            var set = ids.ToHashSet();
            var rows = await _context.GetReturnListAsync(null, status, 3650);
            return rows.Where(r => set.Contains(r.ReturnId)).ToList();
        }
    }
}
