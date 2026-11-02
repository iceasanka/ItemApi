namespace ItemApi.Models
{
    // Customer loyalty points (DBScript/27_BackOffice_Loyalty.sql, Docs/StockSystem.md 6.33)

    public class LoyaltyMember
    {
        public int MemberId { get; set; }
        public string Phone { get; set; } = "";
        public string Name { get; set; } = "";
        public int Points { get; set; }
        public int TotalEarned { get; set; }
        public int TotalRedeemed { get; set; }
        public int Status { get; set; }              // 1 active, 0 blocked
        public DateTime? LastBillAt { get; set; }
        public DateTime CreatedAt { get; set; }
        public int? CreatedTerminalId { get; set; }
        public string? CreatedBy { get; set; }
    }

    public class LoyaltySettings
    {
        public bool Enabled { get; set; }
        public decimal EarnAmount { get; set; }      // rupees for 1 point
        public decimal PointValue { get; set; }      // rupees 1 point pays
        public int MinRedeem { get; set; }           // points needed before redeeming
        public bool PrintPoints { get; set; }
        public int RedeemMode { get; set; } = 1;      // 1 pay with points, 2 discount % for points
        public int DiscountPoints { get; set; }       // discount: points one discount uses
        public decimal DiscountPercent { get; set; }  // discount: % off the bill
    }

    // GET api/Loyalty/Member?phone= (till): Found false = not a member
    public class LoyaltyLookup
    {
        public bool Found { get; set; }
        public LoyaltyMember? Member { get; set; }
        public LoyaltySettings Settings { get; set; } = new();
    }

    public class LoyaltyMemberList
    {
        public List<LoyaltyMember> Members { get; set; } = new();
        public int TotalMembers { get; set; }
        public int ActiveMembers { get; set; }
        public long PointsOutstanding { get; set; }
    }

    public class LoyaltyTxn
    {
        public int TxnId { get; set; }
        public int TxnType { get; set; }             // 1 earned, 2 redeemed, 3 given back, 4 taken back (refund), 5 by hand
        public int Points { get; set; }
        public int BalanceAfter { get; set; }
        public int? TerminalId { get; set; }
        public string? TerminalCode { get; set; }
        public string? InvoiceNo { get; set; }
        public decimal? BillAmount { get; set; }
        public string? CashierId { get; set; }
        public int? UserId { get; set; }
        public string? UserName { get; set; }
        public string? Remark { get; set; }
        public DateTime TxnAt { get; set; }
    }

    // POST api/Loyalty/Member (till Menu > Add loyalty member, or the Loyalty page)
    public class LoyaltyAddMemberRequest
    {
        public string? Phone { get; set; }
        public string? Name { get; set; }
        public int? TerminalId { get; set; }
        public string? CashierId { get; set; }
    }

    // PUT api/Loyalty/Members/5
    public class LoyaltyUpdateMemberRequest
    {
        public string? Phone { get; set; }
        public string? Name { get; set; }
        public int Status { get; set; } = 1;
    }

    // POST api/Loyalty/Members/5/Adjust
    public class LoyaltyAdjustRequest
    {
        public int Points { get; set; }
        public string? Remark { get; set; }
    }

    // POST api/Loyalty/Redeem (till, before the bill is saved)
    public class LoyaltyRedeemRequest
    {
        public Guid RedeemKey { get; set; }
        public string? Phone { get; set; }
        public int Points { get; set; }
        public int TerminalId { get; set; }
        public string? CashierId { get; set; }
        public decimal? Amount { get; set; }          // rupees the points pay on the bill (discount: the % of the bill)
    }

    // POST api/Loyalty/RedeemCancel (till: the bill was not saved)
    public class LoyaltyRedeemCancelRequest
    {
        public Guid RedeemKey { get; set; }
    }

    // POST api/Loyalty/Bills (till upload)
    public class LoyaltyBillBatch
    {
        public int TerminalId { get; set; }
        public List<LoyaltyBillRow> Bills { get; set; } = new();
    }

    public class LoyaltyBillRow
    {
        public string InvoiceNo { get; set; } = "";
        public string Phone { get; set; } = "";
        public int InvType { get; set; }
        public int Status { get; set; }
        public decimal BillAmount { get; set; }
        public int PointsEarned { get; set; }
        public int PointsRedeemed { get; set; }
        public decimal RedeemAmount { get; set; }
        public Guid? RedeemKey { get; set; }
        public string? CashierId { get; set; }
        public DateTime InvDate { get; set; }
    }

    public static class LoyaltyPhone
    {
        // digits only, Sri Lankan mobile as 0XXXXXXXXX: "+94 77 123 4567" / "94771234567" / "771234567" -> "0771234567".
        // null = not a phone number (the db refuses anything but 10 digits starting with 0).
        public static string? Normalize(string? phone)
        {
            if (string.IsNullOrWhiteSpace(phone))
                return null;
            var d = new string(phone.Where(char.IsDigit).ToArray());
            if (d.Length == 11 && d.StartsWith("94"))
                d = "0" + d[2..];
            else if (d.Length == 9 && !d.StartsWith('0'))
                d = "0" + d;
            return d.Length == 10 && d.StartsWith('0') ? d : null;
        }
    }
}
