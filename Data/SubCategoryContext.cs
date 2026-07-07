using ItemApi.Models;
using Microsoft.EntityFrameworkCore;

namespace ItemApi.Data
{
    public class SubCategoryContext : DbContext
    {
        public SubCategoryContext(DbContextOptions<SubCategoryContext> options)
            : base(options)
        {
        }

        public DbSet<SubCategory> SubCategories { get; set; }

        protected override void OnModelCreating(ModelBuilder modelBuilder)
        {
            modelBuilder.Entity<SubCategory>().ToTable("z_tb_SubCategory");

            modelBuilder.Entity<SubCategory>()
                .HasIndex(s => s.SubCatCode)
                .IsUnique();

            modelBuilder.Entity<SubCategory>()
                .HasIndex(s => s.CatId);

            base.OnModelCreating(modelBuilder);
        }
    }
}