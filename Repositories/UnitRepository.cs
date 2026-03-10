using ItemApi.Data;
using ItemApi.Interface;
using ItemApi.Models;
using Microsoft.EntityFrameworkCore;

namespace ItemApi.Repositories
{
    public class UnitRepository : IUnitRepository
    {
        private readonly UnitContext _context;

        public UnitRepository(UnitContext context)
        {
            _context = context;
        }

        public async Task<List<Unit>> GetAllUnitsAsync()
        {
            return await _context.Units.ToListAsync();
        }
    }
}
