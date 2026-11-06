using System.Text.Json.Serialization;

namespace ItemApi.Models
{
    // Where each part of the cheque prints (Service/ChequePrinter.cs, z_tb_ChequeLayout, U049). All in mm.
    // Positions are on the CHEQUE as you read it: X from its left edge, Y from its top edge, to the top-left of the
    // text (the top of the capital letters). The date digits: X = the centre of each box.
    // Defaults = the old BarTender ChqPrint.btw: a 3.5 x 7 inch page (88.9 x 177.8 mm) fed short edge first, the text
    // turned 90 degrees (reads from the bottom of the page up), Arial about 11 pt. Measured from the template itself.
    public class ChequeLayout
    {
        // the cheque (landscape, as you read it)
        public decimal ChequeWidthMm { get; set; } = 177.8m;
        public decimal ChequeHeightMm { get; set; } = 88.9m;

        // how it goes into the printer: 90 = page portrait, cheque short edge first, text reads bottom to top (as the
        // old template); 270 = the other way round; 0 = page landscape (page = cheque)
        public int Rotation { get; set; } = 90;

        // the whole print moved on the cheque (+X = right, +Y = down) - to correct the printer, not single parts
        public decimal OffsetXMm { get; set; }
        public decimal OffsetYMm { get; set; }

        public string FontName { get; set; } = "Arial";
        public bool Bold { get; set; }

        public ChequeTextField Payee { get; set; } = new() { X = 15.5m, Y = 20.4m, FontPt = 11, MaxWidthMm = 145 };

        // amount in words: line 1, and line 2 when it does not fit on line 1
        public ChequeTextField Words { get; set; } = new() { X = 20.2m, Y = 30.6m, FontPt = 11, MaxWidthMm = 145 };
        public ChequeTextField Words2 { get; set; } = new() { X = 10m, Y = 38.6m, FontPt = 11, MaxWidthMm = 105 };

        public ChequeTextField Amount { get; set; } = new() { X = 123.2m, Y = 38.6m, FontPt = 11, MaxWidthMm = 48 };
        // .NET number format of the amount in figures ("0.00" = the old template: 125000.00; "#,##0.00" = 125,000.00)
        public string AmountFormat { get; set; } = "0.00";
        public string AmountPrefix { get; set; } = "";
        public string AmountSuffix { get; set; } = "";

        // date: D D M M Y Y (the year's last two digits - "20" is printed on the cheque)
        public decimal DateY { get; set; } = 8.6m;
        public decimal DateFontPt { get; set; } = 11;
        public decimal[] DateDigitX { get; set; } = { 124.3m, 130.2m, 136.1m, 143.2m, 160.7m, 167.7m };

        // "A/C Payee Only" crossing (when ticked on the cheque): two slanting lines with the words between them, in
        // the top-left corner. X / Y = the centre of the crossing.
        public decimal AcPayeeX { get; set; } = 22m;
        public decimal AcPayeeY { get; set; } = 10m;
        public decimal AcPayeeFontPt { get; set; } = 8;

        [JsonIgnore]
        public decimal PageWidthMm => Rotation is 90 or 270 ? ChequeHeightMm : ChequeWidthMm;
        [JsonIgnore]
        public decimal PageHeightMm => Rotation is 90 or 270 ? ChequeWidthMm : ChequeHeightMm;

        // why this layout cannot be used (null = fine)
        public string? Error()
        {
            if (ChequeWidthMm is < 100 or > 250 || ChequeHeightMm is < 50 or > 120) return "Check the cheque size (mm).";
            if (Rotation is not (0 or 90 or 270)) return "Rotation must be 0, 90 or 270.";
            if (Math.Abs(OffsetXMm) > 20 || Math.Abs(OffsetYMm) > 20) return "The printer shift is more than 20 mm.";
            if (string.IsNullOrWhiteSpace(FontName) || FontName.Length > 50) return "Enter the font.";
            if (DateDigitX == null || DateDigitX.Length != 6) return "Six date digit positions are needed (D D M M Y Y).";
            if (DateFontPt is < 6 or > 24) return "Date font: 6 to 24 pt.";
            if (AcPayeeFontPt is < 6 or > 24) return "A/C Payee font: 6 to 24 pt.";
            if (AcPayeeX < 0 || AcPayeeY < 0 || AcPayeeX > ChequeWidthMm || AcPayeeY > ChequeHeightMm) return "A/C Payee is off the cheque.";
            foreach (var (name, f) in Fields())
            {
                if (f.FontPt is < 6 or > 24) return $"{name}: font 6 to 24 pt.";
                if (f.MaxWidthMm is < 10 or > 240) return $"{name}: width 10 to 240 mm.";
            }
            var all = Fields().SelectMany(p => new[] { (p.Name, p.Field.X, p.Field.Y), (p.Name, p.Field.X + p.Field.MaxWidthMm, p.Field.Y) })
                .Concat(DateDigitX.Select(x => ("Date", x, DateY)));
            foreach (var (name, x, y) in all)
                if (x < 0 || y < 0 || x > ChequeWidthMm || y > ChequeHeightMm) return $"{name} is off the cheque.";
            try { _ = 1m.ToString(AmountFormat); } catch { return "The amount format is not valid."; }
            if (AmountPrefix.Length > 5 || AmountSuffix.Length > 5) return "The amount prefix / suffix is too long.";
            return null;
        }

        public IEnumerable<(string Name, ChequeTextField Field)> Fields()
        {
            yield return ("Payee", Payee);
            yield return ("Amount in words", Words);
            yield return ("Amount in words line 2", Words2);
            yield return ("Amount", Amount);
        }
    }

    public class ChequeTextField
    {
        public decimal X { get; set; }
        public decimal Y { get; set; }
        public decimal FontPt { get; set; } = 11;
        public decimal MaxWidthMm { get; set; } = 100;
    }

    // what goes on the cheque (preview, test print, reprint)
    public class ChequePrintData
    {
        public string Payee { get; set; } = "";
        public decimal Amount { get; set; }
        public string AmountInWords { get; set; } = "";
        public DateTime ChequeDate { get; set; }
        public bool AcPayee { get; set; }   // print "A/C Payee Only" (crossed cheque); default no
    }

    public class ChequePreviewRequest : ChequePrintData
    {
        public ChequeLayout? Layout { get; set; }   // a layout being edited (not saved yet); null = the saved one
    }

    public class ChequeLayoutInfo
    {
        public ChequeLayout Layout { get; set; } = new();
        public bool Saved { get; set; }              // false = the built-in defaults (never adjusted)
        public bool HasPrevious { get; set; }
        public DateTime? UpdatedAt { get; set; }
        public string? UpdatedBy { get; set; }
        public string Printer { get; set; } = "";
    }
}
