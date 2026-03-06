using ItemApi.Models;
using Microsoft.EntityFrameworkCore;

namespace ItemApi.Data
{
    public class CategoryContext : DbContext
    {

        public CategoryContext(DbContextOptions<CategoryContext> options)
          : base(options)
        {
        }

        public DbSet<Category> DbCategory { get; set; }

        protected override void OnModelCreating(ModelBuilder modelBuilder)
        {
            modelBuilder.Entity<Category>().ToTable("z_tb_Category");
        }

        // Add a new category
        public async Task AddCategoryAsync(Category category)
        {
             DbCategory.Add(category);
            await SaveChangesAsync();
        }

        // Update an existing category
        public async Task UpdateCategoryAsync(Category category)
        {
            try
            {
                 DbCategory.Update(category);
                await SaveChangesAsync();
            }
            catch (Exception ex)
            {

                throw ex;
            }
           
        }

        // Delete a category by Id
        public async Task DeleteCategoryAsync(int id)
        {
            var entity = await  DbCategory.FindAsync(id);
            if (entity != null)
            {
                 DbCategory.Remove(entity);
                await SaveChangesAsync();
            }
        }

        // Get a category by Id
        public async Task<Category> GetCategoryByIdAsync(int id)
        {
            return await  DbCategory.FindAsync(id);
        }   

        // Search categories by name
        public async Task<List<Category>> SearchCategoryByNameAsync(string name)
        {
            return await  DbCategory
                .Where(c => c.CatName.Contains(name))
                .ToListAsync();
        }

        // Get all categories
        public async Task<List<Category>> GetAllCategoriesAsync()
        {
            return await  DbCategory.ToListAsync();
        }

      
    }
}
