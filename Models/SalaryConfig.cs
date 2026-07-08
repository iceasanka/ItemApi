using System.ComponentModel.DataAnnotations;
using System.Text.Json.Serialization;

namespace ItemApi.Models
{
    public class SalaryConfig
    {
        [Key]
        [JsonPropertyName("configId")]
        public int ConfigId { get; set; }

        [JsonPropertyName("basicSalary")]
        public decimal BasicSalary { get; set; }

        [JsonPropertyName("byShop")]
        public decimal ByShop { get; set; }

        [JsonPropertyName("attendanceBonus")]
        public decimal AttendanceBonus { get; set; }

        [JsonPropertyName("otRate")]
        public decimal OtRate { get; set; }

        [JsonPropertyName("mhPay")]
        public decimal MhPay { get; set; }

        [JsonPropertyName("mhOtRate")]
        public decimal MhOtRate { get; set; }

        [JsonPropertyName("targetBonus")]
        public decimal TargetBonus { get; set; }

        [JsonPropertyName("isTargetBonusEnabled")]
        public bool IsTargetBonusEnabled { get; set; }

        [JsonPropertyName("modifiedDate")]
        public DateTime ModifiedDate { get; set; } = DateTime.Now;
    }
}
