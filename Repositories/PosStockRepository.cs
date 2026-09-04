using ItemApi.Data;
using ItemApi.Interface;
using ItemApi.Models;

namespace ItemApi.Repositories
{
    public class PosStockRepository : IPosStockRepository
    {
        private readonly PosDbContext _context;

        public PosStockRepository(PosDbContext context)
        {
            _context = context;
        }

        public async Task<decimal> GetSumQtyAsync(string itemCode)
        {
            return await _context.GetSumQtyAsync(itemCode);
        }


    }
}
