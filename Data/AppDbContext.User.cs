using System.Data;
using ItemApi.Models;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;

namespace ItemApi.Data
{
    // Users and roles (z_tb_User, z_tb_Role — DBScript/07_BackOffice_Users.sql).
    public partial class AppDbContext
    {
        public DbSet<AppUser> AppUsers { get; set; }
        public DbSet<AppRole> AppRoles { get; set; }

        partial void ConfigureUser(ModelBuilder modelBuilder)
        {
            modelBuilder.Entity<AppUser>().ToTable("z_tb_User");
            modelBuilder.Entity<AppRole>().ToTable("z_tb_Role");
        }

        public async Task<List<SyncCashier>> GetCashiersForSyncAsync(int terminalId, DateTime? since)
        {
            return await Database.SqlQueryRaw<SyncCashier>(
                "EXEC dbo.z_sp_GetCashiersForSync @TerminalId = @TerminalId, @Since = @Since",
                new SqlParameter("@TerminalId", terminalId),
                new SqlParameter("@Since", SqlDbType.DateTime) { Value = (object?)since ?? DBNull.Value }).ToListAsync();
        }
    }
}
