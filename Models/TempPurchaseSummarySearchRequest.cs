namespace ItemApi.Models
{
    public class TempPurchaseSummarySearchRequest
    {
        public string? GrnNo { get; set; }
        public string? SuppCode { get; set; }
        public string? POderNo { get; set; }
        public DateTime? PDateFrom { get; set; }
        public DateTime? PDateTo { get; set; }
        public string? Remark { get; set; }
    }
}
