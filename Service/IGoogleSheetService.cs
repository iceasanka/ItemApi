using ItemApi.Models;

namespace ItemApi.Service
{
    public interface IGoogleSheetService
    {
        Task InsertOrUpdateChequeAsync(ChequeCreate cheque);

        Task MarkChequeAsDebitedAsync(ChequeCreate cheque);

        // the day's row of the cheque sheet: Avg_Cash (C) = cash to bank, Card (D) = card sales. false = no row for that day.
        Task<bool> UpdateDayTakingsAsync(DateTime date, decimal cash, decimal card);
    }

}
