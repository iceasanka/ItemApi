namespace ItemApi.Models
{
    // POST api/SlipPrint - a report the page built, printed on the bill printer (thermal) of Settings > Printers with
    // no print preview (Day Reports, Paid in / out, Z report "Print 80mm"). The server lays it out for the paper width.
    public class SlipPrintRequest
    {
        public string? DocName { get; set; }
        public List<SlipPrintItem> Items { get; set; } = new();
    }

    // Kind: "text" (Text, Align left / center / right, Bold, Tall), "blank", "divider" (Text = the character, default -),
    // "table" (Rows: cells; 2 cells = label + value, more = the first column + right-aligned columns)
    public class SlipPrintItem
    {
        public string Kind { get; set; } = "text";
        public string? Text { get; set; }
        public string? Align { get; set; }
        public bool Bold { get; set; }
        public bool Tall { get; set; }
        public List<SlipPrintRow>? Rows { get; set; }
    }

    public class SlipPrintRow
    {
        public List<string> Cells { get; set; } = new();
        public bool Bold { get; set; }
        public bool Head { get; set; }
    }
}
