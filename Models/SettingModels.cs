namespace ItemApi.Models
{
    // Settings page (api/Settings, DBScript/24_BackOffice_Settings.sql). Docs/StockSystem.md §6.28.
    // A value for a user: their own value, else the general value (Value), else DefaultValue.
    public class SettingRow
    {
        public string SettingKey { get; set; } = "";
        public string GroupName { get; set; } = "";
        public string Label { get; set; } = "";
        public string? Descrip { get; set; }
        // 1 general only, 2 general + a user's own value
        public int Scope { get; set; }
        // "bool" ("0" / "1") or "choice" (Options = "<value>=<label>|...")
        public string ValueType { get; set; } = "";
        public string? Options { get; set; }
        public string DefaultValue { get; set; } = "";
        // null = DefaultValue
        public string? Value { get; set; }
        public string EffectiveValue { get; set; } = "";
        public DateTime? UpdatedAt { get; set; }
        public string? UpdatedByName { get; set; }
        // users with their own value
        public int UserValues { get; set; }
    }

    public class UserSettingValue
    {
        public int UserId { get; set; }
        public string SettingKey { get; set; } = "";
        public string Value { get; set; } = "";
        public DateTime UpdatedAt { get; set; }
        public string? UpdatedByName { get; set; }
    }

    // GET api/Settings/Users: the per-user settings and every user with their own values (key → value)
    public class UserSettingsList
    {
        public List<SettingRow> Settings { get; set; } = new();
        public List<UserSettingsRow> Users { get; set; } = new();
    }

    public class UserSettingsRow
    {
        public int UserId { get; set; }
        public string? LoginName { get; set; }
        public string? UserName { get; set; }
        public int? RoleId { get; set; }
        public int? Status { get; set; }
        public Dictionary<string, string> Values { get; set; } = new();
    }

    // PUT api/Settings/{key} and api/Settings/User/{userId}/{key} — value null = back to the default / general value
    public class SettingValueRequest
    {
        public string? Value { get; set; }
    }

    // Settings > Printers > Save (PUT api/Settings/Printers/{kind}, U051)
    public class PrinterSaveRequest
    {
        public int? Conn { get; set; }         // 1 Windows printer, 2 COM port, 3 network (general: 1 only)
        public string? Name { get; set; }      // Windows printer name
        public string? Port { get; set; }      // COM3
        public string? Address { get; set; }   // 192.168.1.50:9100
        public int? Baud { get; set; }         // 9600 ... 115200 (COM port)
        public string? Mode { get; set; }      // bill: driver | escpos (a Windows printer)
        public int? Width { get; set; }        // bill: 48 / 42 / 32 characters a line
    }

    // Settings > Printers > Test print: the printer as picked on the page; no Conn / Name / Printer = the saved one
    public class PrinterTestRequest : PrinterSaveRequest
    {
        public string? Kind { get; set; }      // bill | general | sticker
        public string? Printer { get; set; }   // old: the Windows printer name
    }

    // api/Sync/Settings → till zf_tb_Setting / zf_tb_UserSetting. LoginName null = the general value.
    public class SyncSetting
    {
        public string? LoginName { get; set; }
        public string SettingKey { get; set; } = "";
        public string? Value { get; set; }
    }
}
