using ItemApi.Models;
using Microsoft.EntityFrameworkCore;

namespace ItemApi.Data
{
    // Sub-categories (z_tb_SubCategory) — consolidated from the former SubCategoryContext.
    public partial class AppDbContext
    {
        public DbSet<SubCategory> SubCategories { get; set; }

        partial void ConfigureSubCategory(ModelBuilder modelBuilder)
        {
            modelBuilder.Entity<SubCategory>().ToTable("z_tb_SubCategory");

            modelBuilder.Entity<SubCategory>()
                .HasIndex(s => s.SubCatCode)
                .IsUnique();

            modelBuilder.Entity<SubCategory>()
                .HasIndex(s => s.CatId);
        }
    }
}
