using ItemApi.Data;
using ItemApi.Interface;
using ItemApi.Models;
using Microsoft.Extensions.Options;

namespace ItemApi.Repositories
{
    // Mobile GRN drafts (U017)
    public class MobileGrnRepository : IMobileGrnRepository
    {
        private readonly AppDbContext _context;
        // Hard-coded in appsettings.json (AppSettings:LocationId) until the user table is implemented
        private readonly int _locationId;

        public MobileGrnRepository(AppDbContext context, IOptions<AppSettings> appSettings)
        {
            _context = context;
            _locationId = appSettings.Value.LocationId;
        }

        public Task<List<MobileGrnLine>> GetAsync(int suppId) => _context.GetMobileGrnAsync(suppId, _locationId);

        public Task<MobileGrnLineRef> AddLineAsync(MobileGrnAddRequest request) =>
            _context.AddMobileGrnLineAsync(request, _locationId);

        public Task<MobileGrnLineRef> UpdateLineAsync(int idx, MobileGrnUpdateRequest request) =>
            _context.UpdateMobileGrnLineAsync(idx, request);

        public Task<MobileGrnDeleteResult> DeleteLineAsync(int idx) => _context.DeleteMobileGrnLineAsync(idx);
    }
}
