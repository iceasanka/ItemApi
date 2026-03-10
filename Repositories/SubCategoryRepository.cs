using ItemApi.Data;
using ItemApi.Interface;
using ItemApi.Models;

namespace ItemApi.Repositories
{
    public class SubCategoryRepository : ISubCategoryRepository
    {
        private readonly SubCategoryContext _context;

        public SubCategoryRepository(SubCategoryContext context)
        {
            _context = context;
        }

        public async Task<List<SubCategory>> GetAllAsync()
        {
            return await _context.GetAllAsync();
        }

        public async Task<SubCategory?> GetByIdAsync(int id)
        {
            return await _context.GetByIdAsync(id);
        }

        public async Task<List<SubCategory>> GetByCodeAsync(string code)
        {
            return await _context.GetByCodeAsync(code);
        }

        public async Task<List<SubCategory>> GetByCatIdAsync(int catId)
        {
            return await _context.GetByCatIdAsync(catId);
        }

        public async Task AddAsync(SubCategory subCategory)
        {
            await _context.AddSubCategoryAsync(subCategory);
        }

        public async Task UpdateAsync(SubCategory subCategory)
        {
            await _context.UpdateSubCategoryAsync(subCategory);
        }

        public async Task DeleteAsync(int id)
        {
            await _context.DeleteSubCategoryAsync(id);
        }
    }
}
