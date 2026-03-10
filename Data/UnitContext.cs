using ItemApi.Models;
using Microsoft.EntityFrameworkCore;

namespace ItemApi.Data
{
    public class UnitContext : DbContext
    {
        public UnitContext(DbContextOptions<UnitContext> options) : base(options) { }

        public DbSet<Unit> Units { get; set; }

        protected override void OnModelCreating(ModelBuilder modelBuilder)
        {
            modelBuilder.Entity<Unit>().ToTable("z_tb_Unit") .HasKey(u => u.UnitId);

            modelBuilder.Entity<Unit>().HasIndex(u => u.UnitCode).IsUnique();

            base.OnModelCreating(modelBuilder);
        }
    }
}
