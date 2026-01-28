namespace ItemApi.Models
{
    public class ItemWithDetails
    {
        public string Item_Code { get; set; }
        public string Ref_Code { get; set; }
        public string Barcode { get; set; }
        public string Descrip { get; set; }

        public string SinhalaDescrip { get; set; }
        public string Supp_Code { get; set; }
        public double Pack_Size { get; set; }
        public decimal Tax1 { get; set; }
        public string Tax2 { get; set; }//Discount percentage 
        public string Tax3 { get; set; }//Discount
        public string PackScale { get; set; }
        public string Loca_Code { get; set; }
        public decimal ERet_Price { get; set; }
        public decimal Cost_Price { get; set; }
        public string PUnit { get; set; }
        public string EUnit { get; set; }

    }

}