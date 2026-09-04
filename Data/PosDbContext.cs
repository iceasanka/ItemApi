using ItemApi.Models;
using Microsoft.EntityFrameworkCore;
using Serilog;

namespace ItemApi.Data
{
    /// <summary>
    /// DbContext for the entities that live on the separate "PosConnection" database.
    /// Currently just PosStock (tbStock) — kept as its own context/connection rather than folded
    /// into AppDbContext because it genuinely points at a different database.
    /// </summary>
    public class PosDbContext : DbContext
    {
        public PosDbContext(DbContextOptions<PosDbContext> options) : base(options) { }

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
