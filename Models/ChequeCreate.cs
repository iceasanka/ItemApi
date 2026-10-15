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

        // old payee list (z_tb_Payee); cheques written for a supplier have SuppId instead
        [JsonPropertyName("payeeId")]
        public int? PayeeId { get; set; }

        [JsonPropertyName("supplierName")]
        public string SupplierName { get; set; }

        [JsonPropertyName("suppId")]
        public int? SuppId { get; set; }

        // the PAYMENT row this cheque made in z_tb_SupplierLedger (z_sp_LinkWrittenCheque)
        [JsonPropertyName("ledgerId")]
        public int? LedgerId { get; set; }

        // the name printed on the cheque
        [JsonPropertyName("payeeName")]
        public string? PayeeName { get; set; }


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
