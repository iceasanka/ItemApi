namespace ItemApi.Models
{
    public class ChequeCreate
    {
        public int ChequeId { get; set; }
        public decimal Amount { get; set; }

        public DateTime ChequeDate { get; set; }

        public int PayeeId { get; set; }

        public string SupplierName { get; set; }
    }
}
