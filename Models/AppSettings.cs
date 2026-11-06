namespace ItemApi.Models
{
    // The printers are not here any more: Settings > Printers (z_tb_Setting Printer.*, U050 - Service/PrinterConfig.cs).
    public class AppSettings
    {
        public string Apicre { get; set; }

        // Hard-coded location (appsettings.json) until the user table is implemented
        public int LocationId { get; set; } = 1;
    }
}
