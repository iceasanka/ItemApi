using ItemApi.Models;
using Microsoft.EntityFrameworkCore;
using Serilog;

namespace ItemApi.Data
{
    // System counters (z_tb_System) — consolidated from the former SystemContext.
    public partial class AppDbContext
    {
        public DbSet<ItemApi.Models.System> Systems { get; set; }

        partial void ConfigureSystem(ModelBuilder modelBuilder)
        {
            modelBuilder.Entity<ItemApi.Models.System>().ToTable("z_tb_System");
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

        // Takes the next GRN number for a new GRN and moves PNO on, in one statement (two tabs / browsers saving at once
        // get different numbers). A number already on a GRN (e.g. a page that saved with the number it showed) is skipped.
        // GRN Scan (z_sp_GrnScanMakeDraft) and the mobile GRN take theirs the same way.
        public async Task<string> TakeNextGrnNoAsync(string locaCode)
        {
            var result = await Database.SqlQueryRaw<string>(@"
                DECLARE @No INT, @GrnNo VARCHAR(20), @Tries INT = 0;
                WHILE 1 = 1
                BEGIN
                    SET @No = NULL;
                    UPDATE dbo.z_tb_System SET @No = PNO, PNO = PNO + 1 WHERE LocaId = {0};
                    IF @No IS NULL RAISERROR(N'%s', 16, 1, N'GRN counter (z_tb_System.PNO) not found.');
                    SET @GrnNo = 'GRN' + RIGHT('00000000' + CAST(@No AS VARCHAR(10)), 8);
                    SET @Tries = @Tries + 1;
                    IF @Tries >= 1000 OR (NOT EXISTS (SELECT 1 FROM dbo.z_tb_TempPurchaseSummary WHERE GrnNo = @GrnNo)
                                     AND NOT EXISTS (SELECT 1 FROM dbo.z_tb_TempPurchase WHERE GrnNo = @GrnNo)) BREAK;
                END
                SELECT @GrnNo AS Value;", locaCode).ToListAsync();
            return result.First();
        }

        public async Task<string> GenerateNextPrnNoAsync(string locaCode)
        {
            try
            {
                var result = await Database.SqlQueryRaw<int>(
                    "SELECT PRNO FROM z_tb_System WHERE LocaId = {0}",
                    locaCode).ToListAsync();

                int nextNo = result.FirstOrDefault();

                return $"PRN{nextNo:D8}"; // → PRN00000001
            }
            catch (Exception ex)
            {
                Log.Error($"Error generating PRN No: {ex.Message}");
                throw;
            }
        }

        public async Task<string> UpdateNextPrnNoAsync(string locaCode)
        {
            try
            {
                // Increment PRNO atomically - row lock ensures thread safety
                await Database.ExecuteSqlRawAsync(
                    "UPDATE z_tb_System SET PRNO = PRNO + 1 WHERE LocaId = {0}",
                    locaCode);

                var result = await Database.SqlQueryRaw<int>(
                    "SELECT PRNO FROM z_tb_System WHERE LocaId = {0}",
                    locaCode).ToListAsync();

                int nextNo = result.FirstOrDefault();

                return $"PRN{nextNo:D8}"; // → PRN00000001
            }
            catch (Exception ex)
            {
                Log.Error($"Error generating PRN No: {ex.Message}");
                throw;
            }
        }
    }
}
