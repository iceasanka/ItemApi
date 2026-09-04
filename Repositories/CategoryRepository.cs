using ItemApi.Data;
using ItemApi.Models;
using Microsoft.EntityFrameworkCore;

namespace ItemApi.Repositories
{
    public class CategoryRepository : ICategoryRepository
    {
        private readonly AppDbContext _context;

        public CategoryRepository(AppDbContext context)
        {
            _context = context;
        }

        // Get all categories
        public async Task<List<Category>> GetAllAsync()
        {
            return await _context.Categories.ToListAsync();
        }

        // Get category by Id
        public async Task<Category?> GetByIdAsync(int id)
        {
            return await _context.Categories.FindAsync(id);
        }

        // Add category
        public async Task AddAsync(Category category)
        {
            await _context.Categories.AddAsync(category);
            await _context.SaveChangesAsync();
        }

        // Update category
        public async Task UpdateAsync(Category category)
        {
            _context.Categories.Update(category);
            await _context.SaveChangesAsync();
        }

        // Delete category
        public async Task DeleteAsync(int id)
        {
            var entity = await _context.Categories.FindAsync(id);

            if (entity == null)
                return;

            _context.Categories.Remove(entity);
            await _context.SaveChangesAsync();
        }

        // Search by name
        public async Task<List<Category>> SearchCategoryByNameAsync(string name)
        {
            return await _context.Categories
                .Where(c => c.CatName.Contains(name))
                .ToListAsync();
        }
    }
}