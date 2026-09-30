namespace ItemApi.Common
{
    // Shared status codes / lookup metadata used across entities (Supplier, etc.)
    public static class Meta
    {
        public enum SupplierStatus
        {
            Active = 1,
            Inactive = 2
        }

        // z_tb_StockLedger.TxnType — sign of Qty: GRN/Refund +, PRN/Sale -, Adjustment/Opening either
        public enum StockTxnType
        {
            Grn = 1,
            Prn = 2,
            Sale = 3,
            SaleRefund = 4,
            Adjustment = 5,
            Opening = 7
        }

        // z_tb_ZReport.Status (the till's zf_tb_ZReport also uses 0 open / 1 closed)
        public enum ZReportStatus
        {
            Received = 2,
            Reconciled = 3,
            Mismatch = 4
        }

        // z_tb_TempPurchaseSummary.Status once z_sp_PostGrn / z_sp_PostPrn has moved it into stock
        public const int PurchasePostedStatus = 2;
    }
}
