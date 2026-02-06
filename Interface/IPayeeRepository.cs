using ItemApi.Models;

namespace ItemApi.Interface
{
    public interface IPayeeRepository
    {
        Task<List<Payee>> GetPayeesByNameAsync(string name);
        Task<IEnumerable<Payee>> GetAllPayeesAsync();
        Task AddPayeeAsync(Payee payee);
        Task UpdatePayeeAsync(Payee payee);
        Task DeletePayeeAsync(int id);

        Task<Payee> GetById(int id);
       
    }
}
