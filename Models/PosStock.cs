using System.ComponentModel.DataAnnotations.Schema;
using System.ComponentModel.DataAnnotations;

namespace ItemApi.Models
{
    public class PosStock
    {
        [Key]
        [DatabaseGenerated(DatabaseGeneratedOption.Identity)]
        public int Idx { get; set; }

        public string ItemCode { get; set; }

        public string RefCode { get; set; }

        public string Loca { get; set; }

        public string Receipt { get; set; }

        public string Unit { get; set; }

        public DateTime? SDate { get; set; }

        public int? PriceLevel { get; set; }

        public double Qty { get; set; }

        public decimal Price { get; set; }

        public double Amount { get; set; }

        public string Iid { get; set; }

        public int Online { get; set; }
    }
}
