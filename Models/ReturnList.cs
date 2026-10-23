namespace ItemApi.Models
{
    // Return Items list on the new system (Docs/StockSystem.md §6.22, DBScript/Updates/U016_BackOffice_ReturnList.sql).
    // Items waiting to go back to a supplier; Process makes a PRN of the Ready rows of one supplier.

    // z_sp_GetReturnList: one row with the item, supplier and stock now
    public class ReturnListRow
    {
        public int ReturnId { get; set; }
        public int LocationId { get; set; }
        public int ItemId { get; set; }
        public string? Barcode { get; set; }
        public string? RefCode { get; set; }
        public string? Descrip { get; set; }
        public int SuppId { get; set; }
        public string? SuppCode { get; set; }
        public string? SuppName { get; set; }
        public decimal Qty { get; set; }
        public decimal? CostPrice { get; set; }
        public decimal? SellPrice { get; set; }
        // Qty x CostPrice
        public decimal Amount { get; set; }
        public decimal StockQty { get; set; }
        public string? Reason { get; set; }
        public string? Remark { get; set; }
        // 1 Added, 2 Ready, 3 PRN made
        public byte Status { get; set; }
        public string? StatusText { get; set; }
        public string? PrnNo { get; set; }
        // 1 mobile app, 2 back office
        public byte Source { get; set; }
        public string? UserId { get; set; }
        public DateTime CDate { get; set; }
        public DateTime? UDate { get; set; }
    }

    // POST api/ReturnList: a scanned item (the same item + supplier still "Added" gets the qty added)
    public class ReturnListAddRequest
    {
        public int ItemId { get; set; }
        public int SuppId { get; set; }
        public decimal Qty { get; set; }
        public string? Reason { get; set; }
        public string? Remark { get; set; }
        // 1 mobile app, 2 back office
        public byte Source { get; set; } = 2;
        public string? UserId { get; set; }
        public int? LocationId { get; set; }
    }

    // PUT api/ReturnList/{id}
    public class ReturnListUpdateRequest
    {
        public decimal Qty { get; set; }
        public int SuppId { get; set; }
        public string? Reason { get; set; }
        public string? Remark { get; set; }
        public string? UserId { get; set; }
    }

    // POST api/ReturnList/status (Status 1 Added / 2 Ready) and api/ReturnList/delete
    public class ReturnListIdsRequest
    {
        public List<int> Ids { get; set; } = new();
        public int Status { get; set; }
        public string? UserId { get; set; }
    }

    // POST api/ReturnList/process: Ready rows of one supplier -> a PRN (Post = also take them off stock now)
    public class ReturnListProcessRequest
    {
        public List<int> Ids { get; set; } = new();
        public string? UserId { get; set; }
        public bool Post { get; set; } = true;
        public string? RefNo { get; set; }
        public string? Remark { get; set; }
        // print the return slip on the receipt printer afterwards
        public bool Print { get; set; }
    }

    // z_sp_ReturnListToPrn
    public class ReturnListPrnResult
    {
        public string PrnNo { get; set; } = "";
        public int Lines { get; set; }
        public decimal Qty { get; set; }
        public decimal Amount { get; set; }
        public bool Posted { get; set; }
    }

    // GET api/ReturnList/Lookup?code=: a scanned / typed code -> the item(s) with cost, price, stock and supplier
    public class ReturnListLookupRow
    {
        public int ItemId { get; set; }
        public string? Barcode { get; set; }
        public string? RefCode { get; set; }
        public string? Descrip { get; set; }
        public decimal? CostPrice { get; set; }
        public decimal? RetailPrice { get; set; }
        public decimal StockQty { get; set; }
        // the item's own supplier (null = pick one on the screen)
        public int? SuppId { get; set; }
    }
}
