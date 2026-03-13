using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace ItemApi.Models
{
    [Table("z_tb_System")]
    public class System
    {
        [Key]
        [DatabaseGenerated(DatabaseGeneratedOption.Identity)]
        public int Idx { get; set; }

        [Required]
        [MaxLength(5)]
        public string LocaId { get; set; }

        public int PNO { get; set; }

        public int PRNO { get; set; }
    }
}
