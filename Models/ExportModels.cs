using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace ItemApi.Models
{
    // File exports to a folder (DBScript/05_BackOffice_Export.sql, api/Export). First export: SCALE.

    [Table("z_tb_ExportSetting")]
    public class ExportSetting
    {
        [Key]
        [MaxLength(20)]
        public string ExportCode { get; set; } = "";
        public string Name { get; set; } = "";
        // a folder on the API server (local drive or \\pc\share)
        public string? FolderPath { get; set; }
        public string FileName { get; set; } = "";
        // 0 = no limit; longer item names are cut
        public int NameMaxLength { get; set; }
        public DateTime? LastExportAt { get; set; }
        public int? LastExportBy { get; set; }
        public int? LastLineCount { get; set; }
        public int? UserId { get; set; }
        public DateTime UDate { get; set; }
    }

    [Table("z_tb_ExportLog")]
    public class ExportLog
    {
        [Key]
        [DatabaseGenerated(DatabaseGeneratedOption.Identity)]
        public int ExportLogId { get; set; }
        public string ExportCode { get; set; } = "";
        public string? FilePath { get; set; }
        public int LineCount { get; set; }
        public int SkippedCount { get; set; }
        // 1 written, 9 failed
        public int Status { get; set; }
        public string? Error { get; set; }
        public int? UserId { get; set; }
        public DateTime CDate { get; set; }
    }

    // What the last successful SCALE export sent
    [Table("z_tb_ScaleExportItem")]
    public class ScaleExportItem
    {
        [Key]
        [DatabaseGenerated(DatabaseGeneratedOption.None)]
        public int ItemId { get; set; }
        public string Plu { get; set; } = "";
        public string Descrip { get; set; } = "";
        [Column(TypeName = "decimal(18,2)")]
        public decimal Price { get; set; }
        public DateTime ExportedAt { get; set; }
    }

    // Raw row: an active item sold by KGS at the location
    public class ScaleItemSource
    {
        public int ItemId { get; set; }
        public string? RefCode { get; set; }
        public string? Descrip { get; set; }
        public decimal? RetailPrice { get; set; }
        public bool IsSaleLocked { get; set; }
    }

    public class ExportSettingUpdate
    {
        public string? FolderPath { get; set; }
        public string? FileName { get; set; }
        public int NameMaxLength { get; set; }
        public int? UserId { get; set; }
    }

    public class ExportRunRequest
    {
        public int? UserId { get; set; }
    }

    // Change: "same", "new", "changed"
    public class ScaleExportLine
    {
        public int ItemId { get; set; }
        public string? RefCode { get; set; }
        public string Plu { get; set; } = "";
        public string Descrip { get; set; } = "";
        public decimal Price { get; set; }
        public string Change { get; set; } = "same";
        public List<string> Changes { get; set; } = new();
        public string? Warning { get; set; }
    }

    public class ScaleExportSkipped
    {
        public int ItemId { get; set; }
        public string? RefCode { get; set; }
        public string? Descrip { get; set; }
        public decimal? Price { get; set; }
        public string Reason { get; set; } = "";
    }

    public class ScaleExportRemoved
    {
        public int ItemId { get; set; }
        public string Plu { get; set; } = "";
        public string Descrip { get; set; } = "";
        public decimal Price { get; set; }
    }

    public class ExportPreview
    {
        public ExportSetting Setting { get; set; } = new();
        public string? FilePath { get; set; }
        public List<ScaleExportLine> Lines { get; set; } = new();
        public List<ScaleExportSkipped> Skipped { get; set; } = new();
        public List<ScaleExportRemoved> Removed { get; set; } = new();
        public int NewCount { get; set; }
        public int ChangedCount { get; set; }
        public bool HasChanges { get; set; }
    }

    public class ExportResult
    {
        public string FilePath { get; set; } = "";
        public int LineCount { get; set; }
        public int SkippedCount { get; set; }
        public int NewCount { get; set; }
        public int ChangedCount { get; set; }
        public int RemovedCount { get; set; }
        public DateTime ExportedAt { get; set; }
    }

    // Business errors from the export (folder missing, no access, ...) → HTTP 400 { message }
    public class ExportException : Exception
    {
        public ExportException(string message) : base(message) { }
    }
}
