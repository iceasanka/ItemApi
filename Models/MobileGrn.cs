namespace ItemApi.Models
{
    // Mobile GRN draft (U017, StockSystem.md §6.23): a suspended GRN (z_tb_TempPurchaseSummary Status 0, UserId 'mobile')
    // that the phone fills and the back office finishes on the GRN Entry page.

    // one line of the open draft — z_sp_MobileGrnGet
    public class MobileGrnLine
    {
        public string GrnNo { get; set; } = "";
        public int Idx { get; set; }
        public int ItemId { get; set; }
        public string? Barcode { get; set; }
        public string? RefCode { get; set; }
        public string? Descrip { get; set; }
        public decimal Qty { get; set; }
        public decimal CostPrice { get; set; }
        public decimal SellPrice { get; set; }
        public decimal GAmount { get; set; }
        // the item's prices now — the app marks lines whose price differs
        public decimal? ItemCostPrice { get; set; }
        public decimal? ItemRetailPrice { get; set; }
        public decimal StockQty { get; set; }
        public DateTime? UDate { get; set; }
    }

    // POST api/MobileGrn/line
    public class MobileGrnAddRequest
    {
        public int SuppId { get; set; }
        public int ItemId { get; set; }
        public decimal Qty { get; set; }
        public decimal CostPrice { get; set; }
        public decimal SellPrice { get; set; }
    }

    // PUT api/MobileGrn/line/{idx}
    public class MobileGrnUpdateRequest
    {
        public decimal Qty { get; set; }
        public decimal CostPrice { get; set; }
        public decimal SellPrice { get; set; }
    }

    // z_sp_MobileGrnAddLine / UpdateLine
    public class MobileGrnLineRef
    {
        public string GrnNo { get; set; } = "";
        public int Idx { get; set; }
    }

    // z_sp_MobileGrnDeleteLine
    public class MobileGrnDeleteResult
    {
        public string GrnNo { get; set; } = "";
        public int LinesLeft { get; set; }
    }
}
