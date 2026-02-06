using ItemApi.Models;

namespace ItemApi.Interface
{
    public interface IChequeCreateRepository
    {
        Task AddChequeAsync(ChequeCreate cheque);

        Task<IEnumerable<ChequeCreate>> SearchChequesByDateRangeAsync(
            DateTime fromDate,
            DateTime toDate
        );

        Task<IEnumerable<ChequeCreate>> GetChequesByPayeeIdAsync(int payeeId);

        Task<ChequeCreate> GetByIdAsync(int id);
        Task UpdateChequeAsync(ChequeCreate cheque);
        Task DeleteChequeAsync(int id);

    }
}
