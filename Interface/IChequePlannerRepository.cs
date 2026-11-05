using ItemApi.Models;

namespace ItemApi.Interface
{
    public interface IChequePlannerRepository
    {
        Task<ChequePlan> GetPlanAsync(DateTime from, DateTime to);
        Task SaveConfigAsync(ChequePlanConfigSave config);
        Task SaveDayAsync(DateTime date, ChequePlanDaySave day);
        Task<int> AddChequeAsync(ChequePlanChequeSave cheque);
        Task UpdateChequeAsync(int planId, ChequePlanChequeSave cheque);
        Task RemoveChequeAsync(int planId);
    }
}
