using System.Data;
using ItemApi.Models;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;

namespace ItemApi.Data
{
    // Cash Management saved as a cash settlement (z_tb_CashSettlement, DBScript U055 / 34_BackOffice_CashSettlement.sql).
    // Business errors from the procs: RAISERROR → SqlException.Number 50000.
    public partial class AppDbContext
    {
        public async Task<CashSettlementRow> SaveCashSettlementAsync(int terminalId, string? cashierId, decimal countedCash,
            decimal cashIn, decimal cashOut, decimal cashierCash, decimal returnedCoins, string? detail, string? createdBy)
        {
            var rows = await Database.SqlQueryRaw<CashSettlementRow>(
                "EXEC dbo.z_sp_CashSettlementSave @TerminalId = @TerminalId, @CashierId = @CashierId, @CountedCash = @CountedCash, " +
                "@CashIn = @CashIn, @CashOut = @CashOut, @CashierCash = @CashierCash, @ReturnedCoins = @ReturnedCoins, " +
                "@Detail = @Detail, @CreatedBy = @CreatedBy",
                new SqlParameter("@TerminalId", terminalId),
                new SqlParameter("@CashierId", SqlDbType.VarChar, 20) { Value = Db(string.IsNullOrWhiteSpace(cashierId) ? null : cashierId.Trim()) },
                Money("@CountedCash", countedCash),
                Money("@CashIn", cashIn),
                Money("@CashOut", cashOut),
                Money("@CashierCash", cashierCash),
                Money("@ReturnedCoins", returnedCoins),
                new SqlParameter("@Detail", SqlDbType.NVarChar, -1) { Value = Db(detail) },
                new SqlParameter("@CreatedBy", SqlDbType.VarChar, 50) { Value = Db(Cut(createdBy, 50)) }).ToListAsync();
            return rows.First();
        }

        // newest first: counted from..to (dates, optional), matching search (slip code / no, till, cashier, Z no)
        public Task<List<CashSettlementRow>> GetCashSettlementsAsync(DateTime? from, DateTime? to, string? search, int top = 500) =>
            Database.SqlQueryRaw<CashSettlementRow>(
                "EXEC dbo.z_sp_CashSettlementList @Top = @Top, @From = @From, @To = @To, @Search = @Search",
                new SqlParameter("@Top", Math.Clamp(top, 1, 1000)),
                new SqlParameter("@From", SqlDbType.Date) { Value = Db(from?.Date) },
                new SqlParameter("@To", SqlDbType.Date) { Value = Db(to?.Date) },
                new SqlParameter("@Search", SqlDbType.VarChar, 50) { Value = Db(Cut(string.IsNullOrWhiteSpace(search) ? null : search.Trim(), 50)) })
            .ToListAsync();

        public async Task<CashSettlementRow?> GetCashSettlementAsync(int settlementId) =>
            (await Database.SqlQueryRaw<CashSettlementRow>("EXEC dbo.z_sp_CashSettlementList @SettlementId = @Id",
                new SqlParameter("@Id", settlementId)).ToListAsync()).FirstOrDefault();

        // a wrong count: deleted while the till has not used the slip (the proc refuses otherwise)
        public Task DeleteCashSettlementAsync(int settlementId) =>
            Database.ExecuteSqlRawAsync("EXEC dbo.z_sp_CashSettlementDelete @SettlementId = @Id",
                new SqlParameter("@Id", settlementId));

        // A Z arrived with a scanned slip: link them. Never fails the Z - a problem (wrong till, cancelled, a db
        // without U055) is only logged; the sheet then falls back to the Z's own counted cash.
        public async Task LinkCashSettlementAsync(int settlementId, int terminalId, int zNo)
        {
            try
            {
                await Database.ExecuteSqlRawAsync("EXEC dbo.z_sp_CashSettlementLinkZ @SettlementId = @S, @TerminalId = @T, @ZNo = @Z",
                    new SqlParameter("@S", settlementId), new SqlParameter("@T", terminalId), new SqlParameter("@Z", zNo));
            }
            catch (SqlException ex) when (ex.Number >= 50000 || ex.Number == 2812)
            {
                Serilog.Log.Warning($"Cash slip {settlementId} not linked to till {terminalId} Z {zNo}: {ex.Message}");
            }
        }

        // users who can work on the till (Admin / Cashier, active) - the Cash Management cashier list
        public Task<List<CashierOption>> GetTillCashiersAsync() =>
            Database.SqlQueryRaw<CashierOption>(
                "SELECT LoginName, UserName FROM dbo.z_tb_User WHERE Status = 1 AND RoleId IN (1, 3) AND LoginName IS NOT NULL " +
                "ORDER BY UserName").ToListAsync();

        private static SqlParameter Money(string name, decimal value) =>
            new(name, SqlDbType.Decimal) { Precision = 18, Scale = 2, Value = Math.Round(value, 2) };

        private static string? Cut(string? text, int max) => text == null ? null : text.Length > max ? text[..max] : text;
    }
}
