namespace ItemApi.Models
{
    public class TempPurchaseSummarySearchRequest
    {
        public string? GrnNo { get; set; }
        public string? RefNo { get; set; }

        public string? Remark { get; set; }
        public int? SuppId { get; set; }
    }
}
