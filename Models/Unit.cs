using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace ItemApi.Models
{
    [Table("z_tb_Unit")]
    public class Unit
    {
        [Key]
        [DatabaseGenerated(DatabaseGeneratedOption.Identity)]
        public int UnitId { get; set; }

        [MaxLength(5)]
        public string UnitCode { get; set; }

        [MaxLength(30)]
        public string? Description { get; set; }

        public DateTime? CDate { get; set; }

        public int? UserId { get; set; }

        public int IsDefault { get; set; }
    }
}
