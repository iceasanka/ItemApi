using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;
using System.Text.Json.Serialization;
using ItemApi.Common;

namespace ItemApi.Models
{
    // Barcode labels printed straight to the Zebra as ZPL (DBScript/16_BackOffice_LabelLayout.sql, api/Label).
    // The old BarTender barcode print (api/Util/printbarcode) is separate and unchanged. StockSystem.md §6.20.

    // One sticker roll / sheet. Sizes in mm; LabelWidthMm / LabelHeightMm are ONE label.
    [Table("z_tb_LabelLayout")]
    public class LabelLayout
    {
        public const int Barcode = 1;
        public const int Price = 2;

        [Key]
        [DatabaseGenerated(DatabaseGeneratedOption.Identity)]
        public int LabelLayoutId { get; set; }
        // 1 barcode label (ZPL to the Zebra), 2 price label (drawn, through the Windows printer driver)
        public int LabelKind { get; set; } = Barcode;
        public string Name { get; set; } = "";
        // Windows printer on the API server; empty = PrinterAddress, then AppSettings:PrinterZebra (price: PrinterName)
        public string? PrinterName { get; set; }
        // network printer "ip:9100"
        public string? PrinterAddress { get; set; }
        public int Dpi { get; set; } = 203;
        [Column(TypeName = "decimal(6,2)")]
        public decimal LabelWidthMm { get; set; }
        [Column(TypeName = "decimal(6,2)")]
        public decimal LabelHeightMm { get; set; }
        public int LabelsAcross { get; set; } = 1;
        // rows on one page: 1 for a roll, more for a sheet
        public int RowsPerPage { get; set; } = 1;
        [Column(TypeName = "decimal(6,2)")]
        public decimal GapXMm { get; set; }
        [Column(TypeName = "decimal(6,2)")]
        public decimal GapYMm { get; set; }
        [Column(TypeName = "decimal(6,2)")]
        public decimal MarginLeftMm { get; set; }
        [Column(TypeName = "decimal(6,2)")]
        public decimal MarginTopMm { get; set; }
        // AUTO (EAN13 for a valid 13 digit barcode, otherwise CODE128), CODE128, EAN13
        public string BarcodeType { get; set; } = "AUTO";
        // 0 = fit the label
        [Column(TypeName = "decimal(6,2)")]
        public decimal BarcodeHeightMm { get; set; }
        public bool ShowName { get; set; } = true;
        public bool ShowPrice { get; set; } = true;
        public bool ShowItemCode { get; set; }
        public bool ShowDates { get; set; }
        // 0-30, null = the printer's own setting
        public int? Darkness { get; set; }
        // price labels: 1 English, 2 Sinhala, 3 both names
        public int Language { get; set; } = 1;
        // price labels: the label is turned 90° (landscape — the text runs along the paper)
        public bool Rotate { get; set; }
        // price labels: null = Iskoola Pota / Courier New
        public string? SinhalaFont { get; set; }
        public string? EnglishFont { get; set; }
        // price labels: a line on labels without a discount (shop slogan)
        public string? FooterText { get; set; }
        // one default per LabelKind
        public bool IsDefault { get; set; }
        // 1 active, 0 deleted
        public int Status { get; set; } = 1;
        [JsonConverter(typeof(LenientUserIdConverter))]
        public int? UserId { get; set; }
        public DateTime CDate { get; set; }
        public DateTime UDate { get; set; }
    }

    // POST api/Label/Print and api/Label/Zpl
    public class LabelPrintRequest
    {
        // null = the default layout
        public int? LabelLayoutId { get; set; }
        public List<LabelPrintLine> Items { get; set; } = new();
        // labels to leave empty at the start of the first page (a sheet that is partly used)
        public int Skip { get; set; }
        [JsonConverter(typeof(LenientUserIdConverter))]
        public int? UserId { get; set; }
    }

    public class LabelPrintLine
    {
        public int ItemId { get; set; }
        // how many labels of this item
        public int Qty { get; set; } = 1;
        // null = the item's retail price at this location (send a price link's price to print that one)
        public decimal? Price { get; set; }
        public DateTime? MfdDate { get; set; }
        public DateTime? ExpDate { get; set; }
    }

    public class LabelPrintResult
    {
        public int Labels { get; set; }
        public int Pages { get; set; }
        public string Printer { get; set; } = "";
        public string LayoutName { get; set; } = "";
    }

    // What one label shows, after the item was read
    public class LabelData
    {
        public string Name { get; set; } = "";
        public string Barcode { get; set; } = "";
        public string ItemCode { get; set; } = "";
        public decimal? Price { get; set; }
        public DateTime? MfdDate { get; set; }
        public DateTime? ExpDate { get; set; }
    }

    // POST api/Label/Price/Print and api/Label/Price/Preview. Replaces the old printprice / printDiscountPrice /
    // printitempricelandscape (one item, one copy, BarTender): many items, copies, any layout.
    public class PriceLabelRequest
    {
        // null = the default price layout
        public int? LabelLayoutId { get; set; }
        // null = the layout's; 1 English, 2 Sinhala, 3 both (the old page's "Sinhala" tick = 2)
        public int? Language { get; set; }
        public List<PriceLabelLine> Items { get; set; } = new();
        public int Skip { get; set; }
        [JsonConverter(typeof(LenientUserIdConverter))]
        public int? UserId { get; set; }
    }

    public class PriceLabelLine
    {
        public int ItemId { get; set; }
        public int Qty { get; set; } = 1;
        // AUTO (discount label when the item / line has a discount, else price), PRICE, DISCOUNT
        public string Style { get; set; } = "AUTO";
        // the page may change these before printing (as the old page did); null = from the item
        public decimal? Price { get; set; }
        public decimal? DiscountAmount { get; set; }
        public decimal? DiscountPercent { get; set; }
        public string? Name { get; set; }
        public string? SinhalaName { get; set; }
    }

    // What one price label shows
    public class PriceLabelData
    {
        public string ItemCode { get; set; } = "";
        public string Name { get; set; } = "";
        public string SinhalaName { get; set; } = "";
        public decimal Price { get; set; }
        // set = "Save Rs x" + "Now Rs y"
        public decimal? DiscountAmount { get; set; }
        // set = "Save x%" (no price — as the old DiscountPercentagePrint label)
        public decimal? DiscountPercent { get; set; }
    }

    // A wrong layout / request: 400 with the message
    public class LabelException : Exception
    {
        public LabelException(string message) : base(message) { }
    }
}
