namespace ItemApi.Models
{
    // Cheque planner (DBScript/28_BackOffice_ChequePlanner.sql, Updates/U048): the page Payments & Cash > Cheque
    // Planner. Separate from the Google sheet (AsankaTemp) that the Cheque Writer keeps updating.

    public class ChequePlan
    {
        public DateTime Today { get; set; }
        public DateTime From { get; set; }
        public DateTime To { get; set; }
        public ChequePlanConfig Config { get; set; } = new();
        public List<ChequePlanDay> Days { get; set; } = new();
        /// <summary>Written and planned cheques of From..To, plus the ones before From (up to OverdueDays back) not debited yet.</summary>
        public List<ChequePlanCheque> Cheques { get; set; } = new();
    }

    // z_tb_CashPlanConfig (one row)
    public class ChequePlanConfig
    {
        public decimal AvgCash { get; set; }
        public decimal AvgCard { get; set; }
        public decimal KeepMin { get; set; }
        public decimal? BankBalance { get; set; }
        public DateTime? BankBalanceAt { get; set; }
        public bool TodayNotBanked { get; set; }
        public int OverdueDays { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }

    // z_sp_ChequePlanDays row
    public class ChequePlanDayRow
    {
        public DateTime PlanDate { get; set; }
        public int ZCount { get; set; }
        public decimal CashSales { get; set; }
        public decimal PaidIn { get; set; }
        public decimal PaidOut { get; set; }
        public decimal CashInHand { get; set; }
        public decimal CardAmount { get; set; }
        public decimal? CardSettlement { get; set; }
        public decimal BankAmount { get; set; }
        public decimal? ExpectedCash { get; set; }
        public decimal? ExpectedCard { get; set; }
        public string? Note { get; set; }
    }

    /// <summary>A day's money in. Actual = the day has Z reports: Cash = cash in hand (cash sales + paid in - paid out),
    /// Card = card sales, Bank = bank transfers. Otherwise the expected takings (the day's own, else the average).</summary>
    public class ChequePlanDay
    {
        public DateTime Date { get; set; }
        public bool Actual { get; set; }
        public int ZCount { get; set; }
        public decimal Cash { get; set; }
        public decimal Card { get; set; }
        public decimal Bank { get; set; }
        public decimal Total { get; set; }
        // the Z detail behind an actual day
        public decimal CashSales { get; set; }
        public decimal PaidIn { get; set; }
        public decimal PaidOut { get; set; }
        public decimal? CardSettlement { get; set; }
        // the day's own estimate (null = the average)
        public decimal? ExpectedCash { get; set; }
        public decimal? ExpectedCard { get; set; }
        public string? Note { get; set; }
    }

    // z_sp_ChequePlanCheques row. Source 1 = written (z_tb_WrittenCheque), 2 = planned (z_tb_CashPlanCheque).
    public class ChequePlanCheque
    {
        public int Source { get; set; }
        public int Id { get; set; }
        public int? ChequeNumber { get; set; }
        public DateTime PlanDate { get; set; }
        public decimal Amount { get; set; }
        public string Name { get; set; } = "";
        public int? SuppId { get; set; }
        public bool IsDebited { get; set; }
        public string? Note { get; set; }
    }

    public class ChequePlanConfigSave
    {
        public decimal AvgCash { get; set; }
        public decimal AvgCard { get; set; }
        public decimal KeepMin { get; set; }
        public decimal? BankBalance { get; set; }
        public bool TodayNotBanked { get; set; }
        public int OverdueDays { get; set; }
    }

    public class ChequePlanDaySave
    {
        public decimal? ExpectedCash { get; set; }
        public decimal? ExpectedCard { get; set; }
        public string? Note { get; set; }
    }

    public class ChequePlanChequeSave
    {
        public DateTime Date { get; set; }
        public string SupplierName { get; set; } = "";
        public int? SuppId { get; set; }
        public decimal Amount { get; set; }
        public string? Note { get; set; }
    }

    public class ChequePlanException : Exception
    {
        public int StatusCode { get; }
        public ChequePlanException(string message, int statusCode = 400) : base(message) { StatusCode = statusCode; }
    }
}
