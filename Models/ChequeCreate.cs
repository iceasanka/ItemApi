using System.ComponentModel.DataAnnotations;
using System.Text.Json.Serialization;

namespace ItemApi.Models
{
    public class ChequeCreate
    {
        [JsonPropertyName("chequeId")]
        [Key]
        public int ChequeId { get; set; }

        [JsonPropertyName("amount")]
        public decimal Amount { get; set; }

        [JsonPropertyName("chequeNumber")]
        public int ChequeNumber { get; set; }

        [JsonPropertyName("chequeDate")]
        public DateTime ChequeDate { get; set; }

        public int PayeeId { get; set; }

        [JsonPropertyName("supplierName")]
        public string SupplierName { get; set; }
    }
}
