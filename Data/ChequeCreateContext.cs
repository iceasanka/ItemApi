using ItemApi.Models;
using Microsoft.EntityFrameworkCore;

namespace ItemApi.Data
{
    public class ChequeCreateContext : DbContext
    {
        public ChequeCreateContext(DbContextOptions<ChequeCreateContext> options) : base(options) { }

        public DbSet<ChequeCreate> Cheques { get; set; }

        protected override void OnModelCreating(ModelBuilder modelBuilder)
        {
            modelBuilder.Entity<ChequeCreate>().ToTable("z_tb_WrittenCheque");
            base.OnModelCreating(modelBuilder);
        }
    }
}
