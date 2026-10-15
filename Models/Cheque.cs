using System.Text.Json.Serialization;

namespace ItemApi.Models
{
    public class Cheque
    {
        [JsonPropertyName("amount")]
        public decimal amount { get; set; }

        [JsonPropertyName("amountInWords")]
        public string amountInWords { get; set; }

        [JsonPropertyName("chequeDate")]
        public DateTime chequeDate { get; set; }

        [JsonPropertyName("payee")]
        public string payee { get; set; }

        public string? printerName { get; set; }

        public string? printTemplatePath { get; set; }

        public int printType { get; set; }

        [JsonPropertyName("payeeId")]
        public int? payeeId { get; set; }

        // supplier (z_tb_Supplier): the cheque is added to the supplier ledger as a PAYMENT
        [JsonPropertyName("suppId")]
        public int? suppId { get; set; }

        // the bills (supplier ledger PURCHASE rows) this cheque pays
        [JsonPropertyName("allocations")]
        public List<SupplierAllocation>? allocations { get; set; }

        [JsonPropertyName("supplierName")]
        public string supplierName { get; set; }

        [JsonPropertyName("chequeNumber")]
        public int chequeNumber { get; set; }

        // why the picked bills cannot go with this cheque (null = fine) — AddCheque and printCheque
        public string? BillsError()
        {
            if ((allocations?.Count ?? 0) > 0 && (suppId ?? 0) <= 0)
                return "Pick the supplier for the bills this cheque pays.";
            if (allocations != null && allocations.GroupBy(a => a.LedgerId).Any(g => g.Count() > 1))
                return "A bill is picked twice.";
            return null;
        }
    }
}
