using ItemApi.Data;
using ItemApi.Interface;
using ItemApi.Models;

namespace ItemApi.Repositories
{
    public class PosCountedStockRepository : IPosCountedStockRepository
    {
        private readonly AppDbContext _context;

        public PosCountedStockRepository(AppDbContext context)
        {
            _context = context;
        }

        public async Task<double> GetSumQtyAsync(string itemCode)
        {
            return await _context.GetSumQtyAsync(itemCode);
        }
        // AddPosCountedStock method is missing
        public async Task AddPosCountedStock(PosCountedStock posCountedStock)
        {
            await _context.AddPosCountedStock(posCountedStock);
        }

        //implement delete method
        public async Task DeletePosCountedStock(string itemCode)
        {
            await _context.DeletePosCountedStock(itemCode);
        }

        //implement delete all the table data in the database table
        public async Task DeleteAllPosCountedStock()
        {
            await _context.DeleteAllPosCountedStock();
        }
    }
}
