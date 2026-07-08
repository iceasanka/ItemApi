using System.ComponentModel.DataAnnotations;
using System.Text.Json.Serialization;

namespace ItemApi.Models
{
    public class SalaryAttendance
    {
        [Key]
        [JsonPropertyName("attendanceId")]
        public int AttendanceId { get; set; }

        [JsonPropertyName("employeeId")]
        public int EmployeeId { get; set; }

        [JsonPropertyName("attendanceDate")]
        public DateTime AttendanceDate { get; set; }

        [JsonPropertyName("isPresent")]
        public bool IsPresent { get; set; }

        [JsonPropertyName("otHours")]
        public decimal OtHours { get; set; }

        [JsonPropertyName("isMercantileHoliday")]
        public bool IsMercantileHoliday { get; set; }

        [JsonPropertyName("createdDate")]
        public DateTime CreatedDate { get; set; } = DateTime.Now;
    }
}
