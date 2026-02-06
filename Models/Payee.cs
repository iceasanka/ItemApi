using System.Text.Json.Serialization;

namespace ItemApi.Models
{
    public class Payee
    {
        [JsonPropertyName("payeeId")]
        public int PayeeId { get; set; }

        [JsonPropertyName("payeeName")]
        public string PayeeName { get; set; }
        [JsonPropertyName("supplierName")]
        public string SupplierName { get; set; }
        [JsonPropertyName("isActive")]
        public bool IsActive { get; set; }
    }
}
