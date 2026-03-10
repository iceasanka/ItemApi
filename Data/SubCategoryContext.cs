using ItemApi.Models;
using Microsoft.EntityFrameworkCore;

namespace ItemApi.Data
{
    public class SubCategoryContext : DbContext
    {
        public SubCategoryContext(DbContextOptions<SubCategoryContext> options) : base(options) { }

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

        public async Task AddSubCategoryAsync(SubCategory subCategory)
        {
            SubCategories.Add(subCategory);
            await SaveChangesAsync();
        }

        public async Task UpdateSubCategoryAsync(SubCategory subCategory)
        {
            SubCategories.Update(subCategory);
            await SaveChangesAsync();
        }

        public async Task DeleteSubCategoryAsync(int id)
        {
            var entity = await SubCategories.FindAsync(id);
            if (entity != null)
            {
                SubCategories.Remove(entity);
                await SaveChangesAsync();
            }
        }

        public async Task<List<SubCategory>> GetAllAsync()
        {
            return await SubCategories.ToListAsync();
        }

        public async Task<List<SubCategory>> GetByCatIdAsync(int catId)
        {
            return await SubCategories
                .Where(s => s.CatId == catId)
                .ToListAsync();
        }

        public async Task<SubCategory?> GetByIdAsync(int id)
        {
            return await SubCategories.FindAsync(id);
        }

        public async Task<List<SubCategory>> GetByCodeAsync(string code)
        {
            return await SubCategories
                .Where(s => s.SubCatCode.Contains(code) || s.SubCatName.Contains(code))
                .ToListAsync();
        }
    }
}
