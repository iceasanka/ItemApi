using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace ItemApi.Models
{
    public class SubCategory
    {
        [Key]
        public int SubCatId { get; set; }

        [Required]
        [MaxLength(10)]
        public string SubCatCode { get; set; }

        [MaxLength(50)]
        public string? SubCatName { get; set; }

        [Column(TypeName = "decimal(12,2)")]
        public decimal? SubCatRate { get; set; }

        public int CatId { get; set; }
    }
}
