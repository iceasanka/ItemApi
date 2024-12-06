
using System.ComponentModel.DataAnnotations.Schema;
using Microsoft.EntityFrameworkCore;

namespace ItemApi.Models
{

    [Keyless]
    [Table("tb_ItemDet")]
    public class ItemDetail
    {
        public string Item_Code { get; set; }
        public string Loca_Code { get; set; }
        public decimal? PRet_Price { get; set; }
        public decimal? PWhole_Price { get; set; }
        public decimal? PSp_Price { get; set; }
        public decimal? ERet_Price { get; set; }
        public decimal? EWhole_Price { get; set; }
        public decimal? ESp_Price { get; set; }
        public decimal? Cost_Price { get; set; }
        public decimal? AvgCost { get; set; }
        public string Cost_Code { get; set; }
        public bool Lock_S { get; set; }
        public bool Lock_P { get; set; }
        public bool NoDiscount { get; set; }
        public float Re_Qty { get; set; }
        public float Rol { get; set; }
        public float? Qty { get; set; }
        public string User_Id { get; set; }
        public string BinNo { get; set; }
        public String PackScale { get; set; }
    }

}