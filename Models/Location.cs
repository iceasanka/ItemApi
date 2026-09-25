using System.ComponentModel.DataAnnotations;

namespace ItemApi.Models
{
    public class Location
    {
        [Key]
        public int LocationId { get; set; }
        public string LocationCode { get; set; }
        public string? LocationName { get; set; }
    }
}
