using ItemApi.Models;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Serilog;

namespace ItemApi.Data
{
    public class PosCountedStockContext : DbContext
    {

        public PosCountedStockContext(DbContextOptions<PosCountedStockContext> options) : base(options) { }

        public DbSet<PosCountedStock> PosCountedStock { get; set; }

        protected override void OnModelCreating(ModelBuilder modelBuilder)
        {
            modelBuilder.Entity<PosCountedStock>().ToTable("z_tb_PosCountedStock");
            base.OnModelCreating(modelBuilder);
        }

        public async Task<double> GetSumQtyAsync(string itemCode)
        {
            //insert try catch block
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

        //implement delete method
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

        //implement delete all the table data in the database table
        public async Task DeleteAllPosCountedStock()
        {
            try
            {
                //generate try catch block here
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
