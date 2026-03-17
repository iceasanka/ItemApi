using ItemApi.Models;
using Microsoft.EntityFrameworkCore;
using Serilog;

namespace ItemApi.Data
{
    public class SystemContext : DbContext
    {
        public SystemContext(DbContextOptions<SystemContext> options) : base(options) { }

        public DbSet<ItemApi.Models.System> Systems { get; set; }

        protected override void OnModelCreating(ModelBuilder modelBuilder)
        {
            modelBuilder.Entity<ItemApi.Models.System>().ToTable("z_tb_System");
            base.OnModelCreating(modelBuilder);
        }

        public async Task<string> GenerateNextGrnNoAsync(string locaCode)
        {
            try
            {
                // Increment PNO atomically - row lock ensures thread safety
                //await Database.ExecuteSqlRawAsync(
                //    "UPDATE z_tb_System SET PNO = PNO + 1 WHERE LocaId = {0}",
                //    locaCode);

                var result = await Database.SqlQueryRaw<int>(
                    "SELECT PNO FROM z_tb_System WHERE LocaId = {0}",
                    locaCode).ToListAsync();

                int nextNo = result.FirstOrDefault();

                return $"GRN{nextNo:D8}"; // → GRN00000001
            }
            catch (Exception ex)
            {
                Log.Error($"Error generating GRN No: {ex.Message}");
                throw;
            }
        }


        public async Task<string> UpdateNextGrnNoAsync(string locaCode)
        {
            try
            {
                // Increment PNO atomically - row lock ensures thread safety
                await Database.ExecuteSqlRawAsync(
                    "UPDATE z_tb_System SET PNO = PNO + 1 WHERE LocaId = {0}",
                    locaCode);

                var result = await Database.SqlQueryRaw<int>(
                    "SELECT PNO FROM z_tb_System WHERE LocaId = {0}",
                    locaCode).ToListAsync();

                int nextNo = result.FirstOrDefault();

                return $"GRN{nextNo:D8}"; // → GRN00000001
            }
            catch (Exception ex)
            {
                Log.Error($"Error generating GRN No: {ex.Message}");
                throw;
            }
        }
    }
}
