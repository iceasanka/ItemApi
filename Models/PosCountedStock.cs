using System.ComponentModel.DataAnnotations;

namespace ItemApi.Models
{
    public class PosCountedStock
    {
        [Key]
        public string ItemCode { get; set; }

        public double Qty { get; set; }
    }
}
