using ItemApi.Models;
using Microsoft.EntityFrameworkCore;
using Serilog;

namespace ItemApi.Data
{
    // Counted POS stock (z_tb_PosCountedStock) — consolidated from the former PosCountedStockContext.
    // NOTE: despite the "Pos" name this lives on the DefaultConnection database, not PosConnection —
    // see Data/PosDbContext.cs for the entity that actually lives on PosConnection (PosStock).
    public partial class AppDbContext
    {
        public DbSet<PosCountedStock> PosCountedStock { get; set; }

        partial void ConfigurePosCountedStock(ModelBuilder modelBuilder)
        {
            modelBuilder.Entity<PosCountedStock>().ToTable("z_tb_PosCountedStock");
        }

        public async Task<double> GetSumQtyAsync(string itemCode)
        {
            try
            {
                double sumQty = await PosCountedStock.Where(stock => stock.ItemCode == itemCode).SumAsync(stock => (double?)stock.Qty) ?? 0;
                return sumQty;
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex}");
                throw ex;
            }
        }

        public async Task AddPosCountedStock(PosCountedStock posCountedStock)
        {
            try
            {
                var existing = await PosCountedStock.FirstOrDefaultAsync(p => p.ItemCode == posCountedStock.ItemCode);

                if (existing != null)
                {
                    existing.Qty += posCountedStock.Qty;
                }
                else
                {
                    await PosCountedStock.AddAsync(posCountedStock);
                }
                await SaveChangesAsync();
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex}");
                throw ex;
            }
        }

        public async Task DeletePosCountedStock(string itemCode)
        {
            try
            {
                var existing = await PosCountedStock.FirstOrDefaultAsync(p => p.ItemCode == itemCode);

                if (existing != null)
                {
                    PosCountedStock.Remove(existing);
                }
                await SaveChangesAsync();
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex}");
                throw ex;
            }
        }

        public async Task DeleteAllPosCountedStock()
        {
            try
            {
                PosCountedStock.RemoveRange(PosCountedStock);
                await SaveChangesAsync();
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex}");
                throw ex;
            }
        }
    }
}
