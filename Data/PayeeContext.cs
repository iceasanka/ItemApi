using Microsoft.EntityFrameworkCore;

namespace ItemApi.Data
{
    public class PayeeContext : DbContext
    {
        public PayeeContext(DbContextOptions<PayeeContext> options) : base(options) { }

        public DbSet<Models.Payee> Payees { get; set; }

        protected override void OnModelCreating(ModelBuilder modelBuilder)
        {
            modelBuilder.Entity<Models.Payee>().ToTable("z_tb_Payee");
            base.OnModelCreating(modelBuilder);
        }
    }
}
