using ItemApi.Data;
using ItemApi.Interface;
using Serilog;

namespace ItemApi.Repositories
{
    public class SystemRepository : ISystemRepository
    {
        private readonly AppDbContext _context;

        public SystemRepository(AppDbContext context)
        {
            _context = context;
        }

        public async Task<string> GenerateNextGrnNoAsync(string locaCode)
        {
            try
            {
                return await _context.GenerateNextGrnNoAsync(locaCode);
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex.Message}");
                throw;
            }
        }

        public async Task<string> UpdateNextGrnNoAsync(string locaCode)
        {
            try
            {
                return await _context.UpdateNextGrnNoAsync(locaCode);
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex.Message}");
                throw;
            }
        }
    }
}
