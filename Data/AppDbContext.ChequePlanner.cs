using System.Data;
using ItemApi.Models;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;

namespace ItemApi.Data
{
    // Cheque planner (DBScript/28_BackOffice_ChequePlanner.sql, Updates/U048_BackOffice_ChequePlanner.sql).
    public partial class AppDbContext
    {
        public async Task<ChequePlanConfig> GetChequePlanConfigAsync()
        {
            var rows = await Database.SqlQueryRaw<ChequePlanConfig>(
                "SELECT AvgCash, AvgCard, KeepMin, BankBalance, BankBalanceAt, TodayNotBanked, OverdueDays, UpdatedAt " +
                "FROM dbo.z_tb_CashPlanConfig WHERE ConfigId = 1").ToListAsync();
            return rows.FirstOrDefault() ?? new ChequePlanConfig { AvgCash = 400000, TodayNotBanked = true, OverdueDays = 45 };
        }

        public Task<List<ChequePlanDayRow>> GetChequePlanDaysAsync(DateTime from, DateTime to, int locationId) =>
            Database.SqlQueryRaw<ChequePlanDayRow>(
                "EXEC dbo.z_sp_ChequePlanDays @From = @From, @To = @To, @LocationId = @LocationId",
                new SqlParameter("@From", SqlDbType.Date) { Value = from.Date },
                new SqlParameter("@To", SqlDbType.Date) { Value = to.Date },
                new SqlParameter("@LocationId", locationId)).ToListAsync();

        public Task<List<ChequePlanCheque>> GetChequePlanChequesAsync(DateTime from, DateTime to, DateTime overdueFrom) =>
            Database.SqlQueryRaw<ChequePlanCheque>(
                "EXEC dbo.z_sp_ChequePlanCheques @From = @From, @To = @To, @OverdueFrom = @OverdueFrom",
                new SqlParameter("@From", SqlDbType.Date) { Value = from.Date },
                new SqlParameter("@To", SqlDbType.Date) { Value = to.Date },
                new SqlParameter("@OverdueFrom", SqlDbType.Date) { Value = overdueFrom.Date }).ToListAsync();

        public Task SaveChequePlanConfigAsync(ChequePlanConfigSave c) =>
            Database.ExecuteSqlRawAsync(
                "IF NOT EXISTS (SELECT 1 FROM dbo.z_tb_CashPlanConfig WHERE ConfigId = 1) INSERT dbo.z_tb_CashPlanConfig (ConfigId) VALUES (1); " +
                "UPDATE dbo.z_tb_CashPlanConfig SET AvgCash = @AvgCash, AvgCard = @AvgCard, KeepMin = @KeepMin, " +
                "  BankBalanceAt = CASE WHEN (BankBalance IS NULL AND @Bank IS NULL) OR BankBalance = @Bank THEN BankBalanceAt " +
                "                       WHEN @Bank IS NULL THEN NULL ELSE GETDATE() END, " +
                "  BankBalance = @Bank, TodayNotBanked = @TodayNotBanked, OverdueDays = @OverdueDays, UpdatedAt = GETDATE() " +
                "WHERE ConfigId = 1;",
                PlanDec("@AvgCash", c.AvgCash), PlanDec("@AvgCard", c.AvgCard), PlanDec("@KeepMin", c.KeepMin), PlanDec("@Bank", c.BankBalance),
                new SqlParameter("@TodayNotBanked", SqlDbType.Bit) { Value = c.TodayNotBanked },
                new SqlParameter("@OverdueDays", c.OverdueDays));

        // all empty = the day goes back to the average (row removed)
        public Task SaveChequePlanDayAsync(DateTime date, ChequePlanDaySave d) =>
            Database.ExecuteSqlRawAsync(
                "IF @Cash IS NULL AND @Card IS NULL AND @Note IS NULL " +
                "  DELETE dbo.z_tb_CashPlanDay WHERE PlanDate = @Date; " +
                "ELSE IF EXISTS (SELECT 1 FROM dbo.z_tb_CashPlanDay WHERE PlanDate = @Date) " +
                "  UPDATE dbo.z_tb_CashPlanDay SET ExpectedCash = @Cash, ExpectedCard = @Card, Note = @Note, UpdatedAt = GETDATE() WHERE PlanDate = @Date; " +
                "ELSE INSERT dbo.z_tb_CashPlanDay (PlanDate, ExpectedCash, ExpectedCard, Note, UpdatedAt) VALUES (@Date, @Cash, @Card, @Note, GETDATE());",
                new SqlParameter("@Date", SqlDbType.Date) { Value = date.Date },
                PlanDec("@Cash", d.ExpectedCash), PlanDec("@Card", d.ExpectedCard), PlanStr("@Note", d.Note, 200));

        public async Task<int> AddChequePlanChequeAsync(ChequePlanChequeSave c)
        {
            var id = await Database.SqlQueryRaw<int>(
                "INSERT dbo.z_tb_CashPlanCheque (PlanDate, SupplierName, SuppId, Amount, Note) VALUES (@Date, @Name, @SuppId, @Amount, @Note); " +
                "SELECT CAST(SCOPE_IDENTITY() AS INT) AS Value;",
                ChequeParams(c)).ToListAsync();
            return id.FirstOrDefault();
        }

        // rows changed (0 = no such planned cheque)
        public Task<int> UpdateChequePlanChequeAsync(int planId, ChequePlanChequeSave c) =>
            Database.ExecuteSqlRawAsync(
                "UPDATE dbo.z_tb_CashPlanCheque SET PlanDate = @Date, SupplierName = @Name, SuppId = @SuppId, Amount = @Amount, " +
                "  Note = @Note, UpdatedAt = GETDATE() WHERE PlanId = @PlanId AND Status = 1;",
                ChequeParams(c).Append(new SqlParameter("@PlanId", planId)).ToArray());

        public Task<int> RemoveChequePlanChequeAsync(int planId) =>
            Database.ExecuteSqlRawAsync(
                "UPDATE dbo.z_tb_CashPlanCheque SET Status = 9, UpdatedAt = GETDATE() WHERE PlanId = @PlanId AND Status = 1;",
                new SqlParameter("@PlanId", planId));

        private static SqlParameter[] ChequeParams(ChequePlanChequeSave c) => new[]
        {
            new SqlParameter("@Date", SqlDbType.Date) { Value = c.Date.Date },
            PlanStr("@Name", c.SupplierName, 150),
            new SqlParameter("@SuppId", SqlDbType.Int) { Value = (object?)c.SuppId ?? DBNull.Value },
            PlanDec("@Amount", c.Amount),
            PlanStr("@Note", c.Note, 200),
        };

        private static SqlParameter PlanDec(string name, decimal? v) =>
            new(name, SqlDbType.Decimal) { Precision = 18, Scale = 2, Value = (object?)v ?? DBNull.Value };

        private static SqlParameter PlanStr(string name, string? v, int size) =>
            new(name, SqlDbType.NVarChar, size) { Value = string.IsNullOrWhiteSpace(v) ? DBNull.Value : v.Trim() };
    }
}
