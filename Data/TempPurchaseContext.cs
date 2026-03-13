using ItemApi.Models;
using Microsoft.EntityFrameworkCore;

namespace ItemApi.Data
{
    public class TempPurchaseContext : DbContext
    {
        public TempPurchaseContext(DbContextOptions<TempPurchaseContext> options) : base(options) { }

        public DbSet<TempPurchase> TempPurchases { get; set; }

        protected override void OnModelCreating(ModelBuilder modelBuilder)
        {
            modelBuilder.Entity<TempPurchase>().ToTable("z_tb_TempPurchase");
            base.OnModelCreating(modelBuilder);
        }
    }
}
