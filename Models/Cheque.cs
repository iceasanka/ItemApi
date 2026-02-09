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
        public int payeeId { get; set; }

        [JsonPropertyName("supplierName")]
        public string supplierName { get; set; }

        [JsonPropertyName("chequeNumber")]
        public int chequeNumber { get; set; }
    }
}
