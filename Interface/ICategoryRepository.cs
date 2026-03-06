using ItemApi.Models;
using System.Collections.Generic;
using System.Threading.Tasks;

namespace ItemApi.Repositories
{
    public interface ICategoryRepository
    {
        Task<List<Category>> GetAllAsync();
        Task<Category?> GetByIdAsync(int id);
        Task AddAsync(Category category);
        Task UpdateAsync(Category category);
        Task DeleteAsync(int id);
        Task<List<Category>> SearchCategoryByNameAsync(string name);
    }
}
