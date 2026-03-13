using ItemApi.Models;
using Microsoft.EntityFrameworkCore;

namespace ItemApi.Data
{
    public class TempPurchaseSummaryContext : DbContext
    {
        public TempPurchaseSummaryContext(DbContextOptions<TempPurchaseSummaryContext> options) : base(options) { }

        public DbSet<TempPurchaseSummary> TempPurchaseSummaries { get; set; }

        protected override void OnModelCreating(ModelBuilder modelBuilder)
        {
            modelBuilder.Entity<TempPurchaseSummary>().ToTable("z_tb_TempPurchaseSummary");
            base.OnModelCreating(modelBuilder);
        }
    }
}
