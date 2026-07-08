using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;
using System.Text.Json.Serialization;

namespace ItemApi.Models
{
    public class SalaryPayslip
    {
        [Key]
        [JsonPropertyName("payslipId")]
        public int PayslipId { get; set; }

        [JsonPropertyName("employeeId")]
        public int EmployeeId { get; set; }

        [JsonPropertyName("employeeName")]
        [NotMapped]
        public string? EmployeeName { get; set; }

        [JsonPropertyName("payMonth")]
        public int PayMonth { get; set; }

        [JsonPropertyName("payYear")]
        public int PayYear { get; set; }

        [JsonPropertyName("totalDaysInMonth")]
        public int TotalDaysInMonth { get; set; }

        [JsonPropertyName("daysPresent")]
        public int DaysPresent { get; set; }

        [JsonPropertyName("basicEarned")]
        public decimal BasicEarned { get; set; }

        [JsonPropertyName("otHours")]
        public decimal OtHours { get; set; }

        [JsonPropertyName("otAmount")]
        public decimal OtAmount { get; set; }

        [JsonPropertyName("byShop")]
        public decimal ByShop { get; set; }

        [JsonPropertyName("attendanceBonus")]
        public decimal AttendanceBonus { get; set; }

        [JsonPropertyName("mhCount")]
        public int MhCount { get; set; }

        [JsonPropertyName("mhAmount")]
        public decimal MhAmount { get; set; }

        [JsonPropertyName("mhOtHours")]
        public decimal MhOtHours { get; set; }

        [JsonPropertyName("mhOtAmount")]
        public decimal MhOtAmount { get; set; }

        [JsonPropertyName("targetBonus")]
        public decimal TargetBonus { get; set; }

        [JsonPropertyName("advanceDeduction")]
        public decimal AdvanceDeduction { get; set; }

        [JsonPropertyName("netSalary")]
        public decimal NetSalary { get; set; }

        /// <summary>
        /// "Draft" or "Final".
        /// </summary>
        [JsonPropertyName("status")]
        public string Status { get; set; } = "Draft";

        [JsonPropertyName("generatedDate")]
        public DateTime GeneratedDate { get; set; } = DateTime.Now;
    }
}
