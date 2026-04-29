namespace ItemApi.Models
{
    public class SupplierLedgerSearchRequest
    {
        public int SuppId { get; set; }
        public DateTime? FromDate { get; set; }
        public DateTime? ToDate { get; set; }
    }
}
