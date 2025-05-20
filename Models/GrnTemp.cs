using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace ItemApi.Models
{
    public class GrnTemp
    {
        [Key]
        public int Id { get; set; }
        public string BarCode { get; set; }
        public string ItemCode { get; set; }
        public string ItemRefCode { get; set; }
        public string GrnReference { get; set; }
        public string Descrip { get; set; }
        public decimal? CostPrice { get; set; }
        public decimal? ERetPrice { get; set; }
        public double Qty { get; set; }
        public DateTime Date { get; set; }
        public int Status { get; set; }

        [NotMapped]
        public decimal? itemCostPrice { get; set; }
        [NotMapped]
        public decimal? itemERetPrice { get; set; }
    }
}
