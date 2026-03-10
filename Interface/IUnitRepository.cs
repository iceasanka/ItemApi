using ItemApi.Models;

namespace ItemApi.Interface
{
    public interface IUnitRepository
    {
        Task<List<Unit>> GetAllUnitsAsync();
    }
}
