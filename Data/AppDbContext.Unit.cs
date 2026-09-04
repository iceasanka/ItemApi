using ItemApi.Models;
using Microsoft.EntityFrameworkCore;

namespace ItemApi.Data
{
    // Units (z_tb_Unit) — consolidated from the former UnitContext.
    public partial class AppDbContext
    {
        public DbSet<Unit> Units { get; set; }

        partial void ConfigureUnit(ModelBuilder modelBuilder)
        {
            modelBuilder.Entity<Unit>().ToTable("z_tb_Unit").HasKey(u => u.UnitId);

            modelBuilder.Entity<Unit>().HasIndex(u => u.UnitCode).IsUnique();
        }
    }
}
