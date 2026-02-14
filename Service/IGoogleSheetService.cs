using ItemApi.Models;

namespace ItemApi.Service
{
    public interface IGoogleSheetService
    {
        Task InsertOrUpdateChequeAsync(ChequeCreate cheque);
    }

}
