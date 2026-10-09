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

---

## Prompt 14 — Cashier billing: printed receipt, bill copy, cash drawer, No Sale

Backend: TillService now prints the receipt itself (thermal printer, ESC/POS) and opens the cash drawer when the
bill has cash. `POST /invoices` answers `{ invoiceNo, printed, drawerOpened, printError }`; the bill is saved even
when printing fails. New: `GET /invoices?date=`, `GET /invoices/{no}`, `POST /invoices/{no}/print?copy=`,
`POST /drawer/nosale`. Details: StockSystem.md §6.7.

```
Change the existing cashier billing screen (src/pages/CashierBilling.tsx) and src/services/tillLocalApi.ts.
Keep everything else (quantity prices, price links, name search, Reload, Other item, wholesale per line, suspend).

1) tillLocalApi.ts
   - InvoiceLine gets  priceLinkId?: number | null   (the price link the cashier picked, null = normal price).
     Send it on every line of POST /invoices (suspend already sends it).
   - Payment gets  tendered?: number | null  — for cash: the money the customer handed over (amount + change).
   - createInvoice(...) now returns  { invoiceNo: string; printed: boolean; drawerOpened: boolean; printError?: string | null }.
     Request gets  print?: boolean  (default true; always send true from the Pay dialog).
   - add:
       export interface InvoiceListRow { invoiceNo: string; invType: 1|2; invDate: string; cashierId?: string|null; zNo: number;
         netAmount: number; discount: number; status: number; synced: boolean; lineCount: number;
         cashAmount: number; cardAmount: number; otherAmount: number; }
       export interface PrintBillLine { lineNum: number; itemId: number; name: string; code?: string|null; qty: number;
         mktPrice?: number|null; unitPrice: number; discount: number; amount: number; priceType: 1|2; }
       export interface PrintBill { invoiceNo: string; zNo: number; invType: 1|2; invDate: string; cashierId?: string|null;
         grossAmount: number; discount: number; discountPercent?: number|null; netAmount: number; status: number;
         priceType: 1|2; synced: boolean; terminalCode?: string|null; lines: PrintBillLine[];
         payments: { lineNum: number; payType: number; amount: number; refNo?: string|null; tendered?: number|null }[]; }
       export interface PrintResult { printed: boolean; drawerOpened: boolean; printError?: string|null }
       getInvoices(date: string /* yyyy-MM-dd */)  → GET  /invoices?date=          → InvoiceListRow[]
       getInvoice(invoiceNo)                      → GET  /invoices/{invoiceNo}     → PrintBill
       printInvoice(invoiceNo, copy = true)       → POST /invoices/{invoiceNo}/print?copy=true|false → PrintResult
       noSale(pin, cashierId, reason)             → POST /drawer/nosale { pin, cashierId, reason } → PrintResult
                                                    (401 { message: "Wrong PIN." })

2) Pay / tender dialog
   - Cash: send payments [{ payType: 1, amount: <applied amount>, tendered: <cash typed> }]. Mixed cash + card: tendered on the
     cash line only. Card only: no tendered.
   - REMOVE any receipt printing done by the browser (window.print / receipt component) — the till prints now.
   - After createInvoice:
       printed → green toast "Bill <invoiceNo> saved" (+ " · drawer open" when drawerOpened).
       not printed → yellow toast that stays until closed: "Bill <invoiceNo> saved but NOT printed: <printError>"
         with a button "Print again" → printInvoice(invoiceNo, false). The bill is saved — never take payment again.
   - Keep showing "Change: <balance>" big after a cash bill (as today).

3) "Bill copy" button in the toolbar (shortcut F9) → dialog "Bill copy"
   - Date picker at the top, default today (dd/MM/yyyy). Loads getInvoices(date).
   - Table: Invoice no, Time (HH:mm), Lines, Amount (2 decimals, right), Pay (Cash / Card / Cash+Card / Other from the
     amounts), Cashier, badges: REFUND (invType 2), VOID (status 9, grey row), "Not uploaded" (synced false, small orange).
   - Search box filters by invoice number (the last digits are enough).
   - Keyboard: first row highlighted, ↑/↓, Enter = Print copy, Space = preview, Esc closes.
   - Preview panel on the right (getInvoice): lines (name, qty × price, amount), sub total, discount (with % when
     discountPercent), net, payments, balance — like a receipt, monospace.
   - "Print copy" → printInvoice(no) → green toast "Copy printed", or red toast with printError.
   - No PIN needed. It only finds bills made on THIS till.

4) "No Sale" button (toolbar, shortcut Ctrl+D) — opens the cash drawer without a bill
   - Disabled while the tender dialog is open.
   - Dialog "No Sale — open cash drawer": PIN (password field, focused), Reason (optional, max 100; quick chips:
     "Change", "Cash count", "Wrong change", "Other"). Enter = Open drawer, Esc = cancel.
   - The PIN is asked EVERY time (do not reuse an earlier supervisor approval or token).
   - noSale(pin, cashierId, reason) → drawerOpened ? green toast "Drawer opened" : red toast with printError.
     401 → "Wrong PIN", keep the dialog open and clear the PIN.
```

---

## Prompt 15 — Cashier billing: profit view + bill discount % (supervisor PIN)

Backend: `POST /auth/supervisor` now returns `{ ok, token, expiresAt }`; send the token as the `X-Supervisor-Token`
header. `POST /bill/profit` (token) gives cost / profit per line, bill profit and the biggest discount allowed.
`POST /invoices` refuses a bill discount without the token (401) or above the bill profit (400). StockSystem.md §6.7.

```
Change the existing cashier billing screen (src/pages/CashierBilling.tsx) and src/services/tillLocalApi.ts.
Keep everything else.

1) tillLocalApi.ts
   - verifySupervisor(pin) now returns { ok: boolean; token?: string; expiresAt?: string }.
     Keep the token in memory ONLY (React state / module variable — never localStorage). Wherever the page already asks
     for the supervisor PIN (refund, wholesale, cancel suspended bill) keep the token it returns, so one PIN covers
     everything.
   - Every call sends the header  X-Supervisor-Token: <token>  when a token is held.
   - lockSupervisor() → DELETE /auth/supervisor (with the header), then forget the token.
   - getBillProfit(items: InvoiceLine[]) → POST /bill/profit { items } →
       { lines: { lineNum: number; unitCost: number|null; cost: number|null; profit: number|null }[];
         amount: number; cost: number; profit: number; unknownCostLines: number;
         discountBase: number; maxDiscount: number; maxDiscountPercent: number }
     401 → the token expired: forget it, hide the profit view, ask for the PIN again.
   - createInvoice / suspendBill send  discountPercent?: number | null  next to discount.
   - RecalledBill gets  discountPercent?: number | null.

2) Profit view (hidden by default)
   - "Profit" toggle button in the toolbar (eye icon, shortcut Ctrl+P). Off → no cost or profit anywhere on screen.
   - Turning it on: no token → supervisor PIN dialog (same as Refund) → token. Then call getBillProfit(lines) now and
     again (debounced 300 ms) whenever lines, qty, prices or discounts change.
   - While on:
       each bill line shows two small extra columns "Cost" (unitCost) and "Profit" (line profit; red when < 0,
       "—" when null = cost unknown);
       the totals panel shows "Cost", "Profit", "Margin %" (= profit / amount × 100, 1 decimal) and
       "Profit after discount" (= profit − bill discount); when unknownCostLines > 0 a muted note
       "N line(s) without cost — counted as 0".
   - Turning it off → lockSupervisor() and hide the columns. Otherwise it stays on across bills until switched off
     or the cashier signs out.

3) Bill discount % — "Discount %" button in the totals panel (shortcut F6)
   - Needs the token: no token → supervisor PIN dialog first.
   - Dialog "Bill discount": shows "Max allowed: <maxDiscountPercent>% (Rs <maxDiscount>)" from getBillProfit.
     Input "Discount %" (0–100, 2 decimals), live preview "Discount Rs <amount>" and "Net <net>".
     amount = round2(discountBase × % / 100)  — use discountBase from getBillProfit (it leaves out NoDiscount items),
     do NOT work it out on the page.
     amount > maxDiscount → red text "More than this bill allows (max <maxDiscountPercent>%)" and disable OK.
     Buttons: OK (Enter), Remove discount, Cancel (Esc).
   - Totals panel: "Discount 10%  −83.80" under the sub total; net = sum(lines) − discount.
   - The % stays on the bill: when lines change, recompute the amount from the new discountBase (call getBillProfit again).
     If it is now above maxDiscount: red banner "Discount is more than this bill allows — change it" and disable Pay.
   - Pay sends discount (2 decimals) + discountPercent. 400 from the till → red toast with its message, keep the bill.
   - Refund mode: hide the Discount % button.
   - Suspend sends discount + discountPercent; Recall restores both (then recompute as above).

4) After a bill is paid or cleared: discount and discountPercent back to none. The token is kept (the profit view stays
   as the cashier left it).
```

---

## Prompt 16 — Cashier billing: Opening cash, Paid In, Paid Out, cash in drawer at day end

Backend: TillService `GET /cash/summary`, `POST /cash/movements` (kind 1 opening cash, 2 paid in, 3 paid out), and
`POST /z/close` now returns the drawer cash and prints a Z slip. StockSystem.md §6.8.

```
Change the existing cashier billing screen (src/pages/CashierBilling.tsx) and src/services/tillLocalApi.ts.
Keep everything else.

1) tillLocalApi.ts — add:
     export interface CashMovement { moveId: number; zNo: number; kind: 1|2|3; amount: number; reason?: string|null;
       cashierId?: string|null; createdAt: string; status: number /* 1 active, 9 replaced */ }
     export interface CashSummary { zNo: number|null; openedAt?: string|null; openingCash: number; hasOpeningCash: boolean;
       paidIn: number; paidOut: number; cashSales: number; expectedCash: number; movements: CashMovement[] }
     getCashSummary()                                   → GET  /cash/summary → CashSummary
     addCashMovement({ kind, amount, reason, cashierId, pin }) → POST /cash/movements
                                                          → CashMovement & { printed: boolean; drawerOpened: boolean; printError?: string|null }
                                                          401 { message: "Wrong PIN." }, 400 { message }
   ZSummary (POST /z/close) gets: openingCash, paidIn, paidOut, expectedCash: number; printed: boolean; printError?: string|null.

2) Opening cash
   - When the billing screen loads, and again right after a day end, call getCashSummary(). If zNo is null or
     hasOpeningCash is false → open the dialog "Opening cash" automatically:
       "Cash given to the till for this shift", Amount (focused, 2 decimals, > 0), Supervisor PIN (password).
       Enter = Save. A "Later" button closes it (billing is allowed without it) — then show a small orange chip
       "No opening cash" in the status bar; clicking it opens the dialog again.
   - addCashMovement({ kind: 1, amount, pin, cashierId }) → green toast "Opening cash Rs <amount> — drawer open".
     401 → "Wrong PIN", keep the dialog open. 400 (already entered) → red toast with the message, close the dialog.
   - Menu item "Opening cash" in a new "Cash" toolbar menu also opens it.

3) Paid In / Paid Out — "Cash" toolbar menu (shortcut F12) with: Paid In, Paid Out, Opening cash, Drawer summary
   - Paid In dialog: Amount (> 0), Reason (optional, max 100; chips "Change from office", "Float top-up", "Other").
     No PIN. → addCashMovement({ kind: 2, ... }).
   - Paid Out dialog: Amount (> 0), Reason (REQUIRED, max 100; chips "Supplier payment", "Expenses", "Cash to office",
     "Other"), Supervisor PIN. → addCashMovement({ kind: 3, ... }). Remind: "Keep the printed slip with the bill you paid."
   - Both: Enter = Save, Esc = Cancel. OK → green toast "Paid In Rs 1,000.00 — drawer open" / "Paid Out Rs 500.00 — drawer open";
     printError → also a yellow toast "Saved, slip not printed: <printError>". 400 → red toast with the message.
   - Disabled while the tender dialog is open.

4) Drawer summary dialog (from the Cash menu): getCashSummary() →
     Opening cash, + Cash sales, + Paid in, − Paid out, = Cash in drawer (big, bold), then the movements list
     (time, type badge OPENING / PAID IN / PAID OUT, amount, reason, cashier; replaced opening cash greyed with "replaced").

5) Day end (existing Z close)
   - The Z summary dialog adds a "Cash" block: Opening cash, Cash sales, Paid in, Paid out, CASH IN DRAWER (big),
     and a "Counted cash" input: difference = counted − expectedCash, shown green when 0, red "short Rs x" when below,
     blue "over Rs x" when above (display only, not saved).
   - The till prints the Z slip itself now — remove any browser printing of the Z. printed false → yellow toast with printError.
   - After closing: the opening cash is cleared for the next shift → call getCashSummary() and show the Opening cash dialog
     again (step 2).
```

---

## Prompt 17 — Back office home page: today's sales and profit, live

Backend: `GET api/Dashboard/Today` and the SignalR hub `/hubs/sales` (event `salesChanged`), StockSystem.md §6.9.
Each till uploads a bill as soon as it is paid; the server then pushes `salesChanged` and the page reloads.

```
Change the back office HOME page (the first page after login) — add a "Today's sales" dashboard at the top.
Keep what is on the home page now below it.

1) API (use the existing fetch helper; base VITE_API_BASE_URL):
   GET /Dashboard/Today  →
     { serverTime, date, livePush: boolean,
       totals: { bills, refunds, salesAmount, refundAmount, netSales, discount, itemQty, cost, profit, costedSales,
                 uncostedSales, marginPct, avgBill, cash, card, other, firstBillAt, lastBillAt },
       terminals: [{ terminalId, terminalCode, terminalName, status, lastSyncAt, isOnline, bills, netSales, lastBillAt, profit }],
       hourly:   [{ saleHour /*0-23*/, bills, netSales, profit }],
       topItems: [{ itemId, name, qty, netSales, cost, profit, marginPct, hasUncosted }] }
   Money 2 decimals with thousands separators ("Rs 12,345.50"), qty 3 decimals, times HH:mm.

2) Live updates — install @microsoft/signalr.
   - Hub URL: VITE_API_BASE_URL without the trailing "/api" + "/hubs/sales"
     (http://localhost:5000/api → http://localhost:5000/hubs/sales).
   - new HubConnectionBuilder().withUrl(url, { withCredentials: false }).withAutomaticReconnect().build();
     connection.on("salesChanged", () => refetch today)  — debounce 1 s so a burst of bills reloads once.
   - "Auto update" switch in the dashboard header, remembered in localStorage (default ON).
       ON  + connected   → green dot "Live"; the numbers update by themselves.
       ON  + not connected / reconnecting → amber dot "Reconnecting… (refreshes every 60 s)" and refetch every 60 s.
       OFF → grey dot "Auto update off"; disconnect the hub; numbers change only with Refresh.
     Hide the switch and show "Live updates are off on the server" when livePush is false.
   - "Refresh" button (always visible) + "Updated HH:mm:ss" next to it.
   - Briefly highlight (pulse) the cards whose value changed after a live update.

3) Cards (row of KPI tiles, 2 per row on mobile):
   Net sales (big) with "Bills N · Avg bill Rs x" underneath; Profit (green, red when < 0) with "Margin x%";
   Cost; Discount given; Refunds (count and amount, only when > 0); Cash / Card / Other (one tile, three lines).
   When uncostedSales > 0: small muted note under Profit "Rs x of sales have no cost price — not in profit".

4) Sales by hour today: bar chart (shadcn chart / Recharts) of netSales per hour, only hours from the first bill to now;
   a line for profit on the same chart. Tooltip: hour range "10:00–11:00", bills, sales, profit.

5) Tills table: Till (code + name), status chip (green "Online" when isOnline, grey "Offline — last seen HH:mm" /
   "never" when lastSyncAt is null), Bills, Sales, Profit, Last bill (HH:mm). Offline tills show an info line:
   "Bills from offline tills appear when they reconnect."

6) Top 10 items today: Item, Qty, Sales, Profit, Margin %. Row with itemId 0 = "Other items (not in item list)";
   hasUncosted → small "no cost" badge on the profit cell.

7) Link "Sales analysis →" to the page from Prompt 18.
```

---

## Prompt 18 — Sales analysis: date range, daily sales and profit with charts

Backend: `GET api/Dashboard/Sales?fromDate=&toDate=&terminalId=&top=20` (max 366 days), StockSystem.md §6.9.

```
Add a page "Sales analysis" (sidebar group "Sales", route /sales-analysis). Don't change other pages.

1) API: GET /Dashboard/Sales?fromDate=yyyy-MM-dd&toDate=yyyy-MM-dd&terminalId=&top=20 →
     { fromDate, toDate, terminalId,
       totals: (same shape as Today's totals),
       daily: [{ saleDate, bills, refunds, netSales, discount, cost, profit, costedSales, marginPct, cash, card, other }]   // every day, 0 when none
       terminals: [{ terminalId, terminalCode, terminalName, bills, netSales, profit, ... }],
       hourly: [{ saleHour, bills, netSales, profit }],
       topItems: [...], topProfitItems: [...]   // { itemId, name, qty, netSales, cost, profit, marginPct, hasUncosted }
       categories: [{ catId, catName, qty, netSales, profit, marginPct }] }
   400 { message } for a bad range → red toast.

2) Filters bar (sticky): date range picker (From – To, dd/MM/yyyy) with presets: Today, Yesterday, Last 7 days,
   This month, Last month, Last 30 days (default), This year. Till select ("All tills" + terminals). "Apply" reloads.
   Keep the filters in the URL query (?from=&to=&till=) so a view can be shared / reloaded.

3) Summary tiles: Net sales, Profit, Margin %, Bills, Avg bill, Discount, Refunds, Cash / Card / Other.
   Also "Best day" (highest netSales in daily, with its date) and "Daily average" (netSales / days with bills).
   uncostedSales > 0 → muted note "Rs x of sales have no cost price — not in profit".

4) Charts (shadcn chart / Recharts, responsive, tooltips with all values):
   a) "Daily sales and profit": bars = netSales per day, line = profit, second line (right axis, %) = marginPct.
      X axis dd/MM (or MMM yyyy when the range > 90 days — then group daily rows by month on the page).
      Toggle buttons: Sales · Profit · Margin to show/hide series.
   b) "Payments": stacked bars per day of cash / card / other.
   c) "Busy hours": bar chart of netSales by hour (hourly), bills in the tooltip.
   d) "Sales by category": horizontal bar chart (top 10 categories by netSales) with profit next to it; the rest in a
      table below.
   e) "Sales by till": small bar chart or table from terminals (bills, sales, profit).

5) Tables:
   - Top items: tabs "By sales" (topItems) / "By profit" (topProfitItems): Item, Qty, Sales, Cost, Profit, Margin %.
     itemId 0 = "Other items (not in item list)"; hasUncosted → "no cost" badge. Negative profit in red.
   - Daily table under chart (a): Date, Bills, Refunds, Sales, Discount, Cost, Profit, Margin %, Cash, Card, Other,
     with a totals row. "Export CSV" button for this table.

6) Loading skeletons while fetching; empty state "No sales in this period" when totals.bills = 0 and refunds = 0.
```

---

## Prompt 19 — Cashier billing: shortcut keys for every function, assignable, touch still works

No backend change. Every till function works **both** ways: tap the button on the touch screen, or press its key.
The keys live in one table that a supervisor can change on the till. Fixes the F9 clash (Prompt 11 Other item and
Prompt 14 Bill copy both used F9 — Bill copy moves to Ctrl+B).

```
Change the existing cashier billing screen (src/pages/CashierBilling.tsx). Add src/lib/tillShortcuts.ts and
src/components/till/ShortcutSettingsDialog.tsx. Keep every function working exactly as it does now — this change is
only about HOW a function is started: by touch (button) or by keyboard (shortcut), both must do the same thing.

1) One action list — src/lib/tillShortcuts.ts
   export type TillAction =
     "search" | "qty" | "price" | "voidLine" | "clearBill" | "pay" | "refund" | "wholesale" | "lineWR" |
     "discountPct" | "otherItem" | "suspend" | "recall" | "billCopy" | "noSale" | "profit" | "cashMenu" |
     "reload" | "dayEnd" | "shortcuts";
   Each action has: label (button text), description (one line), and up to 2 keys (primary + alternate).
   Defaults (primary key; alternate empty):
     search      F1        Search item by name (opens the Search dialog)
     qty         F2        Qty of the selected line
     price       F3        Price of the selected line (open price / other item only)
     pay         F4        Pay (tender dialog)
     reload      F5        Reload items from back office
     discountPct F6        Bill discount %
     lineWR      F7        Selected line retail / wholesale
     wholesale   F8        Wholesale default for new lines
     otherItem   F9        Other item
     suspend     F10       Suspend bill
     recall      F11       Recall bill
     cashMenu    F12       Cash menu (Paid in / Paid out / Opening cash / Drawer summary)
     voidLine    Delete    Void the selected line
     clearBill   Ctrl+Delete  Void the whole bill (confirm first)
     billCopy    Ctrl+B    Bill copy (moved from F9)
     noSale      Ctrl+D    No sale — open drawer
     profit      Ctrl+P    Profit view
     refund      Ctrl+R    Refund mode
     dayEnd      Ctrl+E    Day end
     shortcuts   Ctrl+K    Shortcut keys (list / change)
   Store a key as a string built from the KeyboardEvent: modifiers in the order Ctrl+Alt+Shift, then event.code
   for numpad keys ("NumpadMultiply", "NumpadAdd", …) and event.key otherwise ("F2", "Delete", "B").
   Show it nicely: "Ctrl+B", "Num *", "Num +", "Del".
   Export: getShortcuts(), saveShortcuts(map), resetShortcuts(), keyFromEvent(e), formatKey(k), findAction(k).

2) Where the keys are kept
   - localStorage "till.shortcuts.v1" on THIS till PC: { version: 1, keys: { [action]: [primary, alternate] } }.
     Wrap every read/write in try/catch. Missing, broken or unknown data → use the defaults (never crash the till).
     An action missing from saved data (added in a later version) gets its default key if that key is still free.
   - Also keep "till.showKeyHints" (true by default) — see 4.

3) One keyboard listener for the whole screen (window keydown, capture phase), replacing ALL existing per-key
   handlers for the actions above (including F5 Reload, F7, F8, F9, F10, F11, F12, F6, Ctrl+D, Ctrl+P from earlier
   prompts) so there is exactly one place that maps keys to actions:
   - k = keyFromEvent(e); action = findAction(k). No action → do nothing (let the key through — the scan box and
     inputs must keep working, and the barcode scanner types digits/letters + Enter into the scan box).
   - Action found → e.preventDefault() + e.stopPropagation() (stops the browser's F1 help, F5 refresh, Ctrl+P print,
     Ctrl+D bookmark, Ctrl+R reload, F11 full screen, …), then run the action.
   - While ANY dialog is open, global shortcuts are OFF (the dialog's own keys work: Enter, Esc, arrows, numbers).
     When the shortcut settings dialog is recording a key, it gets the key instead.
   - Run the action through the SAME function the button's onClick calls — runAction(action). No separate code path
     for keys. If the button is disabled right now (e.g. Pay with no lines, Suspend while the tender dialog is open,
     Discount % in refund mode, Price on a normal-price line), the key does nothing and shows a short grey toast
     with the reason ("No lines on the bill", "Select a line first", …) instead of failing silently.
   - Ignore auto-repeat (e.repeat) so holding a key never opens a dialog twice or pays twice.
   - After any action that does not open a dialog, put focus back in the scan box.

4) Touch — every action is also a button, and the button shows its key
   - Every action in the list has a visible button on the screen (toolbar, line toolbar, totals panel or the Cash menu).
     Add the ones that are missing: "Search", "Void line", "Void bill", "Day end", and a keyboard icon button "Keys".
   - Buttons are touch-sized: at least 48 px high, 8 px apart, no hover-only actions, no double-click-only actions,
     no tiny icons without text. Line selection is a single tap on the line (selected line clearly highlighted).
   - Each button shows its primary key as a small chip in the top-right corner ("F2", "Ctrl+B"), taken from
     getShortcuts() — so after a change the chips update immediately. Hidden when showKeyHints is false.
   - A tap must not steal focus into the button forever: after the action, focus goes back to the scan box (same as 3).
   - Search dialog on a touch-only till: add a "⌨" button in the search box that shows a simple on-screen A–Z / 0–9
     keyboard (big keys, Space, Backspace, Clear) under the input. The numeric keypad on the right keeps typing into
     the focused field as today.

5) Shortcut keys dialog ("Keys" button / Ctrl+K)
   - Anyone can OPEN it to see the list: table Function (label + description), Key, Alternate key. Sorted like the list in 1.
   - Changing keys needs the supervisor PIN (same PIN dialog / token as Refund). Button "Change keys" → PIN → edit mode.
   - Edit mode: tap a Key or Alternate cell → it shows "Press a key…" and the NEXT keydown is recorded (Esc = cancel
     recording, Backspace = clear that cell). Big "Clear" button per cell for touch.
   - Allowed keys: F1–F12 (with or without Ctrl/Alt/Shift), Ctrl/Alt + a letter or digit, Delete, Insert, Home, End,
     Page Up, Page Down, and the numpad operator keys (Num * / + / − / /) — with or without modifiers.
     Refused with a red message under the table:
       • plain letters, digits and symbols, Space, Enter, Tab, Esc, Backspace, arrow keys
         ("This key is used for typing / scanning");
       • keys the browser or Windows will not give up: Ctrl+W, Ctrl+T, Ctrl+N, Ctrl+Shift+N, Ctrl+Tab, Ctrl+Shift+Tab,
         Alt+F4, Alt+Tab, Ctrl+Alt+Delete, Windows key ("Windows keeps this key").
   - Same key on two functions → show "F2 is already used by Qty — use it here instead?" [Move it] [Cancel].
     Move → the other function loses that key. Never save two functions on one key.
   - Toggle "Show keys on buttons" (showKeyHints).
   - Buttons: Save (writes localStorage, green toast "Shortcut keys saved"), Reset to defaults (confirm), Cancel (Esc).
   - "Print list" → small window with the table, for a sticker next to the till.

6) Status bar: a muted hint "Ctrl+K keys" at the right end (hidden when showKeyHints is false).

7) Do not change any function's behaviour, rules, PIN checks or API calls — only how it is started.
```

---

## Prompt 20 — Exports page (common) + weighing scale item file

Backend: `ExportController` (`api/Export`), `DBScript/05_BackOffice_Export.sql`, StockSystem.md §6.10. The API server
writes the file into a folder (local drive or a network share like `\SCALE-PC\Import`) — the browser never picks the
folder. Scale items = active items with unit **KGS**; their **Ref code** is the 5-digit scale code.

```
Add a page "Exports" (sidebar group "Tools", route /exports). Use the existing API helper. Don't change other pages.
It is a COMMON page: one card per export from GET /Export. Today there is one ("SCALE" — Weighing scale items);
build it so a new export type only needs a new card body.

1) API
   GET  /Export → ExportSetting[] { exportCode, name, folderPath, fileName, nameMaxLength, lastExportAt, lastExportBy,
                                    lastLineCount }
   PUT  /Export/{code} { folderPath, fileName, nameMaxLength, userId } → { message, data: ExportSetting }  (400 { message })
   GET  /Export/SCALE/Preview → {
          setting: ExportSetting, filePath: string | null,
          lines:   { itemId, refCode, plu, descrip, price, change: "new" | "changed" | "same", changes: string[], warning?: string }[],
          skipped: { itemId, refCode, descrip, price, reason }[],
          removed: { itemId, plu, descrip, price }[],
          newCount, changedCount, hasChanges }
   POST /Export/SCALE/Run { userId } → { message, data: { filePath, lineCount, skippedCount, newCount, changedCount,
                                         removedCount, exportedAt } }   (400 { message } — folder missing / no access)
   GET  /Export/SCALE/Download → the text file (blob; save with the fileName from Content-Disposition)
   GET  /Export/{code}/Log?top=20 → { exportLogId, filePath, lineCount, skippedCount, status: 1 | 9, error, userId, cDate }[]
   Send userId from the logged-in user if the app has one, else omit it.

2) Export card header: name, "Last export: dd/MM/yyyy HH:mm · N items" (or "Never exported" in orange), and the full
   file path in monospace. Buttons: "Settings", "Download", "Export now" (primary).

3) Settings (dialog): Folder (text, placeholder "D:\Scale  or  \SCALE-PC\Import"), File name (default ScaleItem.txt),
   "Max name length on the scale" (number, 0 = no limit). Muted hint under Folder: "A folder on the server PC (or a shared
   folder the server can write to). The scale program reads the file from here." Save → PUT; 400 → show the message
   under the Folder field (e.g. folder not found) and keep the dialog open. Green toast on success, then reload.
   When folderPath is empty, the card shows an orange note "Set the export folder first" and Export now is disabled.

4) Scale card body (loads GET /Export/SCALE/Preview on open, and a "Refresh" icon button):
   - Summary chips: "N items", "New N" (green), "Price/name changed N" (blue), "Removed N" (grey), "Left out N" (red).
     hasChanges false → green text "The scale is up to date with the last export."
   - Tabs:
       "Changes" (default when hasChanges): new + changed lines and the removed list.
           Columns: Code (plu), Item (descrip), Price (2 decimals, right), What changed (changes joined with " · ",
           or a "New" badge; removed rows have a "Removed" badge and are struck through).
       "All items": every line — Code, Item, Price, badge for new/changed, warning (e.g. "Name cut to 30 characters")
           as a small amber note. Search box filters by code or name. Sorted by code.
       "Left out": skipped rows — Ref code, Item, Price, Reason (red). Hint above: "Fix these in Item Entry (unit KGS,
           Ref code = 5-digit scale code, retail price), then Refresh."
   - Preview of the file: a collapsible "File preview" with the first 20 lines in monospace, built exactly as
     `${plu}#${descrip}#${price.toFixed(2)}#` so the user sees the format the scale gets.

5) Export now → confirm dialog "Write N items to <filePath>?" (+ "Left out: N" in red when skipped > 0)
   → POST /Export/SCALE/Run. Spinner, button disabled while running (no double clicks).
   OK → green toast with the message, then reload the card (the Changes tab is now empty) and the log.
   400 → red toast with the message (folder missing, no write access…). Nothing is marked as exported.

6) Download → GET /Export/SCALE/Download, save the file in the browser. Muted note next to the button:
   "Download doesn't count as an export — the Changes list stays."

7) "History" section at the bottom of the card: last 20 from GET /Export/SCALE/Log — Time (dd/MM/yyyy HH:mm), Items,
   Left out, Result (green "Written" / red "Failed" with the error), File path.
```

---

## Prompt 21 — Customers page + Quotation / Invoice settings

Backend: `CustomerController` (`api/Customer`), `SalesDocController` settings + logo, StockSystem.md §6.11.

```
Add two pages under a new sidebar group "Sales docs": "Customers" (/customers) and "Document settings"
(/sales-doc-settings). Use the existing API helper. Don't change other pages.

1) Customers page (kept simple on purpose — only these fields):
   - API: GET /Customer?text=&top=200 → [{ customerId, name, address, phone, email }]
          POST /Customer { name, address, phone, email, userId } → { message, data }
          PUT /Customer/{id} (same body) → { message, data };  DELETE /Customer/{id}?userId= → { message }
          400 { message } (e.g. "A customer named 'X' already exists.") → red toast / under the field.
   - Search box (name or phone, 300 ms after typing stops), table: Name, Address, Phone, Email, edit + delete icons.
   - "New customer" button → dialog: Name (required, max 100), Address (one line, max 200), Phone (max 20),
     Email (optional, max 100). Enter = Save, Esc = Cancel. Same dialog for edit.
   - Delete → confirm "Delete <name>? Quotations and invoices already made keep the customer's details."
   - Reuse this dialog as a component (CustomerDialog) — Prompt 22 opens it from the document screen.

2) Document settings page (what prints on the PDF):
   - GET /SalesDoc/Settings → { companyName, companyAddress, companyPhone, companyEmail, logoFile, quotationValidDays,
     quotationTerms, invoiceTerms };  PUT /SalesDoc/Settings (same fields + userId) → { message, data }.
   - Form: Company name (required), Address, Phone, Email, "Quotation valid for (days)" (1–365, default 14),
     Quotation terms (textarea, max 1000), Invoice terms (textarea, max 1000). Save → green toast.
   - Logo card: shows GET /SalesDoc/Settings/Logo as an image (404 → "No logo"). "Upload logo" (PNG/JPG, max 2 MB,
     check on the page too) → POST /SalesDoc/Settings/Logo (multipart field "file", plus "userId") → reload the image
     (add ?t=<timestamp> to the URL). "Remove" → DELETE /SalesDoc/Settings/Logo.
```

---

## Prompt 22 — Quotations & Invoices (list, editor, PDF, make invoice, cancel)

Backend: `SalesDocController` (`api/SalesDoc`), StockSystem.md §6.11. **Document only** — no stock or customer balance
effect, no tax. Quotations and invoices are editable while open. One quotation → one invoice.

```
Add pages under the "Sales docs" sidebar group: "Quotations" (/quotations) and "Invoices" (/invoices) — the SAME
component with docType 1 or 2 — plus the editor (/quotations/new, /quotations/:id, /invoices/new, /invoices/:id).

1) API
   POST /SalesDoc/Search { docType, fromDate, toDate, customerId, text, status, page, pageSize } →
        { total, rows: [{ docId, docType, docNo, docDate, validUntil, customerId, custName, reference, lineCount,
                          netAmount, status, fromDocId, fromDocNo, invoiceDocNo, cDate }] }
   GET  /SalesDoc/{id} → { doc: { docId, docType, docNo, docDate, validUntil, customerId, custName, custAddress, custPhone,
                                   reference, notes, grossAmount, discount, netAmount, status, fromDocId, cancelReason,
                                   items: [{ lineNum, itemId, descrip, qty, unitPrice, discount, amount }] },
                           fromDocNo, invoiceDocId, invoiceDocNo }
   POST /SalesDoc { docType, docDate, validUntil, customerId | (custName, custAddress, custPhone), reference, notes,
                    discount, userId, items: [{ itemId, descrip, qty, unitPrice, discount }] } → { message, data: doc }
   PUT  /SalesDoc/{id} (same body, open quotations and invoices) → { message, data: doc }
   POST /SalesDoc/{id}/ToInvoice { docDate?, userId } → { message, data: invoice }
   POST /SalesDoc/{id}/Cancel { reason, userId } → { message, data: doc }
   GET  /SalesDoc/{id}/Pdf            → PDF inline (open in a new tab to view / print)
   GET  /SalesDoc/{id}/Pdf?download=true → PDF download (<docNo>.pdf)
   Items for the line picker: existing GET /Itemz/Search?query= → [{ itemId, refCode, barcode, descrip, retailPrice,
   wholesalePrice, ... }].  400 { message } anywhere → red toast with the message, keep the form as it is.
   Status: 1 Open, 2 Invoiced (quotation), 9 Cancelled.

2) List page
   - Filters: date range (default this month), status select, search (doc no / customer / reference), customer picker.
     Paged 50 per page, newest first.
   - Columns: No, Date, Customer, Reference, Lines, Amount (2 decimals, right), Status badge
     (Open blue, Invoiced green with "→ INV000012", Cancelled grey + strike-through amount).
     Quotations also: Valid until (red "Expired" when before today and still Open).
     Invoices also: "From QT000005" link when fromDocNo.
   - Row actions: View PDF (new tab), Download PDF, Open. "New quotation" / "New invoice" button.

3) Editor (new / open quotation; new / open invoice). Opening a Cancelled document, or a quotation that is Invoiced,
   shows the same layout READ-ONLY with its actions (see 5).
   - Header: Customer combobox (search GET /Customer?text=, shows name + phone) with "+ New customer" (CustomerDialog from
     Prompt 21; select it after saving) and a "One-off customer" switch → Name (required), Address, Phone inputs instead.
     Date (default today). Quotations: Valid until (default empty = server uses date + settings days; show the hint
     "Default: <quotationValidDays> days" from GET /SalesDoc/Settings). Reference ("Customer PO / ref", max 50).
   - Lines table: #, Item / Description, Qty, Unit price, Discount, Amount, delete icon.
       • Add line row: item search (GET /Itemz/Search, 300 ms debounce, ↑/↓/Enter) → fills descrip and unitPrice from
         retailPrice; a small "Retail / Wholesale" toggle above the table decides which price is filled
         (wholesalePrice, falling back to retailPrice). The price stays editable.
       • "+ Typed line" → itemId 0, type the description (services, transport, items not in the list).
       • Description stays editable on item lines too (max 200).
       • Qty > 0 (3 decimals), price ≥ 0, discount 0…qty×price. Amount = qty × price − discount, live.
       • Enter in Qty → next field; Enter in the last field → back to the item search. Max 200 lines.
   - Totals (right): Sub total, Discount (amount input, 0…sub total), Total (big, bold). No tax.
   - Notes (textarea, max 500, "printed under the lines").
   - Buttons: Save (Ctrl+S) → POST or PUT → green toast, go to /<type>/:id. "Save & PDF" → save then open the PDF in a
     new tab. Leaving with unsaved changes → confirm.

4) Saved quotation (Open): Edit stays possible. Extra buttons: "View PDF", "Download PDF",
   "Make invoice" → confirm "Make an invoice from QT… (Rs <total>)?" with an optional Invoice date (default today) →
   POST /ToInvoice → green toast "Invoice INV… made" → open the new invoice. "Cancel quotation" (see 5).

   Saved invoice (Open): Edit stays possible (same editor, PUT). Extra buttons: "View PDF", "Download PDF",
   "Cancel invoice" (see 5). Banner "From quotation QT…" (link) when fromDocNo — editing the invoice does NOT change the
   quotation.

5) Read-only views
   - Invoiced quotation: green banner "Invoiced → INV…" (link). No edit, no cancel (cancel the invoice first).
   - Cancelled: grey banner "Cancelled — <cancelReason>"; PDF still available (it prints CANCELLED).
   - Cancel dialog: Reason (required, max 200) → POST /Cancel → toast, reload. Cancelling an invoice made from a
     quotation tells the user: "QT… is open again and can be invoiced again."
```
