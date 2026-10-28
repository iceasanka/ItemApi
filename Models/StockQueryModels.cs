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

    // GET api/StockLedger/ItemStock/{itemId} — stock panel of Item Entry
    public class ItemStockInfo
    {
        public int ItemId { get; set; }
        public decimal Qty { get; set; }
        public decimal? AvgCost { get; set; }
        // open batches: qty x their cost (FIFO value); qty in a batch without a cost is left out
        public decimal BatchQty { get; set; }
        public decimal BatchValue { get; set; }
        public DateTime? LastGrnDate { get; set; }
        public string? LastGrnNo { get; set; }
        public decimal? LastGrnQty { get; set; }
        public decimal? LastGrnCost { get; set; }
        public decimal? LastGrnSellPrice { get; set; }
        public DateTime? LastSaleDate { get; set; }
        public decimal SoldQty30 { get; set; }   // sales - refunds, last 30 days
        public List<ItemStockBatchRow> Batches { get; set; } = new();
        public List<ItemCardRow> RecentMoves { get; set; } = new();
    }

    public class ItemStockBatchRow
    {
        public int BatchId { get; set; }
        public DateTime InDate { get; set; }
        public string DocNo { get; set; } = "";
        public string TxnTypeName { get; set; } = "";
        public decimal? SellPrice { get; set; }   // NULL = the item's normal price
        public int? PriceLinkId { get; set; }
        public decimal? CostPrice { get; set; }
        public decimal InQty { get; set; }
        public decimal Qty { get; set; }
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
