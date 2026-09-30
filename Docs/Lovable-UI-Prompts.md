# Lovable prompts — Stock UI (back office)

Paste **Prompt 0** first (context), then one screen prompt at a time. Each prompt is
self-contained so Lovable doesn't need to see this API's code. Backend details: [StockSystem.md](StockSystem.md).

If your existing back office app is already in Lovable, open that project and paste the prompts
there; say "add to the existing app and reuse its layout, sidebar and API helper" in Prompt 0.

---

## Prompt 0 — context (paste once)

```
I'm building the back office screens for a supermarket stock system (like Food City).
Stack: React + TypeScript + Tailwind + shadcn/ui, TanStack Query for API calls.
Backend is an existing ASP.NET API. Put the base URL in one config value
VITE_API_BASE_URL (e.g. http://localhost:5000/api) and make one small fetch helper.

API conventions:
- JSON, camelCase.
- Validation errors come back as HTTP 400 with body { "message": "..." } — show that message in a
  red toast. HTTP 500 comes back as { "message": "Internal Server Error", "error": "..." }.
- Success for saves: { "message": "...", "data": {...} } — show message in a green toast.
- Quantities have 3 decimals, money has 2 decimals. Show negative quantities in red.
- Dates from the API are ISO strings; show as dd/MM/yyyy HH:mm.

Stock rules the UI must respect:
- Stock is a ledger: nothing is ever edited or deleted, only new documents are added.
- Stock changes only through: GRN commit (+), Purchase Return (PRN) commit (−), cashier sales (−),
  refunds (+), and stock adjustments (±).
- Transaction types: 1 GRN, 2 PRN, 3 Sale, 4 Refund, 5 Adjustment, 7 Opening.
  Colour chips: GRN green, PRN orange, Sale blue, Refund purple, Adjustment grey, Opening teal.

Add a sidebar group "Stock" with: Stock Balance, Stock Adjustment, Adjustment History,
Tills & Z Reports. Don't build anything else yet.
```

---

## Prompt 1 — Stock Balance + Item Card

```
Build the "Stock Balance" page.

API:
POST {base}/StockLedger/SearchBalances
  body { "query": string, "catId": number|null, "supId": number|null,
         "onlyNegative": boolean, "page": number, "pageSize": number }
  returns { "total": number, "rows": [ { "itemId", "refCode", "barcode", "descrip",
            "qty", "avgCost", "stockValue", "uDate" } ] }

GET {base}/StockLedger/ItemCard?itemId=5&fromDate=2026-09-01&toDate=2026-09-30
  returns { "itemId", "refCode", "descrip", "fromDate", "toDate", "openingQty", "closingQty",
            "rows": [ { "ledgerId", "txnDate", "txnType", "txnTypeName", "docNo",
                        "terminalId", "zNo", "qtyIn", "qtyOut", "balance",
                        "costPrice", "sellPrice", "userId" } ] }

Page layout:
- Top: search box (debounced 300ms, searches code/barcode/description), a switch
  "Only negative stock", and a total count.
- Table: Code, Barcode, Description, Qty (right aligned, red if < 0), Avg Cost, Stock Value,
  Last Movement. Server-side paging 50 rows. Footer shows sum of Stock Value for the page.
- Clicking a row opens a right-side drawer "Item Card":
  - header: code + description, date range picker (default last 30 days), Refresh.
  - summary cards: Opening Qty, Total In, Total Out, Closing Qty.
  - table: Date, Type (coloured chip), Document No, Till/Z (e.g. "T1 / Z15" when terminalId set),
    In, Out, Balance, Price (sellPrice for sales, costPrice otherwise), User.
  - first row is a grey "Opening balance" row, last row a bold "Closing balance" row.
- Export the visible table to CSV.
```

---

## Prompt 2 — Stock Adjustment (new)

```
Build the "Stock Adjustment" page for creating a new adjustment. It can be used any time.

APIs:
GET  {base}/StockAdjustment/Reasons  → [ { "reasonId", "reasonName", "status" } ]
GET  {base}/Itemz/Search?query=abc   → items [ { "itemId", "refCode", "barcode", "descrip", ... } ]
GET  {base}/StockLedger/Balance/{itemId} → { "itemId", "qty", "avgCost", ... }
GET  {base}/Sync/Terminals → [ { "terminalId", "terminalCode", "terminalName", "status",
                                 "lastSyncAt", "openZCount", "isStale" } ]
POST {base}/StockAdjustment/Save
  body { "adjDate": null, "reasonId": number, "remark": string, "userId": string,
         "lines": [ { "itemId": number, "countedQty": number|null, "adjQty": number|null,
                      "reasonId": number|null, "remark": string|null } ] }
  returns { "message", "data": { "adjNo", "adjDate", "reasonName", "totalAdjQty", "totalAdjValue",
            "items": [ { "lineNum", "itemId", "refCode", "descrip", "systemQty", "countedQty",
                         "adjQty", "costPrice" } ] } }

Layout:
- Header card: Reason (select, required), Remark (text), Adj No shows "New" (the number is made
  by the server on save).
- Mode toggle per line, two modes:
  * "Add / Remove" — user types a signed quantity (+5 adds, -3 removes). Sent as adjQty.
  * "Counted"      — user types the physically counted quantity. Sent as countedQty; the server
                     works out the difference.
  Default mode is chosen at header level with a segmented control, and each line can override it.
- Item entry row: barcode/code input with autocomplete (Itemz/Search). Enter or scan adds a line
  and focuses the qty field. Scanning the same item again in Counted mode adds to the counted qty
  instead of adding a new line.
- Lines grid: #, Code, Description, Current Stock (from StockLedger/Balance, grey), Mode,
  Qty input, "Result" column = what stock will become (current + adjQty, or countedQty),
  Difference (coloured + / −), line Reason (optional select), Remark, delete icon.
- Footer: number of lines, total difference, estimated value (difference × avgCost).
- Save button → confirmation dialog listing the totals; on success show the returned adjNo in a
  big success panel with buttons "Print" and "New adjustment". Lines can't be edited after save.

Till warning (important):
- On page load and every 60s call Sync/Terminals. If ANY line uses Counted mode and any active
  terminal has isStale = true or openZCount > 0, show a yellow banner:
  "Till T02 has not uploaded sales since 10:42. Counted quantities may be wrong until all
   tills are synced. Add/Remove adjustments are safe."
  and require ticking "I understand" before Save is enabled.
- Validation before save: at least one line; Counted qty >= 0; Add/Remove qty != 0; an item can
  appear only once in Counted mode. Show server 400 messages as toasts.
```

---

## Prompt 3 — Adjustment History

```
Build the "Adjustment History" page.

APIs:
POST {base}/StockAdjustment/Search body { "adjNo": string, "fromDate": "yyyy-MM-dd"|null,
                                          "toDate": "yyyy-MM-dd"|null, "reasonId": number|null }
  → [ { "adjId", "adjNo", "adjDate", "reasonId", "reasonName", "remark", "lineCount",
        "totalAdjQty", "totalAdjValue", "userId" } ]
GET  {base}/StockAdjustment/GetByAdjNo/{adjNo} → same header + "items": [ { "lineNum", "refCode",
       "descrip", "systemQty", "countedQty", "adjQty", "costPrice", "reasonId", "remark" } ]
GET  {base}/StockAdjustment/Reasons

Layout:
- Filters: Adj No, date range (default this month), Reason select.
- Table: Adj No, Date, Reason, Remark, Lines, Total Qty (red if negative), Total Value, User.
- Row click → dialog with the lines: Code, Description, System Qty, Counted (blank if Add/Remove),
  Adjusted (±, coloured), Cost, Value. Print button (A4, simple table, company header).
- Read only — no edit or delete anywhere.
```

---

## Prompt 4 — GRN / Purchase Return commit (change existing screens)

```
On the existing GRN screen and the existing Purchase Return (PRN) screen, add a "Commit to stock"
step.

APIs:
POST {base}/TempPurchaseSummary/Commit/{grnNo}?userId=xxx
POST {base}/TempPurchaseReturnSummary/Commit/{prnNo}?userId=xxx
  success → { "message": "Commit successful.", "data": "GRN00000008", "lines": 3 }
  400     → { "message": "Document is already posted to stock." } (or not found / no qty lines)

Rules:
- Status 2 on the summary means "posted to stock". For status 2 documents show a green
  "Posted" badge and make the whole document read-only (no line edit/delete, no Commit button).
- For other statuses show a primary "Commit to stock" button next to Save. It opens a confirm
  dialog: "This will add N items / Q qty to stock and cannot be undone." (PRN: "remove from stock").
  Save the document first if there are unsaved changes, then call Commit.
- After success reload the document, show the Posted badge and a toast with the message.
- In the GRN/PRN search lists add a Status column with badges: Draft (0/1) grey, Posted (2) green.
```

---

## Prompt 5 — Tills & Z Reports

```
Build the "Tills & Z Reports" page with two tabs.

APIs:
GET  {base}/Sync/Terminals → [ { "terminalId", "terminalCode", "terminalName", "status",
       "lastSyncAt", "lastItemSyncAt", "lastZNo", "openZCount", "isStale" } ]
POST {base}/Sync/Terminal body { "terminalId": number, "terminalCode": "T01",
       "terminalName": string, "status": 1|0 }
POST {base}/Sync/ZReports/Search body { "fromDate", "toDate", "terminalId", "status" }
  → [ { "zId", "terminalId", "terminalCode", "zNo", "businessDate", "cashierId", "openedAt",
        "closedAt", "invoiceCount", "srvInvoiceCount", "lineCount", "srvLineCount",
        "totalQty", "srvTotalQty", "salesAmount", "refundAmount", "netSales", "srvNetSales",
        "cashAmount", "cardAmount", "otherAmount", "missingCount", "status", "mismatchNote",
        "submittedAt", "reconciledAt" } ]
GET  {base}/Sync/ZReport/{terminalId}/{zNo} → same fields + "items": [ { "itemId", "refCode",
       "descrip", "qty", "amount", "srvQty", "srvAmount" } ]
POST {base}/Sync/ZReport/{terminalId}/{zNo}/Reconcile
  → { "result": { "status", "mismatchNote", ... }, "missingInvoiceNos": ["T01-00000123"] }

Z status: 2 Received (grey), 3 Reconciled (green), 4 Mismatch (red).

Tab "Tills":
- Cards, one per till: code + name, Active/Disabled switch, "Last upload 3 min ago" (red and a
  warning icon if isStale), last item download time, last reconciled Z, and a red badge with
  openZCount if > 0. Auto-refresh every 30s.
- "Add till" button → dialog (Terminal Id number, Code like T01 — uppercase, max 10, Name).
  Explain in the dialog: "Use the same Id and Code when setting up the till program."

Tab "Z Reports":
- Filters: date range (default today), till select, status select.
- Table: Date, Till, Z No, Cashier, Opened–Closed, Bills (till / server), Net Sales (till / server),
  Cash, Card, Other, Status badge. Mismatched rows get a light red background.
- Top summary for the filter: total net sales, cash, card, count of reconciled vs mismatch.
- Row click → full-page detail:
  * two-column comparison card "Till" vs "Server" for Bills, Lines, Qty, Net Sales; any
    difference highlighted red.
  * mismatchNote in a red alert; if missingCount > 0 show "N bills not received yet — the till
    will resend them automatically".
  * items table: Code, Description, Till Qty, Server Qty, Diff, Till Amount, Server Amount, Diff;
    toggle "Show only differences" (on by default when status is 4).
  * "Check again" button → Reconcile API, then reload; show missingInvoiceNos in a list.
  * Print button (80mm-friendly Z summary and an A4 version).
```

---

## Prompt 6 (optional, later) — Cashier billing screen

Only when the till program is being built. The till must work offline, so the screen talks to a
**local** service on the till PC (which uses the `zf_` database), not to the back office API.

```
Build a full-screen cashier billing screen (touch + barcode scanner friendly, 1366x768).
It talks to a LOCAL api at VITE_LOCAL_API (the till service), which wraps these calls:
- GET  /items/find?code=  → item { itemId, refCode, barcode, descrip, inv_Descrip, retailPrice,
                                   openPrice, isSaleLocked, noDiscount, stockQty }
- POST /invoices { invType: 1|2, cashierId, discount, items:[{lineNum,itemId,qty,unitPrice,discount,amount}],
                   payments:[{lineNum,payType,amount,refNo}] } → { invoiceNo }
- POST /z/close → Z summary;  GET /sync/status → { online, unsentBills, lastUpload }

Layout: left = bill lines (big font), right = keypad, totals, pay buttons (Cash, Card, Mixed).
Scanner input always focused. Qty key, price key (only when openPrice), line void (before pay only),
Refund mode toggle (needs supervisor PIN), Pay → tender dialog with change calculation.
Status bar: Online/Offline dot, "N bills waiting to upload", cashier name, Z number.
Never block a sale because stockQty <= 0 — show a small warning only. isSaleLocked items cannot be sold.
Day end button → confirm → show Z summary (bills, net sales, cash, card) and print.
```
