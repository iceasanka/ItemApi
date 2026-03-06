using ItemApi.Data;
using ItemApi.Models;

namespace ItemApi.Repositories
{
    public class CategoryRepository : ICategoryRepository
    {

        private readonly CategoryContext _context;

        public CategoryRepository(CategoryContext context)
        {
            _context = context;
        }

        public async Task<List<Category>> GetAllAsync()
        {
            return await _context.GetAllCategoriesAsync();
        }


        public async Task<Category?> GetByIdAsync(int id)
        {
            return await _context.GetCategoryByIdAsync(id);
        }

        public async Task AddAsync(Category category)
        {
            await _context.AddCategoryAsync(category);
        }

        public async Task UpdateAsync(Category category)
        {
            await _context.UpdateCategoryAsync(category);
        }

        public async Task DeleteAsync(int id)
        {
            await _context.DeleteCategoryAsync(id);
        }


        public async Task<List<Category>> SearchCategoryByNameAsync(string name)
        {
            return await _context.SearchCategoryByNameAsync(name);
        }


    }
}
