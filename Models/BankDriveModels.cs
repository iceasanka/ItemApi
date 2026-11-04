using System.Text.Json.Serialization;

namespace ItemApi.Models
{
    /// <summary>A bank statement file waiting in Google Drive (BankTransactionFiles).</summary>
    public class BankDriveFile
    {
        [JsonPropertyName("id")] public string Id { get; set; } = "";
        [JsonPropertyName("name")] public string Name { get; set; } = "";
        [JsonPropertyName("size")] public long? Size { get; set; }
        [JsonPropertyName("mimeType")] public string? MimeType { get; set; }
        [JsonPropertyName("modified")] public DateTime? Modified { get; set; }
    }

    public class BankDriveProcessRequest
    {
        [JsonPropertyName("fileIds")] public List<string> FileIds { get; set; } = new();
    }

    /// <summary>What processing one Drive file did.</summary>
    public class BankDriveFileResult
    {
        [JsonPropertyName("fileId")] public string FileId { get; set; } = "";
        [JsonPropertyName("name")] public string? Name { get; set; }
        [JsonPropertyName("ok")] public bool Ok { get; set; }
        /// <summary>deleted / moved (to BankTransactionFiles/Processed) / kept (not processed, or could not be removed)</summary>
        [JsonPropertyName("removed")] public string Removed { get; set; } = "kept";
        [JsonPropertyName("message")] public string? Message { get; set; }
        [JsonPropertyName("result")] public ChequeUploadResult? Result { get; set; }
    }
}
