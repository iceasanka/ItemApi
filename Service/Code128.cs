namespace ItemApi.Service
{
    // CODE128 (code set B) as bar / space widths - for slips printed through the Windows driver (Service/ReceiptSlip.cs),
    // where the printer can't draw the barcode itself as it does with ESC/POS GS k. Text: printable ASCII only.
    public static class Code128
    {
        // widths of value 0..106 (bar, space, bar, space, bar, space[, bar]); 103..105 start A/B/C, 106 stop
        private static readonly string[] Patterns =
        {
            "212222", "222122", "222221", "121223", "121322", "131222", "122213", "122312", "132212", "221213",
            "221312", "231212", "112232", "122132", "122231", "113222", "123122", "123221", "223211", "221132",
            "221231", "213212", "223112", "312131", "311222", "321122", "321221", "312212", "322112", "322211",
            "212123", "212321", "232121", "111323", "131123", "131321", "112313", "132113", "132311", "211313",
            "231113", "231311", "112133", "112331", "132131", "113123", "113321", "133121", "313121", "211331",
            "231131", "213113", "213311", "213131", "311123", "311321", "331121", "312113", "312311", "332111",
            "314111", "221411", "431111", "111224", "111422", "121124", "121421", "141122", "141221", "112214",
            "112412", "122114", "122411", "142112", "142211", "241211", "221114", "413111", "241112", "134111",
            "111242", "121142", "121241", "114212", "124112", "124211", "411212", "421112", "421211", "212141",
            "214121", "412121", "111143", "111341", "131141", "114113", "114311", "411113", "411311", "113141",
            "114131", "311141", "411131", "211412", "211214", "211232", "2331112",
        };

        private const int StartB = 104, Stop = 106;

        public static bool CanEncode(string? text) =>
            !string.IsNullOrEmpty(text) && text.All(ch => ch is >= ' ' and <= '~');

        // Module widths, bar first: start B, the text, check value, stop
        public static List<int> Widths(string text)
        {
            if (!CanEncode(text))
                throw new ArgumentException("CODE128 B takes printable ASCII only.", nameof(text));
            var values = new List<int> { StartB };
            var check = StartB;
            for (int i = 0; i < text.Length; i++)
            {
                var v = text[i] - 32;
                values.Add(v);
                check += v * (i + 1);
            }
            values.Add(check % 103);
            values.Add(Stop);
            return values.SelectMany(v => Patterns[v].Select(c => c - '0')).ToList();
        }

        // modules across the whole barcode, quiet zones not included
        public static int ModuleCount(string text) => Widths(text).Sum();
    }
}
