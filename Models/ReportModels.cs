namespace ItemApi.Models
{
    // Back office > Reports (DBScript U057 / 36_BackOffice_Reports.sql).

    // z_sp_RptPeriod: one day or one month (Period = the 1st)
    public class RptPeriodRow
    {
        public DateTime Period { get; set; }
        public int Bills { get; set; }
        public decimal NetSales { get; set; }
        public decimal Cost { get; set; }
        public decimal Profit { get; set; }
        public decimal MarginPct { get; set; }
        public decimal Cash { get; set; }
        public decimal Card { get; set; }
        public decimal BankIn { get; set; }
        public decimal ChequeIn { get; set; }
        public decimal OtherIn { get; set; }
        public decimal PaidIn { get; set; }
        public decimal PaidOut { get; set; }
        public decimal Purchases { get; set; }
        public decimal SupReturns { get; set; }
        public decimal PayCheque { get; set; }
        public decimal PayCash { get; set; }      // supplier paid in cash at a till - also in PaidOut
        public decimal PayTransfer { get; set; }
        public decimal StockIn { get; set; }
        public decimal StockAdj { get; set; }
    }

    // z_sp_RptStockNow
    public class RptStockNow
    {
        public int Items { get; set; }
        public int InStock { get; set; }
        public int ZeroStock { get; set; }
        public int MinusStock { get; set; }
        public decimal CostValue { get; set; }
        public decimal RetailValue { get; set; }
    }

    public class RptPeriodResponse
    {
        public List<RptPeriodRow> Rows { get; set; } = new();
        public RptStockNow? Stock { get; set; }
    }

    // z_sp_RptMoney: Kind CHEQUE / TRANSFER / PAIDOUT / PAIDIN / BANKIN / CHEQUEIN
    public class RptMoneyRow
    {
        public string Kind { get; set; } = "";
        public DateTime TxnDate { get; set; }
        public decimal Amount { get; set; }
        public string? Party { get; set; }
        public string? Ref { get; set; }
        public string? Note { get; set; }
        public DateTime? ChequeDate { get; set; }
        public bool? Cleared { get; set; }
        public string? Terminal { get; set; }
        public int SourceId { get; set; }
    }

    // z_sp_RptStockHealth
    public class RptStockHealthRow
    {
        public int ItemId { get; set; }
        public string? RefCode { get; set; }
        public string? Barcode { get; set; }
        public string? Descrip { get; set; }
        public string? CatName { get; set; }
        public string? SuppName { get; set; }
        public decimal Qty { get; set; }
        public decimal UnitCost { get; set; }
        public decimal CostValue { get; set; }
        public decimal RetailPrice { get; set; }
        public DateTime? LastSale { get; set; }
        public DateTime? LastIn { get; set; }
        public DateTime? LastMove { get; set; }
        public DateTime? Edited { get; set; }
        public DateTime? Created { get; set; }
        public int Status { get; set; }
    }

    public class RptItemStatusRequest
    {
        public List<int> Ids { get; set; } = new();
        public bool Active { get; set; }
    }

    public class RptChanged
    {
        public int Changed { get; set; }
    }
}
