namespace ItemApi.Models
{
    // POST api/StockLedger/SearchBalances
    public class StockBalanceSearchRequest
    {
        // matches RefCode, Barcode or Descrip
        public string? Query { get; set; }
        public int? CatId { get; set; }
        public int? SupId { get; set; }
        public bool OnlyNegative { get; set; }
        public int Page { get; set; } = 1;
        public int PageSize { get; set; } = 50;
    }

    public class StockBalanceRow
    {
        public int ItemId { get; set; }
        public string? RefCode { get; set; }
        public string? Barcode { get; set; }
        public string? Descrip { get; set; }
        public decimal Qty { get; set; }
        public decimal? AvgCost { get; set; }
        public decimal StockValue { get; set; }
        public DateTime? UDate { get; set; }
    }

    public class StockBalancePage
    {
        public int Total { get; set; }
        public List<StockBalanceRow> Rows { get; set; } = new();
    }

    // GET api/StockLedger/ItemCard — movements of one item with running balance
    public class ItemCard
    {
        public int ItemId { get; set; }
        public string? RefCode { get; set; }
        public string? Descrip { get; set; }
        public DateTime FromDate { get; set; }
        public DateTime ToDate { get; set; }
        public decimal OpeningQty { get; set; }
        public decimal ClosingQty { get; set; }
        public List<ItemCardRow> Rows { get; set; } = new();
    }

    public class ItemCardRow
    {
        public long LedgerId { get; set; }
        public DateTime TxnDate { get; set; }
        public int TxnType { get; set; }
        public string TxnTypeName { get; set; } = "";
        public string DocNo { get; set; } = "";
        public int? TerminalId { get; set; }
        public int? ZNo { get; set; }
        public decimal QtyIn { get; set; }
        public decimal QtyOut { get; set; }
        public decimal Balance { get; set; }
        public decimal? CostPrice { get; set; }
        public decimal? SellPrice { get; set; }
        public string? UserId { get; set; }
    }
}
