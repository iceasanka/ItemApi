using BarTender;
using System.Text.Json.Serialization;

namespace ItemApi.Models
{
    public class PrintItem
    {

        [JsonPropertyName("item_Code")]
        public string item_Code { get; set; }

        [JsonPropertyName("barcode")]
        public string barcode { get; set; }

        [JsonPropertyName("descrip")]
        public string descrip { get; set; }

        [JsonPropertyName("sinhalaDescrip")]
        public string sinhalaDescrip { get; set; }

        [JsonPropertyName("eRet_Price")]
        public decimal eRet_Price { get; set; }

        [JsonPropertyName("tax3")]//Discount
        public string tax3 { get; set; }

        [JsonPropertyName("tax2")]//Discount percentage 
        public string tax2 { get; set; }

        [JsonPropertyName("cost_Price")]
        public decimal cost_Price { get; set; }

       // [JsonIgnore]
        public string? printerName { get; set; }

       // [JsonIgnore]
        public string? printTemplatePath { get; set; }

        /// <summary>
        /// 1= Price, 2= Discount, 3=LandScape,4= Cheque
        /// </summary>
        public int printType { get; set; }

        [JsonPropertyName("printLanguage")]
        public int printLanguage { get; set; } // 1= English, 2= Sinhala
    }
}
