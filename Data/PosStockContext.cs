using ItemApi.Models;
using Microsoft.EntityFrameworkCore;
using Serilog;

namespace ItemApi.Data
{
    public class PosStockContext : DbContext
    {
        public PosStockContext(DbContextOptions<PosStockContext> options) : base(options) { }

        public DbSet<PosStock> PosStock { get; set; }

        protected override void OnModelCreating(ModelBuilder modelBuilder)
        {
            modelBuilder.Entity<PosStock>().ToTable("tbStock");
            base.OnModelCreating(modelBuilder);
        }


        internal async Task<decimal> GetSumQtyAsync(string itemCode)
        {
            try
            {
                decimal sumQty = (decimal)await PosStock.Where(stock => stock.ItemCode == itemCode).SumAsync(stock => stock.Qty);
                return sumQty;
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex}");
                throw ex;
            }
        }
    }
}
