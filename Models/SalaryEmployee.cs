using System.ComponentModel.DataAnnotations;
using System.Text.Json.Serialization;

namespace ItemApi.Models
{
    public class SalaryEmployee
    {
        [Key]
        [JsonPropertyName("employeeId")]
        public int EmployeeId { get; set; }

        [JsonPropertyName("employeeName")]
        public string EmployeeName { get; set; }

        [JsonPropertyName("joinDate")]
        public DateTime JoinDate { get; set; }

        /// <summary>
        /// "Active" or "Inactive". Deactivating an employee is a soft delete.
        /// </summary>
        [JsonPropertyName("status")]
        public string Status { get; set; } = "Active";

        // Per-employee overrides. Null = fall back to the global SalaryConfig value.
        [JsonPropertyName("basicOverride")]
        public decimal? BasicOverride { get; set; }

        [JsonPropertyName("byShopOverride")]
        public decimal? ByShopOverride { get; set; }

        [JsonPropertyName("attendanceBonusOverride")]
        public decimal? AttendanceBonusOverride { get; set; }

        [JsonPropertyName("otRateOverride")]
        public decimal? OtRateOverride { get; set; }

        [JsonPropertyName("mhPayOverride")]
        public decimal? MhPayOverride { get; set; }

        [JsonPropertyName("mhOtRateOverride")]
        public decimal? MhOtRateOverride { get; set; }

        [JsonPropertyName("targetBonusOverride")]
        public decimal? TargetBonusOverride { get; set; }

        [JsonPropertyName("isTargetBonusEnabledOverride")]
        public bool? IsTargetBonusEnabledOverride { get; set; }

        [JsonPropertyName("createdDate")]
        public DateTime CreatedDate { get; set; } = DateTime.Now;
    }
}
