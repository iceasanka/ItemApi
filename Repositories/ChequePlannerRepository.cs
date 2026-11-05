using ItemApi.Data;
using ItemApi.Interface;
using ItemApi.Models;
using Microsoft.Extensions.Options;

namespace ItemApi.Repositories
{
    // Cheque planner: money in per day (the Zs once the tills have balanced, else the expected takings) and the cheques
    // going out (written + planned). The page works out the coming bank balance from these.
    public class ChequePlannerRepository : IChequePlannerRepository
    {
        private const int MaxDays = 400;
        private readonly AppDbContext _context;
        private readonly int _locationId;

        public ChequePlannerRepository(AppDbContext context, IOptions<AppSettings> appSettings)
        {
            _context = context;
            _locationId = appSettings.Value.LocationId;
        }

        public async Task<ChequePlan> GetPlanAsync(DateTime from, DateTime to)
        {
            from = from.Date; to = to.Date;
            if (to < from) throw new ChequePlanException("The To date is before the From date.");
            if ((to - from).TotalDays > MaxDays) throw new ChequePlanException($"Ask for {MaxDays} days or less.");

            var today = DateTime.Today;
            var config = await _context.GetChequePlanConfigAsync();
            var rows = await _context.GetChequePlanDaysAsync(from, to, _locationId);
            var overdueFrom = today.AddDays(-Math.Max(0, config.OverdueDays));
            var cheques = await _context.GetChequePlanChequesAsync(from, to, overdueFrom < from ? overdueFrom : from);

            return new ChequePlan
            {
                Today = today,
                From = from,
                To = to,
                Config = config,
                Cheques = cheques,
                Days = rows.Select(r =>
                {
                    bool actual = r.ZCount > 0;
                    var d = new ChequePlanDay
                    {
                        Date = r.PlanDate.Date,
                        Actual = actual,
                        ZCount = r.ZCount,
                        Cash = actual ? r.CashInHand : r.ExpectedCash ?? config.AvgCash,
                        Card = actual ? r.CardAmount : r.ExpectedCard ?? config.AvgCard,
                        Bank = actual ? r.BankAmount : 0,
                        CashSales = r.CashSales,
                        PaidIn = r.PaidIn,
                        PaidOut = r.PaidOut,
                        CardSettlement = r.CardSettlement,
                        ExpectedCash = r.ExpectedCash,
                        ExpectedCard = r.ExpectedCard,
                        Note = r.Note,
                    };
                    d.Total = d.Cash + d.Card + d.Bank;
                    return d;
                }).ToList(),
            };
        }

        public Task SaveConfigAsync(ChequePlanConfigSave c)
        {
            if (c.AvgCash < 0 || c.AvgCard < 0 || c.KeepMin < 0)
                throw new ChequePlanException("The average and the amount to keep cannot be negative.");
            if (c.OverdueDays < 0 || c.OverdueDays > 365)
                throw new ChequePlanException("Look back 0 to 365 days for cheques not debited.");
            return _context.SaveChequePlanConfigAsync(c);
        }

        public Task SaveDayAsync(DateTime date, ChequePlanDaySave d)
        {
            if (d.ExpectedCash < 0 || d.ExpectedCard < 0)
                throw new ChequePlanException("Expected takings cannot be negative.");
            if (d.Note?.Trim().Length > 200) throw new ChequePlanException("The note is longer than 200 letters.");
            return _context.SaveChequePlanDayAsync(date, d);
        }

        public Task<int> AddChequeAsync(ChequePlanChequeSave c)
        {
            Check(c);
            return _context.AddChequePlanChequeAsync(c);
        }

        public async Task UpdateChequeAsync(int planId, ChequePlanChequeSave c)
        {
            Check(c);
            if (await _context.UpdateChequePlanChequeAsync(planId, c) == 0)
                throw new ChequePlanException("That planned cheque is not there any more - refresh.", 404);
        }

        public async Task RemoveChequeAsync(int planId)
        {
            if (await _context.RemoveChequePlanChequeAsync(planId) == 0)
                throw new ChequePlanException("That planned cheque is not there any more - refresh.", 404);
        }

        private static void Check(ChequePlanChequeSave c)
        {
            if (string.IsNullOrWhiteSpace(c.SupplierName)) throw new ChequePlanException("Enter the supplier.");
            if (c.SupplierName.Trim().Length > 150) throw new ChequePlanException("The supplier name is too long.");
            if (c.Amount <= 0) throw new ChequePlanException("Enter the cheque amount.");
            if (c.Note?.Trim().Length > 200) throw new ChequePlanException("The note is longer than 200 letters.");
            if (c.Date.Date < DateTime.Today.AddYears(-1) || c.Date.Date > DateTime.Today.AddYears(2))
                throw new ChequePlanException("Check the cheque date.");
        }
    }
}
