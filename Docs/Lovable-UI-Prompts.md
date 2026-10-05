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

---

## Prompt 7 — Item Entry: quantity prices + price links (change existing screen)

Backend: `ItemzController` (price links, price-level check), `DBScript/03_BackOffice_PriceLink.sql`.

```
Change the existing Item Entry page (src/pages/ItemEntry.tsx). Use the existing Itemz API helper
(src/services/itemzApi.ts) for the new calls. Don't change anything else on the page.

1) "Price Levels" card → rename the title to "Quantity Prices".
   - Column headers: "Buy at least" (was Min Qty) and "Price each" (was Price).
   - Under the title, a small muted hint: "A customer buying at least this quantity pays this price
     for every unit. The till applies it automatically."
   - Rows stay Level 2, 3, 4 (qtyLevel2/priceLevel2 …). Keep the same fields and save flow.
   - Validate before saving (same rules the API enforces; show the first problem under the card in red
     and stop the save):
       • a row must have both values or neither;
       • "Buy at least" must be more than 1 and larger than the row above it;
       • "Price each" must be more than 0, less than the Retail Price, and less than the row above it.
   - If the API still answers 400, show its { message } in a red toast (existing error handling).

2) New card "Price Links" placed directly under the Quantity Prices card.
   Price links are extra retail prices for the SAME item (e.g. old stock still marked at the old MRP).
   When an item has price links, the cashier must choose the right price every time it is scanned.
   - Only enabled when the item is saved (has an itemId). Before that, show the muted text
     "Save the item first to add price links."
   - Load: GET /api/Itemz/PriceLinks/{itemId} → [{ priceLinkId, retailPrice, wholesalePrice, costPrice,
     remark, cDate }]. Reload whenever a different item is loaded into the form.
   - Table columns: Retail Price, Wholesale, Cost, Remark, Added (dd/MM/yyyy), and a delete icon button.
     Money with 2 decimals, right-aligned. Empty state: "No price links — the till uses the normal price."
   - Add row at the bottom of the card: inputs Retail Price (required), Wholesale, Cost, Remark
     (max 50 chars, placeholder "e.g. Old stock MRP") and an "Add" button.
     POST /api/Itemz/AddPriceLink { itemId, retailPrice, wholesalePrice, costPrice, remark }
     → { message, data }. On success: green toast, clear the inputs, reload the list.
     On 400: red toast with { message } (e.g. "This item already has a price link with this price.",
     "This is already the item's normal retail price.").
     Client checks before posting: retail price > 0 and not equal to the form's Retail Price.
   - Delete: confirm dialog "Delete price link {retailPrice}? Tills stop offering it within 5 minutes."
     → DELETE /api/Itemz/PriceLink/{priceLinkId} → { message }. Green toast, reload the list.
   - Card footer, muted: "Changes reach the tills within 5 minutes."
```

---

## Prompt 8 — Cashier billing: quantity prices + price link picker (change existing screen)

Backend: TillService (`/items/find` now returns `priceLinks` and the quantity levels) and
`zf_sp_SaveInvoice`, which refuses a sale line whose price isn't the quantity price or a price link.

```
Change the existing cashier billing screen (src/pages/CashierBilling.tsx) and its local API file
(src/services/tillLocalApi.ts). Keep everything else as it is.

1) tillLocalApi.ts — extend TillItem with:
     qtyLevel2?: number | null; priceLevel2?: number | null;
     qtyLevel3?: number | null; priceLevel3?: number | null;
     qtyLevel4?: number | null; priceLevel4?: number | null;
     stockQty: number | null;
     priceLinks: { priceLinkId: number; retailPrice: number; remark?: string | null }[];

2) Quantity price (automatic). Add this helper and use it everywhere a line's price is worked out.
   The till checks the SAME rule when the bill is saved, so copy it exactly:
     function quantityPrice(item: TillItem, qty: number): number {
       const levels = [
         [item.qtyLevel2, item.priceLevel2], [item.qtyLevel3, item.priceLevel3], [item.qtyLevel4, item.priceLevel4],
       ].filter(([q, p]) => (q ?? 0) > 0 && (p ?? 0) > 0 && qty >= (q as number)) as [number, number][];
       if (levels.length === 0) return item.retailPrice;
       return levels.reduce((best, l) => (l[0] > best[0] ? l : best))[1];
     }
   - Line gets a price source: priceLinkId: number | null (null = normal price).
   - For a line with priceLinkId === null and item.openPrice === false, unitPrice is ALWAYS
     quantityPrice(item, qty). Recalculate it whenever qty changes (scan again, Qty key).
   - When the quantity price is lower than retailPrice, show the retail price struck through next to
     the unit price and a small green badge "Qty price".
   - Lines with a price link keep the link price for any quantity (no quantity price).
   - Open price items: unchanged (cashier types the price).

3) Price link picker. After findItem(code), if the item is not openPrice and
   item.priceLinks (ignoring any whose retailPrice equals item.retailPrice) is not empty:
   - Open a dialog "Select price — {descrip}" BEFORE adding the item. Options as big touch buttons:
       1. Normal price  {retailPrice}
       2. {retailPrice}  {remark}        (one per price link, lowest price first)
     Keyboard: number keys 1..n pick an option, arrow keys + Enter, Esc cancels (item NOT added).
   - Ask every time the item is scanned — the cashier must check the price on the pack each time.
   - Merge into an existing line only when it is the same itemId AND the same priceLinkId
     (null = normal price); otherwise add a new line. Same rule for items without price links.
   - Show the remark under the item name on the line (small, muted) when a link was chosen.
   - The scanner input must get focus back when the dialog closes.

4) Refund mode: same picker and same quantity price.

5) Saving: no change to the request. If POST /invoices answers 400 (e.g. "Price of X has changed.
   Remove the line and scan it again."), show the message in a red toast and keep the bill on screen.
```

---

## Prompt 9 — Cashier billing: search by name + Reload button (change existing screen)

Backend: TillService `GET /items/search`, `GET /items/{itemId}`, `POST /sync/now`.

```
Change the existing cashier billing screen (src/pages/CashierBilling.tsx) and src/services/tillLocalApi.ts.
Keep everything else (including the quantity price and price link picker from the last change).

1) tillLocalApi.ts — add:
     export interface TillItemSearchRow {
       itemId: number; refCode?: string | null; barcode?: string | null;
       descrip: string; inv_Descrip?: string | null; retailPrice: number;
       openPrice: boolean; isSaleLocked: boolean; stockQty: number | null; hasPriceLinks: boolean;
     }
     export interface SyncNowResult {
       ok: boolean; billsUploaded: number; itemsDownloaded: number; priceLinksDownloaded: number; error?: string | null;
     }
     searchItems(text) → GET /items/search?text=...   → TillItemSearchRow[]  (400 { message } if < 2 letters)
     getItem(itemId)   → GET /items/{itemId}          → TillItem (same shape as findItem; 404 if inactive)
     syncNow()         → POST /sync/now               → SyncNowResult   (use timeout 60000 for this call only)

2) Search by name in the scan box:
   - Enter in the scan box: first try findItem(code) exactly as today (barcode / item code).
     Only if that answers 404 AND the text has a letter in it (not only digits), call searchItems(text).
   - 0 results → red toast "No item found for '<text>'".
   - 1 result → use it directly: getItem(itemId), then the same add-to-bill flow as a scan
     (sale-locked check, price link picker, quantity price, merge rules).
   - 2+ results → open a dialog "Select item — '<text>'" with a list (max 50, as returned):
       columns: Description (descrip, and inv_Descrip under it in small muted text when different),
       Code (refCode), Price (retailPrice, 2 decimals, right-aligned), Stock (stockQty, muted, blank if null).
       Rows with isSaleLocked: greyed out with a "Locked" badge and not selectable.
       Rows with hasPriceLinks: small badge "Several prices".
     Keyboard first: the first selectable row is highlighted, ↑/↓ move, Enter picks, Esc closes.
     Touch: tap a row. On pick → getItem(itemId) → same add-to-bill flow as a scan.
   - Also add a "Search" button next to the scan box that opens the same dialog with its own text input
     (type at least 2 letters; search 300 ms after typing stops).
   - After the dialog closes the scan box gets focus again.

3) Reload button in the status bar (icon RefreshCw + text "Reload"):
   - Calls syncNow(). While running: spinner on the button, button disabled (no double clicks).
   - ok → green toast: "Updated: N items, M price links" (+ ", K bills sent" when billsUploaded > 0);
     when everything is 0 → "Already up to date".
   - not ok → red toast with result.error (e.g. "Back office not reachable — working offline.").
     Billing keeps working either way.
   - Then reload the status bar (getSyncStatus).
   - Lines already on the bill keep the item data they were scanned with. If items were updated
     (itemsDownloaded or priceLinksDownloaded > 0) and the bill has lines, show a yellow note above the
     lines: "Prices were updated — if Pay is refused, void the line and scan it again." Hide it when the
     bill is cleared.
   - Keyboard shortcut F5 = Reload (prevent the browser refresh).
```

---

## Prompt 10 — Cashier billing: Wholesale mode (change existing screen)

Backend: `POST /invoices` takes `priceType` (1 retail, 2 wholesale). The till accepts wholesale prices
**only** on a bill sent with `priceType: 2`, and the back office stores it on the bill (`z_tb_SalesInvoice.PriceType`).

```
Change the existing cashier billing screen (src/pages/CashierBilling.tsx) and src/services/tillLocalApi.ts.
Keep everything else (quantity prices, price link picker, name search, Reload).

1) tillLocalApi.ts:
   - InvoiceRequest gets  priceType: 1 | 2;   (1 retail, 2 wholesale)
   - TillItem already has wholesalePrice?: number | null — make sure it is in the interface.
   - priceLinks entries get  wholesalePrice?: number | null.
   - TillItemSearchRow gets  wholesalePrice?: number | null.
   - export const PRICE_RETAIL = 1, PRICE_WHOLESALE = 2;

2) Bill price mode: state priceMode: "retail" | "wholesale", default "retail".
   - "Wholesale" toggle button next to the Refund button (shortcut F8).
     Turning it ON asks for the supervisor PIN (same dialog and verifySupervisorPin as Refund).
     Turning it OFF needs no PIN.
   - While ON: a full-width orange banner above the bill lines "WHOLESALE BILL — wholesale prices"
     and the Wholesale button stays highlighted. It must be impossible to miss.
   - After a bill is saved (Pay finished) or the bill is cleared, priceMode goes back to "retail"
     automatically, so the next customer is never charged wholesale by mistake.

3) One price function for every line (replace the direct quantityPrice calls with this):
     function linePrice(item, qty, link, mode): number {
       if (item.openPrice) return <typed price>;               // unchanged
       if (link) return mode === "wholesale" && (link.wholesalePrice ?? 0) > 0
                        ? link.wholesalePrice! : link.retailPrice;
       if (mode === "wholesale" && (item.wholesalePrice ?? 0) > 0) return item.wholesalePrice!;
       return quantityPrice(item, qty);                       // retail rule, unchanged
     }
   - Wholesale price is per unit for any quantity (no quantity price on top of it).
   - Item without a wholesale price on a wholesale bill: uses the retail rule and shows a small grey
     badge "No wholesale price" on the line.
   - Lines priced at wholesale show a small orange badge "W" next to the unit price.

4) Switching the mode with lines already on the bill: re-price every line that is not open price with
   linePrice(...) for the new mode and show a toast "Prices changed to wholesale" / "Prices changed to retail".

5) Price link picker in wholesale mode: show each option's wholesale price (fall back to its retail price),
   with the retail price small and struck through next to it. Search pick list in wholesale mode: show
   wholesalePrice (fall back to retailPrice) in the Price column.

6) POST /invoices: send priceType: priceMode === "wholesale" ? 2 : 1. Works with Refund mode too
   (a wholesale refund sends invType 2 + priceType 2).
   If the till answers 400 "Price of X has changed…", show it in a red toast and keep the bill.

7) Receipt print: when priceType is 2, print "WHOLESALE" under the bill number.
```

---

## Prompt 11 — Cashier billing: "Other item" (item not in the item list)

Backend: a sale line with `itemId: 0` + `lineDescrip` is an item that is not in the item list. The till
accepts any price above 0 for it (no price check), the back office stores the description and does **not**
move stock for it. All other-item lines of a Z are totalled together as "Other items".

```
Change the existing cashier billing screen (src/pages/CashierBilling.tsx) and src/services/tillLocalApi.ts.
Keep everything else (quantity prices, price links, name search, Reload, Wholesale).

1) tillLocalApi.ts: InvoiceLine gets  lineDescrip?: string | null;  (only sent for itemId 0)

2) "Other item" button next to Search (shortcut F9). Opens a dialog "Other item (not in item list)":
   - Description: text, required, max 50 characters, focused when the dialog opens.
   - Price: number, required, more than 0, 2 decimals.
   - Qty: number, default 1, more than 0.
   - Enter on the last field or the "Add" button adds the line; Esc cancels.
   - Big touch-friendly inputs; the numeric keypad on the right types into the focused field.

3) The line on the bill:
   - itemId 0, unitPrice = the typed price, the typed description as the line name with a small grey
     badge "Other". Store the description on the line (do not look anything up).
   - Never merge other-item lines with each other or with real items — each Add is a new line.
   - Qty key and Price key work on it like an open price item. No price link picker, no quantity price,
     no wholesale price — Wholesale mode does not change it.
   - Works in Refund mode too (a refund line for an item that is not in the list).

4) POST /invoices: for these lines send { lineNum, itemId: 0, lineDescrip: <description>, qty, unitPrice,
   discount: 0, amount }. Real item lines don't send lineDescrip.
   400 "Other item needs a description and a price above 0." → red toast, keep the bill.

5) Receipt print: print the typed description for these lines.
```

---

## Prompt 12 — Cashier billing: wholesale per line (replaces the "all lines" behaviour of Prompt 10)

Backend: each line in `POST /invoices` can send its own `priceType` (1 retail, 2 wholesale). The till checks
each line against its own type — a wholesale price only on a line marked wholesale. The bill's `priceType`
is now only the default for lines that don't send one; the till stores the bill as wholesale when any line is.

```
Change the existing cashier billing screen (src/pages/CashierBilling.tsx) and src/services/tillLocalApi.ts.
A retail bill must be able to have some wholesale lines, and a wholesale bill some retail lines.
Keep everything else (quantity prices, price links, name search, Reload, Other item).

1) tillLocalApi.ts: InvoiceLine gets  priceType?: 1 | 2;

2) Each bill line gets its own  priceType: "retail" | "wholesale".
   Its price is linePrice(item, qty, link, line.priceType) — the same function as before, but called with
   the LINE's type instead of the bill mode. Open price and Other item lines ignore it (typed price).

3) Bill default mode (the existing Wholesale button, F8) now only decides the type of NEW lines:
   - Banner text: "WHOLESALE — new items at wholesale price" while the default is wholesale.
   - When it is switched and the bill already has lines, ask in a small dialog:
       "Change the lines already on the bill too?"  [All lines]  [New items only]   (Enter = New items only)
     All lines → set every line's priceType to the new mode and re-price; New items only → leave lines as they are.

4) Switch one line: select a line and press "W/R" (button in the line toolbar next to Qty / Price, shortcut F7),
   or tap the line's price badge → toggles that line between retail and wholesale and re-prices it.
   - Lines priced wholesale show an orange "W" badge next to the unit price; retail lines show nothing.
   - Item without a wholesale price: switching it to wholesale shows "No wholesale price for <item>" and
     keeps it retail.
   - Merge rule when scanning: merge only into a line with the same itemId, same price link AND same priceType.

5) Supervisor PIN: asked ONCE per bill, the first time anything is set to wholesale (bill default or a line).
   After that, W/R and the Wholesale button work without PIN until the bill is finished or cleared.
   Switching back to retail never needs a PIN.

6) After the bill is saved or cleared: default mode back to retail and the PIN approval is cleared.

7) POST /invoices: send priceType on EVERY line (1 retail, 2 wholesale), and the bill priceType = the default
   mode. The till answers 400 "Price of X has changed…" if a line's price doesn't match its type.

8) Receipt: print "W" after the price of wholesale lines; print "WHOLESALE" under the bill number only when
   every item line is wholesale.
```

---

## Prompt 13 — Cashier billing: Suspend / Recall bill

Backend: TillService `POST /suspended`, `GET /suspended`, `POST /suspended/{id}/recall`, `DELETE /suspended/{id}`,
and `GET /sync/status` now has `suspendedBills`. A suspended bill is **not** an invoice: no number, no Z, never
uploaded. It stays on the till until recalled or cancelled — across restarts and day end. Recall works **once**
(the till marks it recalled), so the same bill can never be paid twice.

```
Change the existing cashier billing screen (src/pages/CashierBilling.tsx) and src/services/tillLocalApi.ts.
Keep everything else (quantity prices, price links, name search, Reload, Other item, wholesale per line).

1) tillLocalApi.ts — add:
     export interface SuspendLine {
       lineNum: number; itemId: number; priceLinkId?: number | null; priceType?: 1 | 2;
       qty: number; unitPrice: number; discount: number; amount: number; lineDescrip?: string | null;
     }
     export interface SuspendedBillRow {
       suspendId: number; label?: string | null; invType: 1 | 2; priceType: 1 | 2; cashierId?: string | null;
       lineCount: number; netAmount: number; suspendedAt: string; firstItems?: string | null;
     }
     export interface RecalledLine extends SuspendLine {
       name?: string | null; itemFound: boolean; item?: TillItem | null;   // item = the item as it is NOW
     }
     export interface RecalledBill {
       suspendId: number; label?: string | null; invType: 1 | 2; priceType: 1 | 2; cashierId?: string | null;
       discount: number; netAmount: number; suspendedAt: string; lines: RecalledLine[];
     }
     suspendBill({ invType, priceType, cashierId, discount, label, items: SuspendLine[] })
                                        → POST /suspended                          → { suspendId }
     getSuspendedBills()                → GET /suspended                           → SuspendedBillRow[]
     recallBill(suspendId, cashierId)   → POST /suspended/{id}/recall?cashierId=   → RecalledBill
     cancelSuspendedBill(suspendId, cashierId) → DELETE /suspended/{id}?cashierId= → { ok }
     SyncStatus gets  suspendedBills: number.

2) "Suspend" button in the bill toolbar (shortcut F10). Enabled only when the bill has lines and the tender
   dialog is not open.
   - Opens a small dialog "Suspend bill" with an optional "Note / customer name" (max 50, focused).
     Enter = Suspend, Esc = cancel.
   - Sends every line exactly as POST /invoices would (lineNum, itemId, qty, unitPrice, discount, amount,
     priceType, lineDescrip for other items) PLUS priceLinkId = the price link the cashier picked (null = normal
     price). invType = 2 in Refund mode, priceType = the bill default mode, discount = bill discount.
   - OK → green toast "Bill suspended (#<suspendId>)", then clear the bill exactly like after Pay
     (default mode back to retail, refund mode off, PIN approvals cleared, scan box focused).
   - 400 → red toast with the message, keep the bill.

3) "Recall" button next to Suspend (shortcut F11) with a count badge = status.suspendedBills (hidden when 0).
   Opens a dialog "Suspended bills" listing getSuspendedBills():
     columns: # (suspendId), Note (label), Items (firstItems, muted, then "+N more" when lineCount > 3),
     Lines (lineCount), Amount (netAmount, 2 decimals, right), Time (suspendedAt as HH:mm, plus dd/MM when not
     today), Cashier. A "REFUND" badge when invType 2, an orange "W" badge when priceType 2.
   Keyboard first: first row highlighted, ↑/↓ move, Enter = Recall, Delete = Cancel bill, Esc closes.
   Touch: tap a row, then the "Recall" button. Empty list → "No suspended bills".
   - If the screen already has a bill with lines, recalling first asks:
       "Suspend the current bill and recall #<id>?"  [Suspend current & recall]  [Cancel]
     (Enter = Suspend current & recall). It suspends the current bill (no note), then recalls.
     Never throw the current bill away silently.
   - "Cancel bill" (Delete key / red button): supervisor PIN first (same dialog as Refund), then confirm
     "Cancel suspended bill #<id> (<amount>)? This cannot be undone." → cancelSuspendedBill → refresh the list.

4) Rebuilding the recalled bill (recallBill answer):
   - Refund mode ON when invType 2; default mode = priceType; treat the supervisor PIN as already given for this
     bill (it was given before it was suspended). Bill discount = discount. Show "Recalled #<id> — <label>" in a
     small blue bar above the lines until the bill is paid or cleared.
   - Each line, in lineNum order:
       itemId 0 (other item): restore as an Other item line with lineDescrip, qty, unitPrice.
       itemFound false: DROP the line and collect its name.
       otherwise use line.item (do NOT call getItem again):
         item.isSaleLocked → drop the line and collect its name;
         priceLinkId set and still in item.priceLinks → use that link, else the normal price;
         openPrice items keep the stored unitPrice; all others: price = linePrice(item, qty, link, line.priceType)
         (prices are taken from the item as it is NOW — they may have changed while the bill was suspended).
       Keep qty, line discount and priceType. Never merge recalled lines with each other.
   - Dropped lines → yellow toast "Removed (no longer sold): <names>".
   - New total differs from netAmount → yellow note above the lines
     "Prices changed since the bill was suspended: was <netAmount>, now <new total>." (hide when the bill is cleared).
   - 400 "already recalled or cancelled" → red toast and refresh the list.

5) Status bar: after a suspend, recall or cancel, reload getSyncStatus so the Recall badge is right.
   Day end: when status.suspendedBills > 0 the confirm dialog adds
   "N suspended bill(s) stay on the till and can be recalled later." (not blocking).

6) Suspended bills are on THIS till only (they live in the till's local database).
```
