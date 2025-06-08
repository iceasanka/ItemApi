using System.ComponentModel.DataAnnotations;

namespace ItemApi.Models
{
    public class UpdateItemSp
    {
      
        public string ItemCode { get; set; }

        public string refCode { get; set; }

        public string barCode { get; set; }

        public string invDescription { get; set; }

        public string description { get; set; }

        public string sinhalaDescription { get; set; }

        public string catCode { get; set; }

        public string catName { get; set; }

        public string subCatCode { get; set; }

        public string subCatName { get; set; }

        public string l1Code { get; set; }

        public string l2Code { get; set; }

        public string l3Code { get; set; }

        public string l4Code { get; set; }

        public string l5Code { get; set; }

        public string l6Code { get; set; }

        public string l7Code { get; set; }

        public string l1Name { get; set; }

        public string l2Name { get; set; }

        public string l3Name { get; set; }

        public string l4Name { get; set; }

        public string l5Name { get; set; }

        public string l6Name { get; set; }

        public string l7Name { get; set; }

        public string supplierCode { get; set; }

        public string supplierName { get; set; }

        public double packSize { get; set; }

        public Decimal costPrice { get; set; }

        public string marginWholeSale { get; set; }

        public string marginRetail { get; set; }

        public Decimal eachRetail { get; set; }

        public Decimal eachWholeSale { get; set; }

        public string unitOfEach { get; set; }

        public Decimal packRetail { get; set; }

        public Decimal packWholeSale { get; set; }

        public string unitOfPack { get; set; }

        public Decimal convertFact { get; set; }

        public string convertFactUnit { get; set; }

        public Decimal avgCost { get; set; }

        public Decimal tax1 { get; set; }

        public Decimal maxPrice { get; set; }

        public string costCode { get; set; }

        public Decimal tax2 { get; set; }

        public Decimal tax3 { get; set; }

        public bool noDiscount { get; set; }

        public Decimal ccPrice { get; set; }

        public double reOrderLevel { get; set; }

        public double reOrderQty { get; set; }

        public string binLocation { get; set; }

        public bool lockedForSale { get; set; }

        public bool lockedForPurchase { get; set; }

        public byte countable { get; set; }

        public byte consign { get; set; }

        public string? type { get; set; }

        public bool isCombine { get; set; }

        public bool taxApply { get; set; }

        public bool nbtApply { get; set; }

        public byte useOpenPrice { get; set; }

        public Decimal secondPriceQty { get; set; }

        public Decimal thirdPriceQty { get; set; }

        public Decimal fourthPriceQty { get; set; }

        public Decimal fifthPriceQty { get; set; }

        public Decimal sixthPriceQty { get; set; }

        public Decimal seventhPriceQty { get; set; }

        public Decimal eightthPriceQty { get; set; }

        public Decimal secondPriceRate { get; set; }

        public Decimal thirdPriceRate { get; set; }

        public Decimal fourthPriceRate { get; set; }

        public Decimal fifthPriceRate { get; set; }

        public Decimal sixthPriceRate { get; set; }

        public Decimal seventhPriceRate { get; set; }

        public Decimal eightthPriceRate { get; set; }

        public string commission { get; set; }

        public string dateCreated { get; set; }

        public string lastModified { get; set; }

        public string lastModifiedBy { get; set; }

        public string QtyPurchased { get; set; }

        public string DatePurchased { get; set; }

        public string QtySold { get; set; }

        public string DateSold { get; set; }

        public Decimal stockThisLocation { get; set; }

        public Decimal stockAllLocations { get; set; }

        public double comRate { get; set; }

        public byte itemType { get; set; }

        public string? csCode { get; set; }

        public Decimal? price { get; set; }

        public string userId { get; set; }

        public string locaCode { get; set; }

        public string? serialNo { get; set; }

        public string? QrCodeDescrip { get; set; }

      public byte Use_Exp { get; set; }
    }
}
