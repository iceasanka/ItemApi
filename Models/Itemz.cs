using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace ItemApi.Models
{
    [Table("z_tb_Item")]
    public class Itemz
    {
        [Key]
        [DatabaseGenerated(DatabaseGeneratedOption.Identity)]
        public int ItemId { get; set; }

        public string? RefCode { get; set; }
        public string? Barcode { get; set; }
        public string? Descrip { get; set; }
        public string? SinhalaDescrip { get; set; }
        public int? CatId { get; set; }
        public int? SubCatId { get; set; }
        public int? SupId { get; set; }
        public bool UseExp { get; set; } = false;

        public int Status { get; set; }
        public string? UserId { get; set; }

        public DateTime CDate { get; set; }
        public DateTime UDate { get; set; }
    }
}
