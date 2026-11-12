using System.Data;
using System.Data.Common;
using ItemApi.Models;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;

namespace ItemApi.Data
{
    // Customer wallet — z_sp_Wallet* (DBScript/37_BackOffice_Wallet.sql, Updates/U059_BackOffice_Wallet.sql)
    public partial class AppDbContext
    {
        // false = this back office db has no wallet yet (U059 not run): the wallet is simply off
        public async Task<bool> HasWalletAsync() =>
            (await Database.SqlQueryRaw<int>(
                "SELECT CASE WHEN OBJECT_ID('dbo.z_sp_WalletBill', 'P') IS NULL THEN 0 ELSE 1 END AS Value").ToListAsync())[0] == 1;

        public async Task<WalletSettings> GetWalletSettingsAsync()
        {
            if (!await HasWalletAsync())
                return new WalletSettings();
            var rows = await LoyaltyReadAsync("dbo.z_sp_WalletSettings", _ => { }, r => new WalletSettings
            {
                Enabled = r.GetBoolean(r.GetOrdinal("Enabled")),
                MaxKeep = r.GetDecimal(r.GetOrdinal("MaxKeep")),
                MaxBalance = r.GetDecimal(r.GetOrdinal("MaxBalance")),
                MinusLimit = r.GetDecimal(r.GetOrdinal("MinusLimit")),
            });
            return rows.FirstOrDefault() ?? new WalletSettings();
        }

        // the wallet part of the till's member lookup; null = no wallet on this back office (U059 not run)
        public async Task<WalletLookup?> GetWalletLookupAsync(string phone)
        {
            if (!await HasWalletAsync())
                return null;
            var member = (await LoyaltyReadAsync("dbo.z_sp_WalletGetMember",
                p => p.Add(new SqlParameter("@Phone", SqlDbType.VarChar, 15) { Value = phone }), ReadWalletMember)).FirstOrDefault();
            return new WalletLookup { Settings = await GetWalletSettingsAsync(), Balance = member?.WalletBalance };
        }

        public async Task<WalletMember> WalletBillAsync(WalletBillRequest req, string phone) =>
            (await LoyaltyReadAsync("dbo.z_sp_WalletBill", p =>
            {
                p.Add(new SqlParameter("@WalletKey", SqlDbType.UniqueIdentifier) { Value = req.WalletKey });
                p.Add(new SqlParameter("@Phone", SqlDbType.VarChar, 15) { Value = phone });
                p.Add(new SqlParameter("@Amount", SqlDbType.Decimal) { Precision = 18, Scale = 2, Value = req.Amount });
                p.Add(new SqlParameter("@TerminalId", SqlDbType.Int) { Value = req.TerminalId });
                p.Add(new SqlParameter("@CashierId", SqlDbType.VarChar, 20) { Value = (object?)req.CashierId ?? DBNull.Value });
            }, ReadWalletMember)).First();

        // true = given back now (false = nothing to give back: unknown key, already back, or on a bill)
        public async Task<bool> CancelWalletAsync(Guid walletKey) =>
            (await LoyaltyReadAsync("dbo.z_sp_WalletCancel",
                p => p.Add(new SqlParameter("@WalletKey", SqlDbType.UniqueIdentifier) { Value = walletKey }),
                r => r.GetBoolean(r.GetOrdinal("Returned")))).FirstOrDefault();

        // → the InvoiceNo of every bill done (all of them)
        public async Task<List<string>> SyncWalletBillsAsync(int terminalId, List<WalletBillRow> bills)
        {
            // column order = dbo.z_tt_WalletBill
            var t = new DataTable();
            t.Columns.Add("InvoiceNo", typeof(string));
            t.Columns.Add("WalletKey", typeof(Guid));
            t.Columns.Add("Status", typeof(int));
            foreach (var b in bills.GroupBy(b => b.InvoiceNo).Select(g => g.Last()))
                t.Rows.Add(b.InvoiceNo, b.WalletKey, b.Status);

            return await LoyaltyReadAsync("dbo.z_sp_WalletSyncBills", p =>
            {
                p.Add(new SqlParameter("@TerminalId", SqlDbType.Int) { Value = terminalId });
                p.Add(new SqlParameter("@Bills", SqlDbType.Structured) { TypeName = "dbo.z_tt_WalletBill", Value = t });
            }, r => r.GetString(r.GetOrdinal("InvoiceNo")));
        }

        public async Task<WalletMemberList> GetWalletMembersAsync(string? text, bool nonZero, int top)
        {
            var list = new WalletMemberList();
            await using var cmd = await LoyaltyCommandAsync("dbo.z_sp_WalletMembers");
            cmd.Parameters.Add(new SqlParameter("@Text", SqlDbType.NVarChar, 100) { Value = (object?)text ?? DBNull.Value });
            cmd.Parameters.Add(new SqlParameter("@NonZero", SqlDbType.Bit) { Value = nonZero });
            cmd.Parameters.Add(new SqlParameter("@Top", SqlDbType.Int) { Value = top });
            await using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
                list.Members.Add(ReadWalletMember(r));
            if (await r.NextResultAsync() && await r.ReadAsync())
            {
                list.HeldForCustomers = r.GetDecimal(r.GetOrdinal("HeldForCustomers"));
                list.OwedByCustomers = r.GetDecimal(r.GetOrdinal("OwedByCustomers"));
                list.Wallets = r.IsDBNull(r.GetOrdinal("Wallets")) ? 0 : r.GetInt32(r.GetOrdinal("Wallets"));
            }
            return list;
        }

        public Task<List<WalletTxn>> GetWalletTxnsAsync(int memberId) =>
            LoyaltyReadAsync("dbo.z_sp_WalletMemberTxns",
                p => p.Add(new SqlParameter("@MemberId", SqlDbType.Int) { Value = memberId }),
                r => new WalletTxn
                {
                    TxnId = r.GetInt32(r.GetOrdinal("TxnId")),
                    TxnType = r.GetInt32(r.GetOrdinal("TxnType")),
                    Amount = r.GetDecimal(r.GetOrdinal("Amount")),
                    BalanceAfter = r.GetDecimal(r.GetOrdinal("BalanceAfter")),
                    TerminalId = Opt<int>(r, "TerminalId"),
                    TerminalCode = OptStr(r, "TerminalCode"),
                    InvoiceNo = OptStr(r, "InvoiceNo"),
                    CashierId = OptStr(r, "CashierId"),
                    Remark = OptStr(r, "Remark"),
                    TxnAt = r.GetDateTime(r.GetOrdinal("TxnAt")),
                });

        private static WalletMember ReadWalletMember(DbDataReader r) => new()
        {
            MemberId = r.GetInt32(r.GetOrdinal("MemberId")),
            Phone = r.GetString(r.GetOrdinal("Phone")),
            Name = r.GetString(r.GetOrdinal("Name")),
            Status = r.GetInt32(r.GetOrdinal("Status")),
            WalletBalance = r.GetDecimal(r.GetOrdinal("WalletBalance")),
            BalanceBefore = HasColumn(r, "BalanceBefore") ? Opt<decimal>(r, "BalanceBefore") : null,
            LastTxnAt = HasColumn(r, "LastTxnAt") ? Opt<DateTime>(r, "LastTxnAt") : null,
        };
    }
}
