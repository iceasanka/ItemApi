using System.ComponentModel.DataAnnotations;

namespace ItemApi.Models
{
    public class Category
    {
        [Key]
        public int CatId { get; set; }
        public string CatCode { get; set; }
        public string? CatName { get; set; }
        public decimal? CatRate { get; set; }
    }
}
