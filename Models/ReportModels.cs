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

    // Discount items (DBScript U075 / 46_BackOffice_DiscountReport.sql)

    // z_sp_RptDiscountItems: one item sold with a discount in the range (discounted lines only; AllQty = every line)
    public class RptDiscountItemRow
    {
        public int ItemId { get; set; }            // 0 = other items typed on the till
        public string? RefCode { get; set; }
        public string? Barcode { get; set; }
        public string? Descrip { get; set; }
        public string? CatName { get; set; }
        public string? SuppName { get; set; }
        public int Bills { get; set; }
        public decimal Qty { get; set; }
        public decimal AllQty { get; set; }
        public decimal Gross { get; set; }
        public decimal ItemDisc { get; set; }
        public decimal BillDisc { get; set; }     // the item's share of bill discounts
        public decimal TotalDisc { get; set; }
        public decimal Net { get; set; }
        public decimal? Cost { get; set; }        // NULL = a line's cost is not known
        public decimal? Profit { get; set; }
        public decimal DiscPct { get; set; }
        public decimal? RetailPrice { get; set; }
        public decimal? SetPercent { get; set; }  // discount set on the item now
        public decimal? SetAmount { get; set; }
        public bool NoDiscount { get; set; }
    }

    // z_sp_RptDiscountLines: the discounted lines of one item
    public class RptDiscountLineRow
    {
        public int InvoiceId { get; set; }
        public string InvoiceNo { get; set; } = "";
        public int InvType { get; set; }          // 2 = refund (amounts negative)
        public DateTime InvDate { get; set; }
        public string? TerminalCode { get; set; }
        public string? CashierId { get; set; }
        public string? CashierName { get; set; }
        public int LineNum { get; set; }
        public string? LineDescrip { get; set; }
        public decimal Qty { get; set; }
        public decimal UnitPrice { get; set; }
        public decimal Gross { get; set; }
        public decimal ItemDisc { get; set; }
        public decimal BillDisc { get; set; }
        public decimal Net { get; set; }
        public decimal BillDiscount { get; set; }
        public decimal BillNet { get; set; }
    }

    // z_sp_RptDiscountSetup: active item with a discount set now (or marked no discount)
    public class RptDiscountSetupRow
    {
        public int ItemId { get; set; }
        public string? RefCode { get; set; }
        public string? Barcode { get; set; }
        public string? Descrip { get; set; }
        public string? CatName { get; set; }
        public string? SuppName { get; set; }
        public decimal RetailPrice { get; set; }
        public decimal? CostPrice { get; set; }
        public decimal? SetPercent { get; set; }
        public decimal? SetAmount { get; set; }
        public bool NoDiscount { get; set; }
        public decimal UnitDisc { get; set; }     // what the till takes off one unit
        public decimal PriceAfter { get; set; }
        public bool Capped { get; set; }          // the set discount is more than price - cost (or no cost) - the till gives less
        public decimal StockQty { get; set; }
        public DateTime? Edited { get; set; }
    }

    // z_sp_RptDiscountClear: an item whose discount was cleared, with the old values
    public class RptDiscountCleared
    {
        public int ItemId { get; set; }
        public decimal? OldPercent { get; set; }
        public decimal? OldAmount { get; set; }
    }

    public class RptIdsRequest
    {
        public List<int> Ids { get; set; } = new();
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
