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

        [JsonPropertyName("chequeWrittenDate")]
        public DateTime ChequeWrittenDate { get; set; } = DateTime.Now;

        public int PayeeId { get; set; }

        [JsonPropertyName("supplierName")]
        public string SupplierName { get; set; }


        /// <summary>
        /// 1=sync, 0=not sync
        /// </summary>
        [JsonPropertyName("isSync")]
        public int IsSync { get; set; }

        /// <summary>
        /// 1=Debited, 0=not Debited
        /// </summary>
        [JsonPropertyName("isDebited")]
        public int IsDebited { get; set; }
    }
}
