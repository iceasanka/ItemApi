namespace ItemApi.Models
{
    public class CommitPurchaseItems
    {
        public string SerialNo { get; set; }
        public string RefNo { get; set; }
        public string RefNo2 { get; set; }
        public string PNDate { get; set; }
        public string SuppCode { get; set; }
        public string SuppName { get; set; }
        public string PODNo { get; set; }
        public int PType { get; set; }
        public int PMode { get; set; }
        public decimal GrossAmount { get; set; }
        public decimal TotDiscount { get; set; }
        public decimal SubTotDiscount { get; set; }
        public decimal Tax { get; set; }
        public decimal Advance { get; set; }

        public int AdvPMode { get; set; } // <-- NEW: matches @ADVPMODE
        public decimal RefAmount { get; set; } // <-- NEW: matches @REFAMOUNT
        public int Returns { get; set; } // <-- NEW: matches @RETURNS
        public int UpdPrice { get; set; } // <-- NEW: matches @UPDPRICE

        public decimal NetAmount { get; set; }
        public string UserName { get; set; }
        public string LocaCode { get; set; }
        public int Status { get; set; }
        public bool IsExp { get; set; }
        public decimal Nbt { get; set; }
        public string Disc { get; set; }

        public decimal RoundingDiff { get; set; } // <-- NEW: matches @RoundingDiff
    }
}
