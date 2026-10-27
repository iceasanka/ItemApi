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

    // api/Sync/Settings → till zf_tb_Setting / zf_tb_UserSetting. LoginName null = the general value.
    public class SyncSetting
    {
        public string? LoginName { get; set; }
        public string SettingKey { get; set; } = "";
        public string? Value { get; set; }
    }
}
