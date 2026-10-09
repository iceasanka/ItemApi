using ItemApi.Models;

namespace ItemApi.Interface
{
    public interface ICustomerRepository
    {
        Task<List<Customer>> SearchAsync(string? text, int top);
        Task<Customer?> GetByIdAsync(int customerId);
        Task<Customer> AddAsync(Customer customer);
        Task<Customer> UpdateAsync(int customerId, Customer customer);
        Task DeleteAsync(int customerId, int? userId);
    }
}
