using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;
using Microsoft.EntityFrameworkCore;

namespace ItemApi.Models
{

    [Table("tb_Item")]
    public class Item
    {
        [Key]
        public string Item_Code { get; set; }
        public string Ref_Code { get; set; }
        public string Barcode { get; set; }
        public string Inv_Descrip { get; set; }
        public string Descrip { get; set; }
        public string Cat_Code { get; set; }
        public string SubCat_Code { get; set; }

        public string Supp_Code { get; set; }
        public double Pack_Size { get; set; } // Change from float to double
        public string W_Margine { get; set; }
        public string R_Margine { get; set; }
        public string PUnit { get; set; }
        public string EUnit { get; set; }
        public decimal Tax1 { get; set; }
        public decimal MaxPrice { get; set; }
        public string Tax2 { get; set; }
        public string Tax3 { get; set; }
        public byte Countable { get; set; }
        public byte Use_Exp { get; set; }
        public decimal ConvertFact { get; set; }
        public string ConvertFactUnit { get; set; }

    }
}