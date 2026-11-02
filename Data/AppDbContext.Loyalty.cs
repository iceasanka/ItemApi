using System.Data;
using System.Data.Common;
using ItemApi.Models;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;

namespace ItemApi.Data
{
    // Customer loyalty points — z_sp_Loyalty* (DBScript/27_BackOffice_Loyalty.sql, Updates/U038_BackOffice_Loyalty.sql)
    public partial class AppDbContext
    {
        public async Task<LoyaltySettings> GetLoyaltySettingsAsync()
        {
            var rows = await LoyaltyReadAsync("dbo.z_sp_LoyaltySettings", _ => { }, ReadLoyaltySettings);
            return rows.FirstOrDefault() ?? new LoyaltySettings();
        }

        public async Task<LoyaltyMember?> GetLoyaltyMemberAsync(string phone) =>
            (await LoyaltyReadAsync("dbo.z_sp_LoyaltyGetMember",
                p => p.Add(new SqlParameter("@Phone", SqlDbType.VarChar, 15) { Value = phone }), ReadLoyaltyMember)).FirstOrDefault();

        public async Task<LoyaltyMember> AddLoyaltyMemberAsync(string phone, string name, int? terminalId, string? createdBy) =>
            (await LoyaltyReadAsync("dbo.z_sp_LoyaltyAddMember", p =>
            {
                p.Add(new SqlParameter("@Phone", SqlDbType.VarChar, 15) { Value = phone });
                p.Add(new SqlParameter("@Name", SqlDbType.NVarChar, 100) { Value = name });
                p.Add(new SqlParameter("@TerminalId", SqlDbType.Int) { Value = (object?)terminalId ?? DBNull.Value });
                p.Add(new SqlParameter("@CreatedBy", SqlDbType.VarChar, 50) { Value = (object?)createdBy ?? DBNull.Value });
            }, ReadLoyaltyMember)).First();

        public async Task<LoyaltyMember> RedeemLoyaltyAsync(LoyaltyRedeemRequest req, string phone) =>
            (await LoyaltyReadAsync("dbo.z_sp_LoyaltyRedeem", p =>
            {
                p.Add(new SqlParameter("@RedeemKey", SqlDbType.UniqueIdentifier) { Value = req.RedeemKey });
                p.Add(new SqlParameter("@Phone", SqlDbType.VarChar, 15) { Value = phone });
                p.Add(new SqlParameter("@Points", SqlDbType.Int) { Value = req.Points });
                p.Add(new SqlParameter("@TerminalId", SqlDbType.Int) { Value = req.TerminalId });
                p.Add(new SqlParameter("@CashierId", SqlDbType.VarChar, 20) { Value = (object?)req.CashierId ?? DBNull.Value });
                p.Add(new SqlParameter("@Amount", SqlDbType.Decimal) { Precision = 18, Scale = 2, Value = (object?)req.Amount ?? DBNull.Value });
            }, ReadLoyaltyMember)).First();

        // true = the points went back now (false = nothing to give back: unknown key, already back, or on a bill)
        public async Task<bool> CancelLoyaltyRedeemAsync(Guid redeemKey) =>
            (await LoyaltyReadAsync("dbo.z_sp_LoyaltyRedeemCancel",
                p => p.Add(new SqlParameter("@RedeemKey", SqlDbType.UniqueIdentifier) { Value = redeemKey }),
                r => r.GetBoolean(r.GetOrdinal("Returned")))).FirstOrDefault();

        // → the InvoiceNo of every bill the back office has done (all of them)
        public async Task<List<string>> SyncLoyaltyBillsAsync(int terminalId, List<LoyaltyBillRow> bills)
        {
            // column order = dbo.z_tt_LoyaltyBill
            var t = new DataTable();
            t.Columns.Add("InvoiceNo", typeof(string));
            t.Columns.Add("Phone", typeof(string));
            t.Columns.Add("InvType", typeof(int));
            t.Columns.Add("Status", typeof(int));
            t.Columns.Add("BillAmount", typeof(decimal));
            t.Columns.Add("PointsEarned", typeof(int));
            t.Columns.Add("PointsRedeemed", typeof(int));
            t.Columns.Add("RedeemAmount", typeof(decimal));
            t.Columns.Add("RedeemKey", typeof(Guid));
            t.Columns.Add("CashierId", typeof(string));
            t.Columns.Add("InvDate", typeof(DateTime));
            foreach (var b in bills.GroupBy(b => b.InvoiceNo).Select(g => g.Last()))
                t.Rows.Add(b.InvoiceNo, b.Phone, b.InvType, b.Status, b.BillAmount, b.PointsEarned, b.PointsRedeemed, b.RedeemAmount,
                           (object?)b.RedeemKey ?? DBNull.Value, (object?)b.CashierId ?? DBNull.Value, b.InvDate);

            return await LoyaltyReadAsync("dbo.z_sp_LoyaltySyncBills", p =>
            {
                p.Add(new SqlParameter("@TerminalId", SqlDbType.Int) { Value = terminalId });
                p.Add(new SqlParameter("@Bills", SqlDbType.Structured) { TypeName = "dbo.z_tt_LoyaltyBill", Value = t });
            }, r => r.GetString(0));
        }

        public async Task<LoyaltyMemberList> GetLoyaltyMembersAsync(string? text, int top)
        {
            var list = new LoyaltyMemberList();
            await using var cmd = await LoyaltyCommandAsync("dbo.z_sp_LoyaltyMembers");
            cmd.Parameters.Add(new SqlParameter("@Text", SqlDbType.NVarChar, 100) { Value = (object?)text ?? DBNull.Value });
            cmd.Parameters.Add(new SqlParameter("@Top", SqlDbType.Int) { Value = top });
            await using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
                list.Members.Add(ReadLoyaltyMember(r));
            if (await r.NextResultAsync() && await r.ReadAsync())
            {
                list.TotalMembers = r.GetInt32(r.GetOrdinal("Members"));
                list.PointsOutstanding = r.GetInt64(r.GetOrdinal("PointsOutstanding"));
                list.ActiveMembers = r.IsDBNull(r.GetOrdinal("Active")) ? 0 : r.GetInt32(r.GetOrdinal("Active"));
            }
            return list;
        }

        public Task<List<LoyaltyTxn>> GetLoyaltyTxnsAsync(int memberId) =>
            LoyaltyReadAsync("dbo.z_sp_LoyaltyMemberTxns",
                p => p.Add(new SqlParameter("@MemberId", SqlDbType.Int) { Value = memberId }),
                r => new LoyaltyTxn
                {
                    TxnId = r.GetInt32(r.GetOrdinal("TxnId")),
                    TxnType = r.GetInt32(r.GetOrdinal("TxnType")),
                    Points = r.GetInt32(r.GetOrdinal("Points")),
                    BalanceAfter = r.GetInt32(r.GetOrdinal("BalanceAfter")),
                    TerminalId = Opt<int>(r, "TerminalId"),
                    TerminalCode = OptStr(r, "TerminalCode"),
                    InvoiceNo = OptStr(r, "InvoiceNo"),
                    BillAmount = Opt<decimal>(r, "BillAmount"),
                    CashierId = OptStr(r, "CashierId"),
                    UserId = Opt<int>(r, "UserId"),
                    UserName = OptStr(r, "UserName"),
                    Remark = OptStr(r, "Remark"),
                    TxnAt = r.GetDateTime(r.GetOrdinal("TxnAt")),
                });

        public async Task UpdateLoyaltyMemberAsync(int memberId, string phone, string name, int status, int? userId) =>
            await LoyaltyReadAsync<int>("dbo.z_sp_LoyaltyUpdateMember", p =>
            {
                p.Add(new SqlParameter("@MemberId", SqlDbType.Int) { Value = memberId });
                p.Add(new SqlParameter("@Phone", SqlDbType.VarChar, 15) { Value = phone });
                p.Add(new SqlParameter("@Name", SqlDbType.NVarChar, 100) { Value = name });
                p.Add(new SqlParameter("@Status", SqlDbType.Int) { Value = status });
                p.Add(new SqlParameter("@UserId", SqlDbType.Int) { Value = (object?)userId ?? DBNull.Value });
            }, _ => 0);

        // → the balance after it
        public async Task<int> AdjustLoyaltyAsync(int memberId, int points, string? remark, int? userId) =>
            (await LoyaltyReadAsync("dbo.z_sp_LoyaltyAdjust", p =>
            {
                p.Add(new SqlParameter("@MemberId", SqlDbType.Int) { Value = memberId });
                p.Add(new SqlParameter("@Points", SqlDbType.Int) { Value = points });
                p.Add(new SqlParameter("@Remark", SqlDbType.NVarChar, 200) { Value = (object?)remark ?? DBNull.Value });
                p.Add(new SqlParameter("@UserId", SqlDbType.Int) { Value = (object?)userId ?? DBNull.Value });
            }, r => r.GetInt32(0))).FirstOrDefault();

        // ─── helpers ─────────────────────────────────────────────────────────────

        private async Task<DbCommand> LoyaltyCommandAsync(string proc)
        {
            var cn = Database.GetDbConnection();
            if (cn.State != ConnectionState.Open)
                await cn.OpenAsync();
            var cmd = cn.CreateCommand();
            cmd.CommandText = proc;
            cmd.CommandType = CommandType.StoredProcedure;
            return cmd;
        }

        private async Task<List<T>> LoyaltyReadAsync<T>(string proc, Action<DbParameterCollection> addParams, Func<DbDataReader, T> read)
        {
            await using var cmd = await LoyaltyCommandAsync(proc);
            addParams(cmd.Parameters);
            var list = new List<T>();
            await using var r = await cmd.ExecuteReaderAsync();
            do
            {
                while (await r.ReadAsync())
                    list.Add(read(r));
                if (list.Count > 0)
                    break;   // the first result set with rows (the procs answer with one)
            } while (await r.NextResultAsync());
            return list;
        }

        private static LoyaltyMember ReadLoyaltyMember(DbDataReader r) => new()
        {
            MemberId = r.GetInt32(r.GetOrdinal("MemberId")),
            Phone = r.GetString(r.GetOrdinal("Phone")),
            Name = r.GetString(r.GetOrdinal("Name")),
            Points = r.GetInt32(r.GetOrdinal("Points")),
            TotalEarned = r.GetInt32(r.GetOrdinal("TotalEarned")),
            TotalRedeemed = r.GetInt32(r.GetOrdinal("TotalRedeemed")),
            Status = r.GetInt32(r.GetOrdinal("Status")),
            LastBillAt = Opt<DateTime>(r, "LastBillAt"),
            CreatedAt = r.GetDateTime(r.GetOrdinal("CreatedAt")),
            CreatedTerminalId = HasColumn(r, "CreatedTerminalId") ? Opt<int>(r, "CreatedTerminalId") : null,
            CreatedBy = HasColumn(r, "CreatedBy") ? OptStr(r, "CreatedBy") : null,
        };

        private static LoyaltySettings ReadLoyaltySettings(DbDataReader r) => new()
        {
            Enabled = r.GetBoolean(r.GetOrdinal("Enabled")),
            EarnAmount = r.GetDecimal(r.GetOrdinal("EarnAmount")),
            PointValue = r.GetDecimal(r.GetOrdinal("PointValue")),
            MinRedeem = r.GetInt32(r.GetOrdinal("MinRedeem")),
            PrintPoints = r.GetBoolean(r.GetOrdinal("PrintPoints")),
            RedeemMode = r.GetInt32(r.GetOrdinal("RedeemMode")),
            DiscountPoints = r.GetInt32(r.GetOrdinal("DiscountPoints")),
            DiscountPercent = r.GetDecimal(r.GetOrdinal("DiscountPercent")),
        };

        private static bool HasColumn(DbDataReader r, string name)
        {
            for (var i = 0; i < r.FieldCount; i++)
                if (string.Equals(r.GetName(i), name, StringComparison.OrdinalIgnoreCase))
                    return true;
            return false;
        }

        private static T? Opt<T>(DbDataReader r, string name) where T : struct
        {
            var i = r.GetOrdinal(name);
            return r.IsDBNull(i) ? null : r.GetFieldValue<T>(i);
        }

        private static string? OptStr(DbDataReader r, string name)
        {
            var i = r.GetOrdinal(name);
            return r.IsDBNull(i) ? null : r.GetString(i);
        }
    }
}
