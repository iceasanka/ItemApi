using ItemApi.Data;
using ItemApi.Interface;
using ItemApi.Models;
using Microsoft.EntityFrameworkCore;

namespace ItemApi.Repositories
{
    public class UnitRepository : IUnitRepository
    {
        private readonly AppDbContext _context;

        public UnitRepository(AppDbContext context)
        {
            _context = context;
        }

        public async Task<List<Unit>> GetAllUnitsAsync()
        {
            return await _context.Units.ToListAsync();
        }
    }
}
