using ItemApi.Models;
using System.Collections.Generic;
using System.Threading.Tasks;

namespace ItemApi.Repositories
{
    public interface IFileLocationRepository
    {
        Task<List<FileLocation>> GetAllAsync();
        Task<FileLocation?> GetByIdAsync(int id);
        Task AddAsync(FileLocation fileLocation);
        Task UpdateAsync(FileLocation fileLocation);
        Task DeleteAsync(int id);
        Task<List<FileLocation>> SearchFileByNameAsync(string suppName);
    }
}
