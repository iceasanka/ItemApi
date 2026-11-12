namespace ItemApi.Models
{
    // Customer wallet (DBScript/37_BackOffice_Wallet.sql, Updates/U059_BackOffice_Wallet.sql). Its own function, separate
    // from loyalty points; the members are the loyalty members (by phone). On a bill: payment PayType 9, signed
    // (+ paid from the wallet, - change kept). Never paid out as cash.

    public class WalletSettings
    {
        public bool Enabled { get; set; }
        public decimal MaxKeep { get; set; }       // most change kept per bill (0 = can't keep change)
        public decimal MaxBalance { get; set; }    // most a wallet holds (0 = no limit)
        public decimal MinusLimit { get; set; }    // how far below 0 (0 = never)
    }

    // the wallet part of GET api/Loyalty/Member (till): null when the back office has no wallet (no U059)
    public class WalletLookup
    {
        public WalletSettings Settings { get; set; } = new();
        public decimal? Balance { get; set; }      // null = not a member
    }

    public class WalletMember
    {
        public int MemberId { get; set; }
        public string Phone { get; set; } = "";
        public string Name { get; set; } = "";
        public int Status { get; set; }
        public decimal WalletBalance { get; set; }
        public decimal? BalanceBefore { get; set; } // api/Wallet/Bill: the wallet before this bill
        public DateTime? LastTxnAt { get; set; }    // Wallet tab
    }

    public class WalletMemberList
    {
        public List<WalletMember> Members { get; set; } = new();
        public decimal HeldForCustomers { get; set; }   // + balances: the shop holds the customers' money
        public decimal OwedByCustomers { get; set; }    // - balances: the customers owe the shop
        public int Wallets { get; set; }                // members whose wallet is not 0
    }

    public class WalletTxn
    {
        public int TxnId { get; set; }
        public int TxnType { get; set; }            // 1 on a bill, 3 given back (bill not saved / voided)
        public decimal Amount { get; set; }         // the balance change: + change kept, - paid from the wallet
        public decimal BalanceAfter { get; set; }
        public int? TerminalId { get; set; }
        public string? TerminalCode { get; set; }
        public string? InvoiceNo { get; set; }
        public string? CashierId { get; set; }
        public string? Remark { get; set; }
        public DateTime TxnAt { get; set; }
    }

    // POST api/Wallet/Bill (till, before the bill is saved). Amount = the bill's WALLET payment: + paid from the wallet,
    // - change kept.
    public class WalletBillRequest
    {
        public Guid WalletKey { get; set; }
        public string? Phone { get; set; }
        public decimal Amount { get; set; }
        public int TerminalId { get; set; }
        public string? CashierId { get; set; }
    }

    // POST api/Wallet/Cancel (till: the bill was not saved)
    public class WalletCancelRequest
    {
        public Guid WalletKey { get; set; }
    }

    // POST api/Wallet/Bills (till upload)
    public class WalletBillBatch
    {
        public int TerminalId { get; set; }
        public List<WalletBillRow> Bills { get; set; } = new();
    }

    public class WalletBillRow
    {
        public string InvoiceNo { get; set; } = "";
        public Guid WalletKey { get; set; }
        public int Status { get; set; }             // the bill's: 1 completed, 9 voided
    }
}
