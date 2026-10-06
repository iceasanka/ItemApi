namespace ItemApi.Models
{
    // Sales dashboard (home page) and sales analysis — rows of the z_sp_Dash* procs
    // (DBScript/04_BackOffice_SalesDashboard.sql). Property names = proc column names (EF SqlQueryRaw).
    // Money: net of refunds and of bill discounts. Profit and margin only count lines with a known cost;
    // sales of lines without a cost are UncostedSales. Docs/StockSystem.md §6.9.

    public class DashTotals
    {
        public int Bills { get; set; }
        public int Refunds { get; set; }
        public decimal SalesAmount { get; set; }
        public decimal RefundAmount { get; set; }
        public decimal NetSales { get; set; }
        public decimal Discount { get; set; }
        public decimal ItemQty { get; set; }
        public decimal Cost { get; set; }
        public decimal Profit { get; set; }
        public decimal CostedSales { get; set; }
        public decimal UncostedSales { get; set; }
        public decimal MarginPct { get; set; }
        public decimal AvgBill { get; set; }
        public decimal Cash { get; set; }
        public decimal Card { get; set; }
        public decimal Other { get; set; }
        public DateTime? FirstBillAt { get; set; }
        public DateTime? LastBillAt { get; set; }
    }

    public class DashDay
    {
        public DateTime SaleDate { get; set; }
        public int Bills { get; set; }
        public int Refunds { get; set; }
        public decimal NetSales { get; set; }
        public decimal Discount { get; set; }
        public decimal Cost { get; set; }
        public decimal Profit { get; set; }
        public decimal CostedSales { get; set; }
        public decimal MarginPct { get; set; }
        public decimal Cash { get; set; }
        public decimal Card { get; set; }
        public decimal Other { get; set; }
    }

    public class DashTerminal
    {
        public int TerminalId { get; set; }
        public string? TerminalCode { get; set; }
        public string? TerminalName { get; set; }
        public int Status { get; set; }
        public DateTime? LastSyncAt { get; set; }
        // sent a bill or heartbeat in the last 2 minutes
        public bool IsOnline { get; set; }
        public int Bills { get; set; }
        public decimal NetSales { get; set; }
        public DateTime? LastBillAt { get; set; }
        public decimal Profit { get; set; }
    }

    public class DashHour
    {
        public int SaleHour { get; set; }
        public int Bills { get; set; }
        public decimal NetSales { get; set; }
        public decimal Profit { get; set; }
    }

    public class DashItem
    {
        // 0 = all "other items" (not in the item list)
        public int ItemId { get; set; }
        public string? Name { get; set; }
        public decimal Qty { get; set; }
        public decimal NetSales { get; set; }
        public decimal Cost { get; set; }
        public decimal Profit { get; set; }
        public decimal MarginPct { get; set; }
        // some of its sales have no cost (not in Profit)
        public bool HasUncosted { get; set; }
    }

    public class DashCategory
    {
        public int? CatId { get; set; }
        public string? CatName { get; set; }
        public decimal Qty { get; set; }
        public decimal NetSales { get; set; }
        public decimal Profit { get; set; }
        public decimal MarginPct { get; set; }
    }

    // GET api/Dashboard/Today — home page
    public class DashboardToday
    {
        public DateTime ServerTime { get; set; }
        public DateTime Date { get; set; }
        // Dashboard:LivePush — the server sends "salesChanged" on /hubs/sales when tills upload bills
        public bool LivePush { get; set; }
        public DashTotals Totals { get; set; } = new();
        public List<DashTerminal> Terminals { get; set; } = new();
        public List<DashHour> Hourly { get; set; } = new();
        public List<DashItem> TopItems { get; set; } = new();
    }

    // GET api/Dashboard/Sales — sales analysis for a date range
    public class DashboardSales
    {
        public DateTime FromDate { get; set; }
        public DateTime ToDate { get; set; }
        public int? TerminalId { get; set; }
        public DashTotals Totals { get; set; } = new();
        public List<DashDay> Daily { get; set; } = new();
        public List<DashTerminal> Terminals { get; set; } = new();
        public List<DashHour> Hourly { get; set; } = new();
        public List<DashItem> TopItems { get; set; } = new();
        public List<DashItem> TopProfitItems { get; set; } = new();
        public List<DashCategory> Categories { get; set; } = new();
    }

    // SignalR /hubs/sales → "salesChanged"
    public class SalesChangedEvent
    {
        public int TerminalId { get; set; }
        public int NewBills { get; set; }
        public DateTime At { get; set; }
    }
}
