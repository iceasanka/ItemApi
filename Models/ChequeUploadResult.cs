using System.Text.Json.Serialization;

namespace ItemApi.Models
{
    /// <summary>
    /// One cheque line from the bank statement CSV and what the upload did with it.
    /// </summary>
    public class ChequeUploadRow
    {
        /// <summary>Line number in the uploaded file (1 = first line).</summary>
        [JsonPropertyName("lineNo")]
        public int LineNo { get; set; }

        /// <summary>First column of the bank line (the transaction date, as the bank wrote it).</summary>
        [JsonPropertyName("bankDate")]
        public string? BankDate { get; set; }

        [JsonPropertyName("chequeNumber")]
        public int ChequeNumber { get; set; }

        /// <summary>Debit amount on the bank statement.</summary>
        [JsonPropertyName("bankAmount")]
        public decimal BankAmount { get; set; }

        /// <summary>Amount in the database; null when the cheque is not in the database.</summary>
        [JsonPropertyName("dbAmount")]
        public decimal? DbAmount { get; set; }

        [JsonPropertyName("supplierName")]
        public string? SupplierName { get; set; }

        [JsonPropertyName("chequeDate")]
        public DateTime? ChequeDate { get; set; }

        /// <summary>Debited / NotFound / AmountMismatch / AlreadyDebited</summary>
        [JsonPropertyName("status")]
        public string Status { get; set; } = "";

        [JsonPropertyName("message")]
        public string Message { get; set; } = "";
    }

    public class ChequeUploadResult
    {
        [JsonPropertyName("fileName")]
        public string? FileName { get; set; }

        /// <summary>Cheque lines read from the file.</summary>
        [JsonPropertyName("totalRows")]
        public int TotalRows { get; set; }

        /// <summary>Found with the same amount and marked as debited by this upload.</summary>
        [JsonPropertyName("debited")]
        public List<ChequeUploadRow> Debited { get; set; } = new();

        /// <summary>Debited by the bank but not in the database — not updated.</summary>
        [JsonPropertyName("notFound")]
        public List<ChequeUploadRow> NotFound { get; set; } = new();

        /// <summary>In the database but the amount differs from the bank — not updated.</summary>
        [JsonPropertyName("amountMismatch")]
        public List<ChequeUploadRow> AmountMismatch { get; set; } = new();

        /// <summary>Already marked as debited by an earlier upload — nothing to do.</summary>
        [JsonPropertyName("alreadyDebited")]
        public List<ChequeUploadRow> AlreadyDebited { get; set; } = new();

        /// <summary>NotFound + AmountMismatch: debited by the bank but not updated in the database.</summary>
        [JsonPropertyName("notUpdated")]
        public List<ChequeUploadRow> NotUpdated => NotFound.Concat(AmountMismatch).OrderBy(r => r.LineNo).ToList();
    }
}
