using System.ComponentModel.DataAnnotations;
using System.Text.Json.Serialization;

namespace ItemApi.Models
{
    public class SalaryHoliday
    {
        [Key]
        [JsonPropertyName("holidayId")]
        public int HolidayId { get; set; }

        [JsonPropertyName("holidayDate")]
        public DateTime HolidayDate { get; set; }

        [JsonPropertyName("description")]
        public string? Description { get; set; }

        [JsonPropertyName("createdDate")]
        public DateTime CreatedDate { get; set; } = DateTime.Now;
    }
}
