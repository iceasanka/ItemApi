using ItemApi.Data;
using ItemApi.Interface;
using ItemApi.Models;

namespace ItemApi.Repositories
{
    public class PosStockRepository : IPosStockRepository
    {
        private readonly PosStockContext _context;

        public PosStockRepository(PosStockContext context)
        {
            _context = context;
        }

        public async Task<decimal> GetSumQtyAsync(string itemCode)
        {
            return await _context.GetSumQtyAsync(itemCode);
        }


    }
}
