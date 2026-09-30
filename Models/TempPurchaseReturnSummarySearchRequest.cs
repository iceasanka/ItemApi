namespace ItemApi.Models
{
    public class TempPurchaseReturnSummarySearchRequest
    {
        public string? PrnNo { get; set; }
        public string? RefNo { get; set; }

        public string? Remark { get; set; }
        public int? SuppId { get; set; }
    }
}
