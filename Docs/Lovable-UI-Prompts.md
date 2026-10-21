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

---

## Prompt 23 — Back office sign-in, Users page, token on every call

Backend: `AuthController` (`api/Auth`), `UsersController` (`api/Users`), StockSystem.md §6.12. The API only REQUIRES the
token after `Auth:Enforce` is turned on — build this first, then turn it on. The till billing page (/billing) is NOT part
of this (it signs cashiers in at the till — Prompt 24).

```
Add sign-in to the back office app. Don't change what the existing pages do.

1) src/services/auth.ts
   - Keep { token, expiresAt, user: { userId, loginName, userName, roleId, roleName } } in localStorage "auth".
     Also set localStorage "userId" = user.loginName and "userName" = user.userName (GRN / Goods Return already read
     "userId"); remove all of these on sign out.
   - getToken(), getUser(), isAdmin() (roleId 1), signOut(), and an "auth changed" event so the layout re-renders.
   - API (use createApiClient("Auth")):
       GET  /Auth/Status → { setupNeeded, enforced }
       POST /Auth/Setup { loginName, userName, password } → same answer as Login
       POST /Auth/Login { loginName, password } → { token, expiresAt, user }   (401 { message } when refused)
       GET  /Auth/Me → user   (401 → signed out)
       POST /Auth/ChangePassword { currentPassword, newPassword } → { message }

2) src/services/apiClient.ts — every client from createApiClient:
   - request interceptor: Authorization: Bearer <token> when signed in;
   - response interceptor: 401 from any route except /Auth/Login and /Auth/Setup → signOut() and go to
     /login?next=<current path> (toast "Please sign in again"). Keep the existing error handling otherwise.
   - TodayDashboard SignalR: .withUrl(salesHubUrl, { ..., accessTokenFactory: () => getToken() ?? "" }).
   - salesDocApi openPdf / downloadPdf: fetch the PDF through the api client with responseType "blob" (so the token is
     sent), then open / download an object URL. Don't open the bare URL any more. The logo URL stays as it is (public).

3) /login page (outside AppLayout, centred card, shop name on top):
   - On load GET /Auth/Status. setupNeeded → "Create the first admin" form: Name, User name, Password, Confirm password
     (6+ characters) → POST /Auth/Setup → signed in → go to "/".
   - Else the sign-in form: User name, Password (show/hide eye), "Sign in" (Enter). 401 → show the message under the
     form ("Wrong user name or password.", "Too many wrong passwords. Try again after 11:07.", "Cashiers sign in at the
     till…"), clear the password, keep the user name. Then go to ?next or "/".
   - Already signed in → go to "/".

4) Guard: wrap the AppLayout route group (NOT /billing, NOT /login) in <RequireAuth>: no token or expired → /login?next=.
   On app start, when there is a token, call GET /Auth/Me once; 401 → sign out.

5) Top bar (AppLayout): user's name + role chip, menu: "Change password" (dialog: current, new, confirm; 6+ chars →
   POST /Auth/ChangePassword → green toast) and "Sign out".

6) Users page (/users, sidebar group "Settings", shown only to admins; non-admins opening it see "Admins only"):
   API (createApiClient("Users")):
     GET  /Users?text=&includeDisabled= → [{ userId, loginName, userName, roleId, roleName, status, phone, email,
                                             lastLoginAt, isLocked, createdDate }]
     POST /Users { loginName, userName, roleId, password, phone, email } → { message, data }
     PUT  /Users/{id} { userName, roleId, status, phone, email } → { message, data }
     POST /Users/{id}/ResetPassword { newPassword } → { message }
     400 { message } → red toast / under the field.
   - Search box + "Show disabled" switch. Table: Name, User name, Role chip (Admin purple, Back office blue, Cashier
     green), Phone, Last sign-in (dd/MM/yyyy HH:mm or "never"), Status (Active / Disabled grey / "Locked" orange when
     isLocked), actions: Edit, Reset password, Disable / Enable.
   - "New user" dialog: Name, User name (3–20 letters/digits . _ -, no spaces; hint "Can't be changed later — it is
     printed on bills"), Role (radio with one-line meaning: Admin = everything + users; Back office = back office only;
     Cashier = tills only), Password + Confirm (hint: 6+ characters, cashiers 4+), Phone, Email.
   - Edit dialog: same without User name / password. Changing a Cashier to Admin / Back office shows a hint:
     "Back office passwords need 6+ characters — reset the password if it is shorter."
   - Reset password dialog: New password + Confirm → also unlocks. Disable → confirm "Disable <name>? They are signed out
     now; tills stop accepting them within 5 minutes."
   - Footer note: "Cashier changes reach the tills within 5 minutes (or press Reload on the till)."
```

---

## Prompt 24 — Till billing page: cashier sign-in screen

Backend: TillService `POST /auth/cashier`, `GET /auth/cashier`, `DELETE /auth/cashier`, header `X-Cashier-Token`
(TillService README). Checked on the till — works offline. Cashiers are made in the back office Users page (Prompt 23).
TillService only REQUIRES it after `Till:RequireSignIn` is turned on.

```
Change the cashier billing page (src/pages/CashierBilling.tsx) and src/services/tillLocalApi.ts. Keep everything else.

1) tillLocalApi.ts
   - cashierSignIn(loginName, password) → POST /auth/cashier → { token, expiresAt, userId, loginName, userName, roleId }
     (401 { message } refused; 400 { message } "No cashier accounts on this till yet…")
   - cashierMe() → GET /auth/cashier (401 = not signed in);  cashierSignOut() → DELETE /auth/cashier
   - Keep the session in sessionStorage "till.cashier" (token + names) so a page refresh keeps the cashier signed in;
     the browser closing signs out. Every call sends X-Cashier-Token when there is one (next to X-Supervisor-Token).
   - Any 401 with { signInRequired: true } → clear the session and show the sign-in screen (keep the bill on screen
     in memory; after sign-in the same bill is still there).

2) Sign-in screen (full screen over the billing page, touch friendly, big inputs and buttons):
   - Shop / till code on top (from GET /sync/status terminalCode), "Cashier sign in".
   - User name, Password (numeric keypad on screen too — cashier passwords are often 4 digits), "Sign in" (Enter).
   - 401 / 400 → the message in red under the form, clear the password.
   - Status line at the bottom: Online/Offline dot from /sync/status and a "Reload" button (POST /sync/now — works before
     sign-in, so a new till can download its cashiers).
   - On load: if sessionStorage has a token → GET /auth/cashier; ok → straight to billing, 401 → show this screen.
   - While TillService has sign-in turned off (calls work without a token), still show this screen; a "Skip" link is
     NOT offered — cashiers always sign in.

3) Billing page with a cashier signed in:
   - Status bar "Cashier: <userName>" from the session (replace localStorage "userId"/"userName"). Send cashierId =
     session.loginName where the page sent it before (the till uses the signed-in cashier anyway).
   - "Sign out" button (status bar, icon LogOut, shortcut via the shortcut-key table: action "signOut", default Ctrl+L):
     if the bill has lines → "Suspend the bill or finish it before signing out." and stop; else confirm → cashierSignOut()
     → clear supervisor token too → sign-in screen.
   - Day end: after the Z is closed, sign the cashier out (next shift signs in).
```

---

## Prompt 25 — Cashier billing: quantity before the scan ("5*" then scan)

No backend change — the till already takes any quantity on a line. Today 5 of an item = scan → Qty → 5 → Enter.
After this: type `5*` and scan (the scanner adds the barcode and Enter) → one line with qty 5.

```
Change src/pages/CashierBilling.tsx and src/lib/tillShortcuts.ts. Keep everything else (the Qty button still works).

1) Read a quantity in front of the code — in submitInput, scan mode only:
     const m = v.match(/^(\d+(?:\.\d{1,3})?)\s*\*\s*(.*)$/);
   - m → qty = Number(m[1]), code = m[2].trim(). No "*" → qty 1 exactly as today.
   - qty <= 0 → toast.error("Quantity must be more than 0").
   - code empty (cashier typed "5*" and pressed Enter) → put "5*" back in the box and toast.info("Now scan the item").
   - text starts with "*" (e.g. "*4252") → toast.error("Type the quantity before *, e.g. 5*").
   - qty > 999 (usually a barcode scanned before the "*") → confirm dialog "Add <qty> × <item name>?" after the item
     is found, with Cancel focused (Enter must NOT add it by accident).
   - 1.25* works for loose / weighed items (up to 3 decimals).

2) Carry the quantity through every add path (it is 1 everywhere today):
   addItem(code, qty = 1) → processItem(item, qty) → the price link picker state keeps qty → addLine(item, opt, qty).
   - New line: qty = qty, unitPrice = linePrice(item, qty, link, type, 0) — so a quantity price applies at once
     (5* of an item with "buy 3+ at 218" is priced 218).
   - Existing line (same merge rule: same itemId + price link + price type): qty = l.qty + qty, re-priced with linePrice.
   - Name search: "5*sugar" with several results → the search dialog remembers qty; the picked row is added with it.
     (The Search button dialog adds 1.)
   - Price link picker: chosen price + qty; Esc cancels and adds nothing.
   - Open price item: the line gets qty, then "Enter the price" as today. Sale locked items: refused as today.
   - Refund mode: same (refund line with that qty). "Other item": unchanged (it has its own Qty field).
   - After adding, the new / merged line is selected and the scan box is empty and focused.

3) Show that a quantity is waiting: while the scan box text matches /^\d+(\.\d{1,3})?\s*\*/ show a blue chip at the right
   end of the box "× 5". Placeholder: "Scan / enter code   ·   5* then scan = 5 pcs".

4) On-screen keypad (touch): add a "×" key that types "*". Layout:
     7 8 9 ⌫
     4 5 6 C
     1 2 3 ×
     0 00 . Enter        (Enter is one row high now)
   On the physical keyboard "*" (Num * or Shift+8) just types into the box.

5) tillShortcuts.ts: "*" is the quantity key now.
   - validKey: refuse NumpadMultiply (with or without modifiers) — "Num * is the quantity key (5* then scan)".
   - getShortcuts(): drop any saved NumpadMultiply assignment (an older saved map may have one).
   - The global key listener never treats "*" as a shortcut while the scan box has focus.
```

---

## Prompt 26 — Cashier billing: "Other item" dialog — description "Other", price first, Enter adds

No backend change.

```
Change the "Other item" dialog in src/pages/CashierBilling.tsx only.

1) openOther(): description starts as "Other" (not empty), qty "1", and the field the keypad types into
   (otherField) starts as "price":  setOtherField("price"); setOther({ descrip: "Other", price: "", qty: "1" }).

2) Focus: the Price input gets the focus when the dialog opens (move autoFocus from Description to Price).
   Description: select all its text when it gets focus (onFocus → e.target.select()), so the cashier can tap it and
   type a different name straight over "Other".

3) Enter adds the line from ANY field: wrap the fields in <form onSubmit={(e) => { e.preventDefault(); addOther(); }}>
   and make "Add" the form's submit button (type="submit", the default button); "Cancel" is type="button".
   Remove the Qty-only onKeyDown. Esc still cancels.
   - Price empty or 0 → toast "Enter the price", keep the dialog open, focus Price.
   - Description cleared → toast "Enter a description", focus Description. (Same checks addOther already has.)

4) On-screen keypad in the dialog: add an "Enter" key (same as the Add button) so a touch till can do
   Other item → type price on the keypad → Enter. Layout: 7 8 9 ⌫ / 4 5 6 C / 1 2 3 . / 0 00 Enter (Enter 2 wide).

Fast path after this: F9 → type the price → Enter → the line "Other", qty 1, is on the bill and the scan box is focused.
```

---

## Prompt 27 — Cashier billing: focus fixes, arrow keys on the bill, Card / Mixed keys, bill copy Space

No backend change. Fixes from using the till.

```
Change src/pages/CashierBilling.tsx and src/lib/tillShortcuts.ts. Keep everything else.

1) Focus that lands in the right box — the root causes, fix them once for every dialog:
   - Radix Dialog moves focus to its own first element when it opens, so `autoFocus` on an Input is not reliable.
     For EVERY dialog that has a "first field", give that field a ref and use
       <DialogContent onOpenAutoFocus={(e) => { e.preventDefault(); ref.current?.focus(); ref.current?.select(); }}>
     First fields: Supervisor PIN dialog → the PIN input (used for refund, wholesale, profit, discount, cancel suspended,
     change keys); No Sale → PIN; Opening cash / Paid In / Paid Out → Amount; Bill discount → %; Suspend → note;
     Bill copy → invoice no filter; Other item → Price.
   - focusScan() must do nothing while any dialog is open (use the existing anyDialog flag), so a late focusScan from
     the action that opened the dialog can't pull the focus back to the scan box.
   - The "Cash" dropdown menu: <DropdownMenuContent onCloseAutoFocus={(e) => e.preventDefault()}> so closing the menu
     does not move focus to its trigger button after the Paid In / Paid Out / Opening cash dialog has opened.
   - Same for the "No opening cash" chip that opens the Opening cash dialog.

2) Opening cash / Paid In / Paid Out dialog: Enter saves from anywhere in the dialog.
   - Wrap the fields in <form onSubmit={(e) => { e.preventDefault(); saveCash(); }}>; the "Save" button becomes the
     submit button (type="submit", primary, text "Save (Enter)"); "Cancel"/"Later" and the reason chips are type="button".
     Remove the INPUT-only onKeyDown. Esc cancels.
   - Amount empty / 0 → toast "Enter the amount" and focus Amount. PIN missing where needed → toast "Enter the supervisor
     PIN" and focus PIN. Wrong PIN (401) → clear the PIN and focus it.

3) Void line keeps a sensible selection: after removing the selected line select the line that was ABOVE it (or the new
   first line when the top line was voided; nothing when the bill is empty), scroll it into view, and focus the scan box.
   Same after "Void bill" of the last line → nothing selected, scan box focused.

4) Arrow keys move through the bill (main screen, no dialog open, focus in the scan box or nowhere):
   - ↑ / ↓ select the previous / next line (stop at the ends, no wrap); Home / End = first / last line.
   - With nothing selected, ↑ selects the last line and ↓ the first.
   - Scroll the selected line into view (scrollIntoView({ block: "nearest" })). Keep the focus in the scan box, so
     Qty / Price / Void / W-R then work on that line and scanning still works.
   - Do not handle the arrows when a dialog is open (the dialogs already use them).

5) Shortcut keys for Card and Mixed:
   - tillShortcuts.ts: add actions "payCard" (default Shift+F4, label "Card", "Pay by card") and "payMixed" (default
     Ctrl+M, label "Mixed", "Cash + card"). Rename the label of "pay" to "Cash" ("Pay in cash"). A saved map from before
     gets the new defaults when those keys are free (existing rule).
   - runAction: "payCard" / "payMixed" do the same checks as "pay" (no lines, discount too high) and then openPay("card")
     / openPay("mixed"). The Card and Mixed buttons call runAction too and show their key chips like Cash (F4).

6) Bill copy dialog — Space previews, tap previews:
   - Space anywhere in the dialog (also while the invoice-no box has the focus — invoice numbers never contain spaces)
     → e.preventDefault() and preview the highlighted bill. Replace the `tag !== "INPUT"` condition.
   - Tapping a row: highlight it and preview it (keep), and put the focus back in the invoice-no box so ↑ / ↓ / Enter /
     Space keep working after a tap. The preview panel scrolls to the top for each new bill.
```

---

## Prompt 28 — Cashier billing: payment dialog Enter = Complete (no double sale), one-key Card / Mixed, messages on top

No backend change.

```
Change src/pages/CashierBilling.tsx, src/lib/tillShortcuts.ts and (for the message position) src/App.tsx. Keep everything else.

1) Payment dialog (Cash / Card / Mixed): Enter completes the sale from ANY field.
   - Wrap the fields in <form onSubmit={(e) => { e.preventDefault(); finishSale(); }}>; "Complete" becomes the submit
     button (type="submit", primary, text "Complete (Enter)"); Cancel and the Exact / 500 / 1000 … chips are type="button".
     Remove the onKeyDown on the cash input. Esc cancels (not while saving).
   - Focus when the dialog opens (onOpenAutoFocus → preventDefault + ref.focus() + select(), like Prompt 27):
     Cash → "Cash given"; Card → "Card ref / approval no" (optional — Enter right away completes); Mixed → "Card amount".
   - NEVER SAVE A SALE TWICE: finishSale must stop at once when a save is already running. Use a ref, not only the busy
     state (state updates too late for a fast double Enter / held key):
       const savingRef = useRef(false);
       const finishSale = async () => {
         if (savingRef.current) return;
         if (!canFinish) { toast.error(...); focus the cash input; return; }
         savingRef.current = true; setBusy(true);
         try { ...as today... } finally { savingRef.current = false; setBusy(false); }
       };
     Also ignore e.repeat on Enter in this dialog.

2) One-key shortcuts for Card and Mixed (tillShortcuts.ts):
   - payCard default "NumpadAdd" (shown "Num +"), payMixed default "NumpadSubtract" (shown "Num −").
     Cash stays F4. A saved map that still has the old defaults (payCard Shift+F4, payMixed Ctrl+M) is moved to the new
     ones; a key the cashier set themselves is kept.
   - "Num +" / "Num −" only act as shortcuts on the main screen (no dialog open), like the other keys; inside a dialog
     they type normally.
   - The Card / Mixed buttons show the new chips.

3) Messages (toasts) on the till: put them where the cashier looks, not over the status bar / Reload area.
   - On /billing only: Sonner position "top-center", offset so the first message sits just under the scan box, over the
     bill lines — never covering the scan box, the Total or the pay buttons. Other pages keep bottom-right.
     (Move <Sonner /> inside <BrowserRouter> in App.tsx and pick the position from useLocation().pathname.)
   - On /billing: bigger text (text-base, title font-semibold), richColors (error red, warning amber, success green),
     at most 3 visible (visibleToasts={3}), durations: success 2 s, info / warning 3 s, error 5 s.
   - Messages that need an action stay until closed, as today (e.g. "Bill saved but NOT printed — Print again").
```

---

## Prompt 29 — Cashier billing: messages in the bottom bar, safer keys, scan box focused, No Sale reason

No backend change. Replaces the toast position from Prompt 28 on the till.

```
Change src/pages/CashierBilling.tsx, src/lib/tillShortcuts.ts, src/components/till/* and src/App.tsx. Keep everything else.

1) Messages in the bottom bar (middle), not floating toasts — on /billing only:
   - New src/lib/tillMessages.ts: a tiny store (useSyncExternalStore) with the same calls the page uses today:
       tillToast.success(text, opts?) / .error / .info / .warning / .dismiss()
     opts: { duration?: number (ms; Infinity = until closed), action?: { label: string; onClick: () => void } }.
     Keep the latest message plus the last 10 (history).
   - In CashierBilling.tsx and every till component it uses (ShortcutSettingsDialog, sign-in screen, …):
       import { tillToast as toast } from "@/lib/tillMessages";   (instead of sonner) — so no other code changes.
   - Show the message in the MIDDLE of the bottom status bar (between "bills waiting to upload" and "Cashier: …"):
       icon + text, text-base font-medium, one line (ellipsis, full text in title); colours: error = red background
       with white text, warning = amber, success = green, info = blue / muted. An action → a small button after the text
       (e.g. "Print again"); an × closes it.
     Durations: success 3 s, info / warning 5 s, error 8 s, with action → until closed. A new message replaces the old.
     Errors also play a short beep (Web Audio, 150 ms) so the cashier notices without looking.
   - Clicking the message area opens a small popover with the last 10 messages and their times.
   - The bottom bar must stay readable while a dialog is open: give it a z-index above the dialog overlay
     (e.g. relative z-[60] with the page background), so "No receipt printer is set on this till…" from the Bill copy
     dialog shows in the bar and is not dimmed.
   - App.tsx: remove the /billing-only Sonner settings from Prompt 28 — on /billing render no Sonner at all; other pages
     keep the normal bottom-right Sonner.

2) Keys that can't reload the page / single keys (tillShortcuts.ts):
   - Refund: default "NumpadDivide" (shown "Num /") instead of Ctrl+R (Ctrl+R is the browser's reload).
   - No Sale: default "Insert" instead of Ctrl+D.
   - A saved map that still has the old defaults (refund Ctrl+R, noSale Ctrl+D) is moved to the new ones; keys the cashier
     set themselves are kept.
   - validKey: refuse Ctrl+R, Ctrl+Shift+R, Ctrl+F5, Shift+F5 ("The browser reloads the page with this key").
   - Safety on /billing, ALWAYS (also while a dialog is open or the global shortcuts are off): a window keydown listener
     that calls preventDefault() for F5, Ctrl+R, Ctrl+Shift+R, Ctrl+F5 and Shift+F5 (F5 still runs the Reload action
     when no dialog is open). And a beforeunload handler that asks the browser to confirm leaving while the bill has lines.

3) Scan box focused when the page loads:
   - Focus the scan box on mount, right after a successful cashier sign-in, and when the sign-in screen closes.
   - When the browser window / tab gets focus back (window "focus" event) and no dialog is open → focus the scan box.
   - focusScan() keeps the "no dialog open" rule from Prompt 27.

4) No Sale dialog: the reason starts as "Change" (that chip selected, the text box filled); the PIN box has the focus
   (Prompt 27). Enter = Open drawer from any field (form submit, like the cash dialogs).
```

---

## Prompt 30 — Cashier billing: focus after "item not found", No Sale = Alt+O, line buttons restyled

No backend change.

```
Change src/pages/CashierBilling.tsx and src/lib/tillShortcuts.ts. Keep everything else.

1) Focus after an item is not found. Cause: the scan box has disabled={busy}; a disabled input loses the focus, and only
   the "item found" path puts it back.
   - Scan box: readOnly={busy} (with aria-busy and a small spinner at its right end) instead of disabled, so it keeps the
     focus while the till looks the item up.
   - addItem: in its finally block call focusScan() (it already does nothing while a dialog is open — the search list or
     price picker), so after "No item found for '…'" / "Item '…' not found" the cursor is back in the scan box and the
     wrong text is cleared, ready for the next scan.

2) No Sale shortcut = Alt+O:
   - tillShortcuts.ts: noSale default "Alt+O". A saved map that still has an old default (Ctrl+D or Insert) is moved to
     Alt+O; a key the cashier set themselves is kept.
   - keyFromEvent: for letters use e.code ("KeyO" → "O") so Alt+O works the same on every keyboard layout.
   - preventDefault on Alt+O so the browser menu does not react.

3) Line / mode buttons (Qty, Price, W/R, Void line, Refund, Wholesale) — make them like the Cash / Card / Mixed buttons:
   - Two rows of three, full width of the right panel, same height as each other (h-14), filled buttons, white text,
     icon above or left of the label, the key chip in the top-right corner (as now):
         [ Qty      ] [ Price     ] [ W/R       ]
         [ Void line] [ Refund    ] [ Wholesale ]
   - Colours (different from the blue pay buttons):
       Qty, Price, W/R  → slate (bg-slate-600, hover slate-700) — they change the selected line;
       Void line        → red (destructive);
       Refund           → purple (outline purple when off, filled purple + ring when refund mode is ON);
       Wholesale        → orange (outline orange when off, filled orange + ring when the wholesale default is ON).
     Disabled (e.g. Price on a normal-price line, nothing selected): same colour at 40 % opacity, still readable.
   - Labels never overflow: text-sm font-semibold leading-tight, allowed to wrap to two lines, min-w-0, no fixed widths;
     icons 18 px. Check at 1366×768 and 1920×1080 that "Void line" and "Wholesale" fit inside their buttons.
   - Touch: at least 56 px high, 6 px gap.
```

---

## Prompt 31 — Cashier billing: "000" key, one colour for the line / mode buttons

No backend change. Changes Prompt 30's colours.

```
Change src/pages/CashierBilling.tsx only. Keep everything else.

1) Keypad (right panel): add a "000" key (types "000", like "00"). New layout — 4 columns, Enter as a full-width bar:
       7    8    9    ⌫
       4    5    6    C
       1    2    3    ×
       0    00   000  .
       [        Enter        ]
   Same key style and font as now; Enter keeps the primary style. The keypad still fills the space it has (flex-1),
   rows equal height. The Other item dialog's keypad also gets "000" next to "00".

2) Line / mode buttons (Qty, Price, W/R, Void line, Refund, Wholesale): ONE colour for all six, a little different
   from the blue Cash / Card / Mixed buttons — a darker navy of the same blue family:
       className "bg-blue-900 hover:bg-blue-950 text-white"  (all six; drop the slate / red / purple / orange of Prompt 30)
   - "On" states keep the same colour and add a white inner ring so they still stand out:
       Qty / Price while the keypad types into them, Refund while refund mode is on, Wholesale while the wholesale
       default is on, W/R on a wholesale line → "ring-2 ring-inset ring-white".
     (Refund mode is still obvious from the red REFUND banner; wholesale from the orange banner.)
   - Disabled: same colour at 40 % opacity. Keep the two-rows-of-three layout, sizes, icons and key chips of Prompt 30.
```

---

## Prompt 32 — Cashier billing: on-screen keypad inside the payment dialog (and every number dialog)

No backend change. On a touch till the main keypad is under the dialog, so the cashier can't type "cash given".
Each dialog that takes numbers gets its own keypad.

```
Change src/pages/CashierBilling.tsx and add src/components/till/NumPad.tsx. Keep everything else.

1) src/components/till/NumPad.tsx — one keypad for all dialogs:
     props: onKey(key: string), enterLabel?: string (default "Enter"), enterDisabled?: boolean, showDot = true
     layout (4 columns, Enter as a full-width bar, same look as the main keypad):
         7  8  9  ⌫
         4  5  6  C
         1  2  3  .
         0  00 000
         [  <enterLabel>  ]
   - Every key: onMouseDown={(e) => e.preventDefault()} (the focused input keeps the focus) and onClick → onKey(k).
   - Big touch keys (h-14, text-2xl); Enter is the primary colour.

2) Shared typing rule (helper typeKey(value, key, opts)):
   - digits / 00 / 000 append; "." only once and only when decimals are allowed; at most 2 decimals for money;
     ⌫ removes the last character; C clears.
   - The FIRST key after a field gets the focus replaces its whole value (calculator style), later keys append — so a
     pre-filled amount (e.g. card amount in Mixed) can be overwritten by just typing.
   - Number inputs used with the keypad get inputMode="none" so the Windows touch keyboard does not pop up over the
     dialog (a physical keyboard still types normally).

3) Payment dialog (Cash / Card / Mixed) becomes a two-column payment screen (max-w-3xl):
     left:  Total (big) · Cash due · the fields of that mode (Cash given / Card amount / Card ref) · quick cash buttons
            (Exact, 500, 1000, 2000, 5000 — h-12, bigger) · Change / Short (big, green / red)
     right: <NumPad enterLabel="Complete" enterDisabled={busy || !canFinish} …>
   - The keypad types into the field that has the focus (track it like the Other item dialog's otherField:
     payField "cash" | "card" | "ref"; tapping a field selects it). Default: Cash → Cash given, Card → Card ref,
     Mixed → Card amount.
   - Card ref takes digits from the keypad too (approval numbers are digits); letters only from a keyboard.
   - Keypad Enter = Complete, through the same finishSale with the double-sale guard from Prompt 28.
   - Change updates live while typing.

4) The same keypad (smaller, h-12 keys) in every other dialog that takes a number or PIN, typing into its focused field:
     Supervisor PIN (no ".", Enter = OK) · No Sale (PIN; Enter = Open drawer) · Opening cash / Paid In / Paid Out
     (Amount and PIN; Enter = Save) · Bill discount % (Enter = OK) · Suspend note is text — no keypad there.
   The Other item dialog switches its own keypad to <NumPad> too.

5) Layout check at 1366×768 and 1920×1080 on a touch screen: the whole payment dialog, keypad included, fits without
   scrolling; no key smaller than 56 × 56 px.
```

---

## Prompt 33 — Cashier billing: scale sticker barcode (weight from the barcode)

Backend: TillService `GET /items/find` reads the weighing scale's sticker (10 digits = 5 digits scale code + 5 digits
weight in grams, e.g. `1000801410` = item 10008, 1.410 kg) and answers the item with `scaleQty: 1.41`
(`zf_sp_FindItem`, StockSystem.md §6.14). Scale items (unit KGS) only. The page only has to use that quantity.

```
Change src/pages/CashierBilling.tsx and src/services/tillLocalApi.ts. Keep everything else.

1) tillLocalApi.ts — extend TillItem with:
     unitCode?: string | null;    // "KGS" = sold by weight
     scaleQty?: number | null;    // weight in kg from a scale sticker barcode; null = normal scan

2) After findItem(code) in addItem: when item.scaleQty is a number > 0, the line quantity is item.scaleQty
   (e.g. 1.41) instead of 1. Everything after that is the same add flow as today (sale-locked check, price link
   picker, quantity price via linePrice(item, qty, …), open price, refund mode, wholesale).
   - A quantity typed in front ("2*" then the sticker) is ignored for a sticker scan — the weight is on the sticker.
     Show toast.info("Weight taken from the sticker: 1.410 kg").
   - The "more than 999" confirm of Prompt 25 does not apply.
   - getItem(itemId) (name search) never has scaleQty → qty as today.

3) One sticker = one bill line: a sticker scan ALWAYS adds a new line, it is never merged into an existing line of the
   same item (two bags of the same rice = two lines, so the bill matches the stickers). Mark the line
   fromScale: true; a later normal scan of the same item must not merge into a fromScale line either.
   Keep fromScale on suspend / recall if the line model allows it; if not, recalled lines are normal lines.

4) Display: for lines whose item.unitCode === "KGS" show the quantity with 3 decimals and "kg" (1.410 kg);
   other lines as today. Line amount = round(qty × unitPrice, 2) as today (1.410 × 190.00 = 267.90).
   The Qty key still works on the line (the cashier can correct a weight).

5) Not found: a sticker for an unknown / inactive / non-KGS item answers 404 as today → the existing red
   "item not found" message; the text is digits only, so no name search is started.
```

---

## Prompt 34 — Cashier billing: function bar at the bottom of the page, layout rearranged

No backend change. Moves the function buttons out of the top toolbar, the right panel and the Cash menu into one
bar at the bottom of the page. Changes the button layout of Prompts 30 / 31 and the Cash menu of Prompt 16.

```
Change src/pages/CashierBilling.tsx and src/lib/tillShortcuts.ts; add src/components/till/FunctionBar.tsx.
Keep every function, rule, PIN check, dialog and API call exactly as it is — this is only WHERE the buttons are.

1) New bottom function bar (FunctionBar.tsx) — full page width, directly ABOVE the status / message bar, always
   visible (never scrolls away; the bill list above it takes the scroll). 13 buttons, in this order, left to right:

     Qty · Price · Refund · Bill copy · No Sale · Suspend · Recall · Paid In · Paid Out · Opening cash ·
     Drawer summary · Day end · Void bill

     [Qty][Price] | [Refund][Bill copy][No Sale][Suspend][Recall] | [Paid In][Paid Out][Opening cash][Drawer summary] | [Day end][Void bill]

   - One row: grid with 13 equal columns (grid-cols-[repeat(13,minmax(0,1fr))]), gap 6 px, padding 6 px, each
     button h-14 (56 px). The "|" above are a slightly bigger gap (ml-2) between the four groups: line, bill, cash, end.
   - Below 1280 px wide: two rows (7 + 6), same order, same height.
   - Button: icon (18 px) above the label, text-xs font-semibold leading-tight, label may wrap to two lines
     ("Drawer summary", "Opening cash"), min-w-0, no fixed widths, the key chip in the top-right corner as now.
   - Colour: the same navy as Prompt 31 for all ("bg-blue-900 hover:bg-blue-950 text-white"), except
     Void bill → red (destructive) and Day end → amber, so the two that end something stand apart at the right end.
     "On" states keep "ring-2 ring-inset ring-white" (Qty / Price while the keypad types into them, Refund while
     refund mode is on). Disabled: same colour at 40 % opacity, with the same rules as today.
   - Recall keeps its count badge (status.suspendedBills, hidden when 0).
   - Every button: onMouseDown preventDefault and, after an action that opens no dialog, focusScan() — as today.
   - Every button calls runAction(action) — the same function the shortcut key calls. No second code path.

2) Remove these buttons from where they are now (they exist ONLY in the bottom bar afterwards):
   - top toolbar: Bill copy, No Sale, Suspend, Recall, Day end, Void bill, and the "Cash" menu button;
   - right panel: Qty, Price, Refund.

3) Cash menu → four direct buttons:
   - tillShortcuts.ts: add the actions "paidIn" | "paidOut" | "openingCash" | "drawerSummary" (labels as on the
     buttons; no default key — the supervisor can give them one in the Keys dialog). They open the same dialogs the
     menu items open today.
   - "cashMenu" (F12) stays as a key only: it opens the same four choices as a small popover above the Paid In
     button (↑/↓, Enter, Esc), so a cashier used to F12 loses nothing. A saved shortcut map keeps working; the new
     actions are added with empty keys.
   - The "No opening cash" chip in the status bar still opens the Opening cash dialog.

4) What is left, rearranged:
   - Top toolbar (one slim row): Search · Other item · Discount % · Reload · Profit · Keys — then the cashier name /
     Sign out at the right. Nothing else.
   - Right panel, top to bottom: totals → Cash / Card / Mixed → ONE row of three [ W/R ] [ Void line ] [ Wholesale ]
     (navy, h-14, as Prompt 31) → the keypad, which takes all the height the removed row gave back (flex-1).
   - Left: scan box, banners (REFUND / wholesale / recalled), the bill lines (flex-1, scrolls inside itself).
   - Page = h-screen flex column: toolbar · main (bill | right panel, flex-1 min-h-0) · function bar · status bar.
     No page scroll bar at any size.

5) Layout check at 1366×768 and 1920×1080, touch: all 13 buttons visible without scrolling, no label cut off or
   overflowing, no button under 56 px high, at least 8 bill lines visible at 1366×768, keypad keys not smaller
   than before. The status bar stays above the dialog overlay (Prompt 29); the function bar does NOT (it is dimmed
   under a dialog like the rest of the page).
```

---

## Prompt 35 — Cashier billing: Cash and Mixed shortcut keys swapped

No backend change. Changes the default keys of Prompts 19 / 28: Cash was F4 and Mixed was Num −; now the other way round.

```
Change src/lib/tillShortcuts.ts only. Keep everything else.

1) New defaults:
     pay       (Cash)   "NumpadSubtract"  (shown "Num −")   — was F4
     payMixed  (Mixed)  "F4"                                — was Num −
     payCard   (Card)   "NumpadAdd"       (shown "Num +")   — unchanged

2) Saved maps (localStorage "till.shortcuts.v1"): swap only when BOTH still have the old defaults
   (pay = F4 and payMixed = NumpadSubtract) → pay = NumpadSubtract, payMixed = F4. If the cashier changed either
   key themselves, leave both as saved (never end up with one key on two functions). Do the move once
   (bump the stored version to 2). Alternate keys are not touched.

3) "Num −" still acts as a shortcut only on the main screen (no dialog open); inside a dialog it types normally.
   The Cash / Mixed buttons, the Keys dialog and "Print list" show the new chips — they read getShortcuts(), so
   nothing else changes. The buttons stay where they are and do what they did; only the keys swap.
```

---

## Prompt 36 — Cashier billing: Reprint last bill (one key, no dialog)

Backend: TillService `POST /invoices/last/print` prints a COPY RECEIPT of the newest bill on this till
(StockSystem.md §6.7). No PIN, never opens the drawer. Needs the new TillService; no database change.

```
Change src/pages/CashierBilling.tsx, src/services/tillLocalApi.ts, src/lib/tillShortcuts.ts and
src/components/till/FunctionBar.tsx. Keep everything else (Bill copy stays as it is, for older bills).

1) tillLocalApi.ts — add:
     printLastInvoice() → POST /invoices/last/print
                          → { invoiceNo: string; printed: boolean; printError?: string | null }
                          400 { message: "No bill on this till yet." }

2) tillShortcuts.ts — new action "reprintLast": label "Reprint", description "Print a copy of the last bill",
   default key "Ctrl+L" (Ctrl+B stays Bill copy). preventDefault on it (the browser's address bar key). A saved map gets the new action with its default key when
   Ctrl+L is still free, otherwise with no key.

3) runAction("reprintLast"):
   - No dialog, no confirm, no PIN. Works with or without lines on the bill (it never touches the bill on the screen).
   - Guard against a double press: a ref (reprintingRef) — while one reprint is running, a second key press / tap
     does nothing. Ignore e.repeat as for every key.
   - While it runs: toast.info("Printing copy of the last bill…").
   - OK and printed → toast.success("Copy printed — <invoiceNo>").
     printed false → toast.error(printError ?? "Copy not printed") with the action "Try again" (runs it again).
     400 → toast.error(message)  ("No bill on this till yet.").
   - Finally focusScan().
   - Disabled only while the payment dialog is saving a bill.

4) FunctionBar.tsx — a "Reprint" button right after "Bill copy" (printer icon, same navy, key chip), calling
   runAction("reprintLast"). The bar now has 14 buttons: grid-cols-[repeat(14,minmax(0,1fr))] in one row; below
   1280 px two rows of 7 + 7. Order:
     Qty · Price · Refund · Bill copy · Reprint · No Sale · Suspend · Recall · Paid In · Paid Out · Opening cash ·
     Drawer summary · Day end · Void bill

5) Keys dialog and "Print list": the new row shows up by itself (they read the action list).
```

---

## Prompt 37 — Cashier billing: Price check (price and stock without adding to the bill, cost with the PIN)

Backend: TillService `GET /items/{itemId}/cost` (supervisor token) and `lastStockSyncAt` in `GET /sync/status`
(StockSystem.md §6.7). Prices and stock come from the item calls the page already has. Needs the new TillService;
no database change.

```
Change src/pages/CashierBilling.tsx, src/services/tillLocalApi.ts, src/lib/tillShortcuts.ts and
src/components/till/FunctionBar.tsx; add src/components/till/PriceCheckDialog.tsx. Keep everything else.

1) tillLocalApi.ts — add:
     export interface ItemCost { itemId: number; costPrice: number | null;
       priceLinks: { priceLinkId: number; costPrice: number | null }[] }
     getItemCost(itemId) → GET /items/{itemId}/cost  (send X-Supervisor-Token like getBillProfit)
                           401 { message } = no / expired token, 404 { message }
     SyncStatus gets  lastStockSyncAt?: string | null.

2) tillShortcuts.ts — new action "priceCheck": label "Price check", description "See an item's price and stock",
   default key "Ctrl+I" (preventDefault). A saved map gets it with its default key when Ctrl+I is still free,
   otherwise with no key.

3) FunctionBar.tsx — a "Price check" button right after "Price" (tag / search icon, same navy, key chip) calling
   runAction("priceCheck"). 15 buttons now: one row (grid-cols-[repeat(15,minmax(0,1fr))]) from 1440 px wide,
   two rows of 8 + 7 below that. Order:
     Qty · Price · Price check · Refund · Bill copy · Reprint · No Sale · Suspend · Recall · Paid In · Paid Out ·
     Opening cash · Drawer summary · Day end · Void bill
   Enabled always, except while the payment dialog is open.

4) PriceCheckDialog.tsx (max-w-2xl) — title "Price check", a blue strip under it: "Nothing is added to the bill".
   THE BILL ON THE SCREEN IS NEVER TOUCHED: this dialog has its own state and never calls addItem.
   - Scan box at the top (focused on open, onOpenAutoFocus like the other dialogs; the barcode scanner types here
     because the dialog has the focus). Enter:
       · findItem(text) → show the item;
       · 404 and the text has a letter → searchItems(text): one row → getItem(itemId); more → a list under the box
         (name, code, price, stock; ↑/↓, Enter or tap picks) ; none → red line "No item found for '<text>'";
       · 404 and digits only → red line "Item '<text>' not found".
     After every lookup: clear the box, keep the focus in it — the next scan replaces the item shown (check item
     after item without closing). A "⌨" button shows the on-screen A–Z keyboard of the Search dialog.
   - Item shown (big, readable from a step back):
       name (Descrip; Inv_Descrip muted under it when different), code line: barcode · RefCode · unit
       PRICE  Rs <retailPrice>   (text-5xl bold)          MRP <maxPrice> struck through when maxPrice > retailPrice
       Wholesale  Rs <wholesalePrice>   (only when set)
       Quantity prices (only when a level is set): "<qtyLevel2> or more → Rs <priceLevel2>", level 3, level 4
       Other prices (priceLinks, when any): table Remark · Retail · Wholesale
       Badges: "Open price" (openPrice), "Sale locked" red (isSaleLocked), "No discount" (noDiscount)
       Scale sticker scan (scaleQty > 0): "Weight 1.410 kg → Rs <round(scaleQty × retailPrice, 2)>"
       STOCK  <stockQty>  (3 decimals + "kg" for unitCode "KGS", else no trailing zeros; red when ≤ 0;
              "not known" when null) and muted "as of <status.lastStockSyncAt as dd/MM HH:mm>" — it is the last
              stock downloaded from the back office, not live.
   - Cost — only with the supervisor PIN:
       · A "Show cost" button (lock icon, key F2 inside this dialog). If the page already holds a supervisor token
         (profit view, discount, …) call getItemCost at once; else open the existing Supervisor PIN dialog first
         (same token flow, focus back to this dialog's scan box afterwards).
       · Shown: "Cost Rs <costPrice>" and "Margin Rs <retailPrice − costPrice> (<% of retailPrice>)", wholesale
         margin when a wholesale price is set, and a Cost column in the Other prices table (per link). null →
         "Cost not known". Cost in amber so it is clearly the private part.
       · Once shown it stays on for the next scans in THIS dialog (getItemCost after each lookup). Closing the dialog
         hides it again — the next price check starts without cost. A "Hide cost" button turns it off at once.
       · 401 from getItemCost (token expired) → hide cost, drop the token, ask the PIN again. Never cache cost
         values (no localStorage, no query cache that outlives the dialog).
   - Buttons: "Add to bill" (secondary; closes the dialog and runs the normal addItem with that code — for the
     customer who says yes; disabled for a sale-locked item) · "Close" (Esc). Global shortcuts are off while it is
     open, as for every dialog; on close → focusScan().

5) Keys dialog and "Print list": the new row shows up by itself.
```

---

## Prompt 38 — Cashier billing: X report (mid-shift reading, the day is not closed)

Backend: TillService `GET /x` and `POST /x/print` (StockSystem.md §6.8). Same figures as the day end, for the Z that
is still open — nothing is closed, billing goes on. Needs the new TillService and till db update U002.

```
Change src/pages/CashierBilling.tsx, src/services/tillLocalApi.ts, src/lib/tillShortcuts.ts and
src/components/till/FunctionBar.tsx; add src/components/till/XReportDialog.tsx. Keep everything else
(Day end and its Z summary dialog stay exactly as they are).

1) tillLocalApi.ts — add (ZSummary is the type POST /z/close already answers with):
     getXReport()    → GET  /x        → ZSummary   (closedAt null, status 0)
     printXReport()  → POST /x/print  → ZSummary   (printed, printError filled)
     both: 400 { message: "No Z is open - nothing to report yet." }

2) tillShortcuts.ts — new action "xReport": label "X report", description "Sales and cash so far — does not close the day",
   default key "Alt+X" (preventDefault). A saved map gets it with its default key when Alt+X is still free, otherwise
   with no key.

3) FunctionBar.tsx — an "X report" button right before "Day end" (chart / receipt icon, same navy — NOT amber, it
   closes nothing). The bar has 16 buttons now → always two rows of 8, same order, each button a little wider:
     Qty · Price · Price check · Refund · Bill copy · Reprint · No Sale · Suspend
     Recall · Paid In · Paid Out · Opening cash · Drawer summary · X report · Day end · Void bill
   Enabled always, except while the payment dialog is open (a bill on the screen does not matter — it is not saved yet
   and is not in the figures).

4) XReportDialog.tsx (max-w-md) — opens on runAction("xReport"), loads getXReport():
   - Title "X report", a blue strip: "Reading only — the day is NOT closed".
   - Header: Z <zNo> · opened <openedAt dd/MM HH:mm> · bills <fromSeq> – <toSeq> (<invoiceCount>) · now <time>.
   - Sales block:   Sales, Refunds (−), NET SALES (bold)
     Payments block: Cash, Card, Credit / voucher (only when otherAmount ≠ 0)
     Cash block:     Opening cash, + Cash sales (cashAmount), + Paid in, − Paid out, CASH IN DRAWER (expectedCash, big, bold)
     Money with 2 decimals and thousands separators, right aligned — the same look as the Z summary dialog, but
     WITHOUT the "Counted cash" input (counting is for the day end).
   - Buttons: "Print" (primary, Enter) → printXReport(): printed → toast.success("X report printed") and close;
     printed false → toast.error(printError ?? "X report not printed"), keep the dialog open (the figures are on the
     screen anyway). Guard against a double Enter with a ref, as in the payment dialog.
     "Refresh" (F5 inside the dialog) loads getXReport() again. "Close" (Esc).
   - 400 → no dialog, toast.info("No sales yet — nothing to report.").
   - Loading: skeleton rows. On close → focusScan().
   - If the bill on the screen has lines, a muted note at the bottom: "The bill on the screen is not included."

5) No PIN, no drawer, any number of times a day. Nothing else changes: the Z number, the bills, the opening cash and
   the day end are untouched by an X report.

6) Keys dialog and "Print list": the new row shows up by itself.
```

---

## Prompt 39 — Cashier billing: Bank transfer and Cheque payments, split on the Z and X

Backend: TillService takes `payType` 5 (bank transfer) and 6 (cheque) in `POST /invoices`; the Z summary and the
X report answer `bankAmount` and `chequeAmount` (StockSystem.md §6.15). Needs the new TillService and till db
update U003.

```
Change src/pages/CashierBilling.tsx, src/services/tillLocalApi.ts, src/lib/tillShortcuts.ts and
src/components/till/XReportDialog.tsx. Keep everything else (Cash, Card and Mixed work exactly as now).

1) tillLocalApi.ts
   - Payment line payType: 1 | 2 | 3 | 4 | 5 | 6   (5 = bank transfer, 6 = cheque).
   - ZSummary (POST /z/close, GET /x, POST /x/print) gets  bankAmount: number;  chequeAmount: number.
     otherAmount still means "everything that is not cash or card" — it INCLUDES bankAmount and chequeAmount.
   - POST /invoices can answer 400 { message: "A cheque payment needs the cheque number." } — show it as today.

2) Pay buttons (right panel): a second row under Cash / Card / Mixed with two buttons, same blue, same height:
       [ Cash ] [ Card ] [ Mixed ]
       [ Bank transfer ] [ Cheque ]
   They call runAction("payBank") / runAction("payCheque") → the same checks as Cash (no lines, discount too high)
   → openPay("bank") / openPay("cheque"). Disabled in the same cases as Card.
   tillShortcuts.ts: new actions "payBank" (label "Bank transfer", "Pay by bank transfer") and "payCheque" (label
   "Cheque", "Pay by cheque") — no default key; the supervisor can give them one in the Keys dialog.

3) Payment dialog, two new modes (same two-column screen with the NumPad as Card):
   - Bank transfer: Total (big), "Transfer ref / slip no" (optional, max 30, focused — digits from the NumPad,
     letters from a keyboard), a muted line "Check the transfer has arrived before you complete."
     Complete sends payments [{ lineNum: 1, payType: 5, amount: <bill net>, refNo }].
   - Cheque: Total (big), "Cheque no" (REQUIRED, max 30, focused), a muted line "Write the bill number on the back
     of the cheque." Complete is disabled until a cheque number is typed;
     sends payments [{ lineNum: 1, payType: 6, amount: <bill net>, refNo: <cheque no> }].
   - Both: the whole bill is paid that way (no part payment, no change, no "cash given"), Enter = Complete through the
     same finishSale with the double-sale guard. The cash drawer does NOT open (the till opens it for cash only).
   - Refund mode: both are allowed, same fields ("Refund by bank transfer" / "Refund by cheque").
   - Mixed stays cash + card only.

4) Z summary dialog (day end) and XReportDialog — Payments block shows, in this order:
       Cash
       Card
       Bank transfer      (bankAmount, only when ≠ 0)
       Cheque             (chequeAmount, only when ≠ 0)
       Credit / voucher   (otherAmount − bankAmount − chequeAmount, only when ≠ 0)
   The Cash block (opening cash, cash sales, paid in / out, CASH IN DRAWER) does not change: transfers and cheques
   are not drawer cash. Under the Cash block, when chequeAmount ≠ 0, a muted line:
   "Cheques to hand over: Rs <chequeAmount>".

5) Bill copy dialog: in the payment column / preview show "Bank transfer" and "Cheque" (with the ref / cheque no)
   for payType 5 / 6 instead of "Other". The list row keeps Cash / Card / Other (other includes both).
```

---

## Prompt 40 — Tills & Z Reports: Bank transfer and Cheque columns (change existing screen)

Backend: `POST Sync/ZReports/Search` and `GET Sync/ZReport/{terminalId}/{zNo}` now also answer `bankAmount` and
`chequeAmount` (StockSystem.md §6.15). Needs the new ItemApi and back office db update U003.

```
Change the existing "Tills & Z Reports" page (Z Reports tab and the Z detail page). Keep everything else.

1) Z rows get two more fields:  bankAmount: number | null,  chequeAmount: number | null.
   otherAmount still means "everything that is not cash or card" and INCLUDES both.
   null = the till did not send a split (a Z from before the change, or a till still on the old program).

2) Z Reports table — payment columns become: Cash, Card, Bank, Cheque, Other
   - Bank = bankAmount, Cheque = chequeAmount, Other = otherAmount − (bankAmount ?? 0) − (chequeAmount ?? 0).
   - When bankAmount and chequeAmount are both null: Bank and Cheque show "–" (muted) and Other shows otherAmount
     with a small "not split" hint in the title.
   - 0 shows as a muted "0.00"; money right aligned, 2 decimals.

3) Top summary for the filter: add Bank transfer and Cheque totals next to cash and card (nulls count as 0), and
   Other as the rest.

4) Z detail page: the payments card lists Cash, Card, Bank transfer, Cheque, Credit / voucher (the rest), with the
   same null rule. The 80 mm and A4 prints get the same lines (only the ones that are not 0).

5) Nothing changes in the till / server comparison or the mismatch rules — payment types are not compared.
```

---

## Prompt 41 — Cashier billing: bigger, bold text in the scan box, search, price fields and buttons

No backend change. Only text size / weight and the heights that go with it — the cashier must read the screen from
a step back. Changes the sizes of Prompts 30 / 32 / 34 (text-xs / text-sm labels) and nothing else.

```
Change src/pages/CashierBilling.tsx, src/components/till/FunctionBar.tsx, src/components/till/NumPad.tsx,
src/components/till/PriceCheckDialog.tsx and the till dialogs; add src/components/till/tillText.ts.
Keep every function, rule, key, colour, dialog and API call exactly as it is — this is ONLY text size, weight and
the height of the inputs / buttons. /billing only; the back office pages are not touched.

1) src/components/till/tillText.ts — the sizes in ONE place, used everywhere below (no sizes typed by hand):
     export const tillInput  = "h-14 text-2xl md:text-2xl font-bold placeholder:text-lg placeholder:font-normal";
     export const tillNumber = "h-14 text-3xl md:text-3xl font-bold text-right tabular-nums";
   The md: copies are needed: the shadcn <Input> has "text-base md:text-sm" built in, and md:text-sm wins over a
   plain text-2xl on a till screen (wider than 768 px) — without them the typed text stays small.
     export const tillPayBtn = "h-16 text-xl font-bold";
     export const tillBtn    = "text-base font-bold leading-tight";

2) Scan box (main screen): className tillInput — 56 px high, text-2xl bold, dark text (text-foreground, not muted),
   the placeholder smaller and normal weight so typed text clearly stands out. Border 2 px, and a 2 px primary ring
   while it has the focus so the cashier sees at a glance where the scanner will type. The "5*" quantity prefix chip
   (Prompt 25) and the spinner keep their place, sized to the new height. The "Search" button next to it: same
   height (h-14), text-lg font-bold.

3) Search dialog (F1 / the Search button) and the "Select item" list:
   - Text input: tillInput, focused on open as today. The "⌨" button same height.
   - Result rows: Description text-lg font-semibold (inv_Descrip under it text-sm muted), Code text-base,
     Price text-xl font-bold right aligned, Stock text-base muted. Row height at least 52 px (easy to tap);
     the highlighted row keeps its highlight. Badges ("Locked", "Several prices") text-sm.
   - The dialog may grow to max-w-3xl so the bigger rows do not wrap; the list scrolls inside the dialog.
   - Price check dialog scan box (Prompt 37): tillInput too.

4) Price and amount fields — every field where the cashier types a number gets tillNumber (text-3xl bold,
   right aligned), label above it text-base font-semibold:
     · the Qty / Price value shown while the main keypad types into the selected line;
     · open-price dialog (price), price link picker prices, Other item dialog (Price, Qty);
     · payment dialog: Cash given, Card amount (Card ref / Transfer ref / Cheque no: tillInput — it is text);
     · Opening cash / Paid In / Paid Out (Amount), Bill discount %, Z summary "Counted cash";
     · PIN fields: tillNumber but centred (text-center, tracking-widest).
   Keep inputMode="none", the first-key-replaces rule and the focus handling of Prompt 32. The value is selected
   on focus as today.

5) Pay buttons (right panel): Cash / Card / Mixed → tillPayBtn (64 px high, text-xl bold), icon 24 px;
   Bank transfer / Cheque → h-14 text-lg font-bold. The key chips stay text-xs in the corner.
   The row [ W/R ] [ Void line ] [ Wholesale ] → tillBtn, icon 20 px, h-14 as now.

6) Bottom function bar (FunctionBar.tsx, 16 buttons, two rows of 8):
   - Label: tillBtn (text-base font-bold) instead of text-xs; icon 20 px; button h-16 (64 px) instead of h-14.
   - Labels may still wrap to two lines ("Drawer summary", "Opening cash", "Price check"); min-w-0, never cut off,
     never an ellipsis. The key chip stays text-xs in the top-right corner and must not cover the label.
   - Colours, order, "on" ring, disabled opacity and the Recall badge: unchanged.

7) Also, the same step up where it is still small: toolbar buttons (Search · Other item · Discount % · Reload ·
   Profit · Keys) text-base font-semibold; dialog primary / secondary buttons on /billing h-12 text-lg font-semibold;
   quick cash buttons (Exact, 500, …) text-xl font-bold. NumPad keys stay text-2xl. Bill lines and totals are
   already big — do not change them.

8) Layout check at 1366×768 and 1920×1080, touch: no page scroll bar; the function bar's two rows fully visible,
   no label cut off or overflowing its button; at least 7 bill lines visible at 1366×768 (the bar is 16 px taller —
   take the space from the bill list, not from the keypad); keypad keys not smaller than before; every dialog,
   keypad included, still fits without scrolling. After each dialog closes the scan box has the focus, as today.
```

---

## Prompt 42 — Cashier billing: the text the cashier TYPES is too small (scan box, Select item, Cash given)

No backend change. Three boxes where the typed text is still about 14 px: the scan box on the main screen, the
text box of the "Select item" dialog, and "Cash given" in the payment dialog. Paste this on its own, or after
Prompt 41 if the typed text is still small.

```
Change src/pages/CashierBilling.tsx and the till dialogs (Select item / Search, payment). Only the size of the
text inside the inputs — nothing else moves or changes.

Cause to fix: the shadcn <Input> carries "text-base md:text-sm". A class like text-2xl does not remove
md:text-sm, so on a till screen (wider than 768 px) the typed text stays 14 px. Every size below must be given
with its md: copy too (or set with style={{ fontSize }}), and checked in the browser at 1366×768.

1) Scan box (main screen, "Scan / enter code"):
   - Typed text: 28 px bold, dark  → "h-16 text-[28px] md:text-[28px] font-bold text-foreground", the normal
     UI font (font-sans, NOT the monospace it has now), letter-spacing normal.
   - Placeholder stays small and light so it never looks like typed text:
     "placeholder:text-base placeholder:font-normal placeholder:text-muted-foreground".
   - 2 px border; while focused a 2 px primary ring. Padding px-4. The caret must be easy to see (caret-primary).

2) "Select item" dialog — the text box at the top (where the cashier typed "rose ra"):
   - "h-14 text-2xl md:text-2xl font-bold text-foreground" (24 px bold), px-4; the "⌨" button h-14 to match.
   - List under it: Description 18 px semibold, Price 20 px bold (already bold — keep), Code and Stock 16 px.

3) Payment dialog — "Cash given" (and Card amount in Card / Mixed):
   - "h-16 text-4xl md:text-4xl font-bold text-right tabular-nums text-foreground" (36 px bold) — the same
     weight as the Total above it; it is the number the cashier must check before pressing Complete.
   - Its label "Cash given" 16 px semibold. "Cash due" value 20 px semibold (it is 14 px now).
   - Card ref / Transfer ref / Cheque no: 24 px bold, like the Select item box.

4) The same rule for every other box the cashier types into on /billing (Other item price and qty, open price,
   Opening cash / Paid In / Paid Out amount, Discount %, PIN, Price check scan box): numbers 30 px bold right
   aligned, text 24 px bold — each with its md: copy.

5) Check at 1366×768 and 1920×1080: type "rose ra" in the scan box and in Select item, and 324 in Cash given —
   the text must be clearly readable from one metre. No dialog gets a scroll bar, the keypad keys do not shrink,
   and the focus rules stay exactly as they are.
```

---

## Prompt 43 — Two themes: Light (as now) and Dark, with a switch

No backend change. The look of today stays as the Light theme, untouched; a Dark theme is added. The choice is
kept on that computer (each till / PC picks its own), not per user.

```
Add src/lib/theme.ts and src/components/ThemeToggle.tsx; change index.html, src/index.css, the app layout header,
src/pages/CashierBilling.tsx, src/components/till/* and src/lib/tillShortcuts.ts.
Keep every function, layout, size, key and API call exactly as it is — this is ONLY colours.
Light must look exactly as it does today.

1) How the theme is switched (shadcn way):
   - Tailwind darkMode: ["class"]; the theme is the class "dark" on <html> (none = light).
   - src/lib/theme.ts: getTheme() / setTheme("light" | "dark") / toggleTheme() and a useTheme() hook.
     Saved in localStorage "app.theme"; default "light" when nothing is saved (do NOT follow the Windows setting —
     a till must not change by itself).
   - index.html: a tiny inline script in <head> that reads "app.theme" and adds the class before the app loads,
     so a dark till never flashes white on start or on F5 / Reload.
   - Also set <html style="color-scheme: dark|light"> so scroll bars and native inputs match.

2) The switch (ThemeToggle.tsx): a button with a Sun / Moon icon and the text "Light" / "Dark" (the theme it
   switches TO), title "Change theme".
   - Back office: in the top header, next to the signed-in user.
   - Sign-in screens (back office and till): top-right corner, so it can be changed before signing in.
   - /billing: in the top toolbar after "Keys". onMouseDown preventDefault and focusScan() after the click, like
     every till button. tillShortcuts.ts: new action "theme" (label "Theme", description "Switch light / dark"),
     no default key — the supervisor can give it one in the Keys dialog. Switching never touches the bill.

3) Dark colours — in src/index.css under ".dark", as the shadcn CSS variables (no new colour system):
     background  very dark blue-grey (about #0f172a)      foreground  near white (#e5e7eb)
     card / popover / dialog  one step lighter (#1e293b)   border / input  #334155
     muted text  #94a3b8  (never darker — it must stay readable)
     primary  the same blue family, a little lighter (#3b82f6) with white text
     destructive red #ef4444 · success green #22c55e · warning amber #f59e0b
   Use the variables everywhere (bg-background, bg-card, text-foreground, text-muted-foreground, border-border).
   Find every hard-coded light colour (bg-white, bg-gray-50/100, bg-slate-50, text-black, text-gray-700/900,
   border-gray-200, …) and replace it with the variable or give it a dark: pair. No white panel may be left in Dark.

4) /billing in Dark — the parts with their own colours:
   - Bill lines: rows on bg-card; the selected line "dark:bg-blue-900/60" with white text and a 2 px left primary
     bar (today's pale blue highlight is unreadable on dark). Refund lines red text "dark:text-red-400".
   - Totals: the Total stays the biggest, pure white. Change green "dark:text-green-400", Short red "dark:text-red-400".
   - Scan box and every input: "dark:bg-slate-900 dark:text-white dark:border-slate-600", placeholder #94a3b8,
     the focus ring as bright as in Light. The typed text sizes of Prompts 41 / 42 are not changed.
   - Pay buttons (Cash / Card / Mixed / Bank transfer / Cheque): keep the bright blue, white text.
   - Navy buttons (function bar, W/R, Void line, Wholesale — bg-blue-900) would vanish on a dark page:
     "dark:bg-slate-700 dark:hover:bg-slate-600" with a 1 px "dark:border-slate-500" and white text.
     Void bill stays red, Day end stays amber (dark text on amber). The "on" ring stays white.
     Disabled: 40 % opacity as now — check a disabled label can still be read.
   - Keypad / NumPad keys: "dark:bg-slate-800 dark:text-white dark:border-slate-600"; Enter / Complete primary.
   - Key chips (F1, Ctrl+P …): "dark:bg-black/40 dark:text-slate-200".
   - Banners: REFUND "dark:bg-red-900 dark:text-red-100"; wholesale "dark:bg-orange-900 dark:text-orange-100";
     recalled bill and the "Prices were updated" note "dark:bg-amber-900 dark:text-amber-100".
   - Status / message bar: error "dark:bg-red-800", warning "dark:bg-amber-700", success "dark:bg-green-800",
     info "dark:bg-slate-700" — all with white text. The Online dot keeps green / red.
   - Dialogs: bg-card, the overlay "bg-black/70". Blue info strips (Price check, X report) "dark:bg-blue-950
     dark:text-blue-100". Cost in Price check stays amber ("dark:text-amber-400").

5) Back office pages in Dark:
   - Tables: header bg-muted, row hover "dark:hover:bg-slate-800", borders border-border; negative quantities
     "dark:text-red-400".
   - Chips (GRN green, PRN orange, Sale blue, Refund purple, Adjustment grey, Opening teal; the role chips) keep
     their colour family: in Dark use the 900 shade as background with the 200 shade as text.
   - Charts (home page, Sales analysis): axis, grid and legend colours from the variables (grid #334155, labels
     #94a3b8), tooltip on bg-popover; the series colours a step lighter so they stand out on dark.
   - Toasts: pass the current theme to the sonner <Toaster theme=…>.

6) Always light, whatever the theme: everything that is PRINTED or exported — receipt / bill copy previews,
   Z and X prints (80 mm and A4), quotation / invoice PDF, the shortcut "Print list". Wrap the print area in a
   white, black-text container and in @media print force white background and black text.

7) Check both themes at 1366×768 and 1920×1080: /billing with a bill of normal, refund and wholesale lines, the
   payment dialog, Select item, Price check, X report, Day end; back office home, a table page and Sales analysis.
   Text contrast at least 4.5 : 1 (labels on buttons, muted text, disabled buttons, placeholder). Switching the
   theme keeps the bill, the focus in the scan box and any open page as they are; the choice survives F5 and
   sign-out.
```

---

## Prompt 44 — Till: no "Save password?" from Chrome, no browser notifications

No backend change. Two parts — the page (this prompt) and the till PC (below). The page alone cannot switch
Chrome's password manager off for certain; the PC setting does.

**Till PC, once per till** (not Lovable):

1. Run [Till-Chrome-Policy.reg](Till-Chrome-Policy.reg) as administrator, then close every Chrome window and open
   it again. `chrome://policy` must list the values with status OK. It turns off the password offer, autofill,
   notifications, the translate bar and the "make Chrome default" bar for that PC.
2. Passwords Chrome saved before: `chrome://password-manager/passwords` → remove the till's entries.
3. Start the till from a shortcut, so there is no address bar and no "Restore pages?" bubble after a power cut:
   `"C:\Program Files\Google\Chrome\Application\chrome.exe" --kiosk "<till url>/billing" --no-first-run --hide-crash-restore-bubble`
   (`--kiosk` = full screen, Alt+F4 closes it; use `--app="<till url>/billing" --start-maximized` to keep the
   window frame.)

**Back office PC, once per PC** (not Lovable): [BackOffice-Chrome-Policy.reg](BackOffice-Chrome-Policy.reg): like the till
file, but Chrome still saves passwords and shows the "Save as" dialog, and it allows print / PDF pop-up windows,
downloads and copy for the back office address. Change
`http://192.168.1.5` in the file first, then run it the same way as the till file.

**PCs with Microsoft Edge instead of Chrome:** [Till-Edge-Policy.reg](Till-Edge-Policy.reg) and
[BackOffice-Edge-Policy.reg](BackOffice-Edge-Policy.reg), checked at `edge://policy`. Till shortcut:
`"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe" --kiosk "<till url>/billing" --edge-kiosk-type=fullscreen --no-first-run`

```
Change the cashier sign-in screen, the Supervisor PIN dialog and every other PIN / password field on /billing
(No Sale, Opening cash / Paid In / Paid Out, Discount %, Price check "Show cost", Keys) — and src/components/till/*
where they live. Keep every function, check, key and API call exactly as it is.

1) No field on /billing may be type="password" — that is what makes Chrome offer "Save password?" and fill in an
   old one. Make one component src/components/till/SecretInput.tsx and use it for the cashier password and every
   PIN:
     <input type="text" inputMode="none" autoComplete="off" autoCorrect="off" autoCapitalize="off"
            spellCheck={false} data-lpignore="true" data-1p-ignore data-form-type="other"
            style={{ WebkitTextSecurity: "disc" }} … />
   - The dots come from -webkit-text-security (Chrome / Edge), so the value is still hidden on the screen.
   - name / id must not contain "password", "pass", "pwd", "pin", "user" or "login" (use e.g. "f1", "f2").
   - It keeps the sizes of Prompts 41 / 42, the NumPad typing and the focus rules of today.
   - No copy / cut from it (onCopy / onCut preventDefault).

2) Cashier user name field: type="text", autoComplete="off", name "f0", spellCheck false — so Chrome shows no
   list of earlier user names under it.

3) No <form> around these fields (or <form autoComplete="off" onSubmit preventDefault>): Enter and the Sign in /
   OK buttons call the same handlers as today from onKeyDown / onClick. Chrome offers to save on a form submit
   followed by a page change — there must be none. After a good sign-in or PIN clear the field's value at once.

4) Scan box, Select item box, amount, qty and ref fields on /billing: autoComplete="off", autoCorrect="off",
   spellCheck={false} — no suggestion list, no red spelling line under an item name.

5) Notifications: the app never calls Notification.requestPermission(), registers no service worker and no push
   on /billing — messages go to the bottom bar only (Prompt 29). Remove any such call if one exists.

6) The back office sign-in (Prompt 23) is NOT changed — it keeps a normal password field; office users may let
   their own browser remember it.

7) Check in Chrome with the password manager still ON (before the PC setting): sign in as a cashier, type a
   supervisor PIN, do a No Sale — no "Save password?" bubble, no key icon in the address bar, no filled-in or
   suggested value in any field. The password and the PINs still show as dots.
```

---

## Prompt 45 — Cashier billing: refund against the original bill (scan the bill, pick the lines)

Backend: TillService `GET /invoices/{no}/refund`, `POST /refunds/check`, `POST /refunds` (StockSystem.md §6.16).
Every sale receipt now ends with the bill number as a barcode. Needs the new TillService and till db update U004.
The till works out the money and refuses more than was sold — the page only picks lines and quantities.

```
Change src/pages/CashierBilling.tsx, src/services/tillLocalApi.ts, src/lib/tillShortcuts.ts and
src/components/till/FunctionBar.tsx; add src/components/till/RefundBillDialog.tsx. Keep everything else.

1) tillLocalApi.ts — add:
     export interface RefundBillLine { lineNum: number; itemId: number; name: string; code?: string | null;
       unitCode?: string | null; qty: number; unitPrice: number; discount: number; amount: number; priceType: number;
       refundedQty: number; leftQty: number }
     export interface RefundBill { invoiceNo: string; zNo: number; invDate: string; cashierId?: string | null;
       grossAmount: number; discount: number; discountPercent?: number | null; netAmount: number; status: number;
       refundedAmount: number; canRefund: boolean; reason?: string | null;
       lines: RefundBillLine[]; payments: { lineNum: number; payType: number; amount: number; refNo?: string | null }[] }
     export interface BillRefundBody { refInvoiceNo: string; lines: { refLineNum: number; qty: number }[];
       payType?: number; refNo?: string | null; cashierId?: string | null; print?: boolean }
     export interface BillRefundResult { invoiceNo: string | null; refInvoiceNo: string; linesAmount: number;
       discount: number; netAmount: number;
       lines: { refLineNum: number; lineNum: number; itemId: number; name: string; qty: number; unitPrice: number;
                discount: number; amount: number }[];
       printed: boolean; drawerOpened: boolean; printError?: string | null }

     getRefundBill(invoiceNo)   → GET  /invoices/{invoiceNo}/refund → RefundBill
                                   400 { message: "Bill not found on this till." }
     checkBillRefund(body)      → POST /refunds/check → BillRefundResult (invoiceNo null, nothing saved)
     saveBillRefund(body, token)→ POST /refunds  with header X-Supervisor-Token: <token> → BillRefundResult
                                   401 { message } no / expired token;  400 { message } e.g.
                                   "SUGAR 1KG: only 2.000 left to refund (sold 3.000, already refunded 1.000)."
   The PrintBill type (GET /invoices/{no}) gets  refInvoiceNo?: string | null.

2) How it opens:
   - The "Refund" button in the function bar and its shortcut key now open the RefundBillDialog (label "Refund",
     description "Refund against the bill"). tillShortcuts.ts: keep the action id and its saved key.
   - Scan box on the main screen: when the text looks like a bill number — /^[A-Za-z0-9]{1,10}-\d{8}$/ (e.g.
     T01-00000351, what the receipt barcode types) — do NOT look for an item: open the dialog with that number
     already looked up. If the bill on the screen has lines: message "Finish or suspend the bill on the screen
     first." and do nothing.
   - The old refund mode (a refund without a bill) stays, behind a secondary button in the dialog:
     "No bill — refund without a receipt" → closes the dialog and turns refund mode on exactly as today (PIN as
     today, red REFUND banner). Nothing else about refund mode changes.

3) RefundBillDialog.tsx (max-w-4xl, two columns from 1280 px: left the bill, right totals + pay back + NumPad):
   THE BILL ON THE SCREEN IS NEVER TOUCHED — the dialog has its own state. Global shortcuts are off while it is
   open, as for every dialog; on close → focusScan().
   a) Top: scan box "Scan the barcode under the bill — or type the bill number" (the big input style of
      Prompts 41 / 42, focused on open, autoComplete off). Enter → getRefundBill(text.trim().toUpperCase()).
      400 → the message in red under the box, select the text, keep the focus (ready for the next scan).
   b) Bill header strip: bill number · date and time (dd/MM/yyyy HH:mm) · cashier · "Paid Rs <netAmount>" ·
      how it was paid (Cash / Card / Bank transfer / Cheque / Mixed, from payments) ·
      "Refunded so far Rs <refundedAmount>" when > 0 · "Bill discount Rs <discount>" when > 0.
      canRefund false → a red strip with `reason`, the lines shown greyed out, nothing can be ticked.
   c) Lines table (scrolls inside the dialog): [tick] · Item (name; code small, muted) · Sold · Refunded · Left ·
      Refund qty · Price · Amount.
        - A line with leftQty 0: greyed out, badge "Refunded", cannot be ticked.
        - Ticking a line puts leftQty in "Refund qty"; unticking clears it. "Select all" ticks every line that
          has something left, with its full leftQty.
        - Refund qty: more than 0 and never more than leftQty — a bigger number is cut back to leftQty and the
          cell flashes red. Whole numbers only, except unitCode "KGS": up to 3 decimals.
          Typing a quantity into an unticked line ticks it; 0 or empty unticks it.
        - Amount = qty × unitPrice − (line discount × qty / sold qty), a preview only, 2 decimals.
        - Keyboard: ↑/↓ move the highlighted line, Space ticks / unticks, digits (keyboard or NumPad) type the
          Refund qty of the highlighted line (first key replaces, like every number field), Ctrl+A = Select all.
   d) Right column — totals from the till, not worked out by the page: after every change (300 ms after the last
      one) call checkBillRefund({ refInvoiceNo, lines }) with the ticked lines and show
          Lines            <linesAmount>
          Bill discount  − <discount>        (only when > 0)
          REFUND TOTAL     <netAmount>       (text-4xl bold, red)
      While it loads: the old figures dimmed. 400 → the message in red instead of the totals and the Refund
      button disabled. No ticked line → "Tick the lines the customer brings back."
   e) Pay back by: four buttons [ Cash ] [ Card ] [ Bank transfer ] [ Cheque ] (payType 1 / 2 / 5 / 6) — the whole
      amount goes back ONE way. Default: the way the bill was paid when it had one payment type, else Cash.
      Card: "Card ref" (optional, max 30). Bank transfer: "Transfer ref" (optional). Cheque: "Cheque no" (REQUIRED).
      Under it the NumPad of the other dialogs: it types into the field that has the focus (Refund qty of the
      highlighted line, or the ref field).
   f) Buttons: "Refund Rs <netAmount>" (primary, red, key Enter when the focus is not in the scan box) ·
      "Another bill" (clears the dialog, focus back to the scan box) · "Close" (Esc).

4) Saving — the supervisor PIN is asked EVERY time (a token the page already holds is not enough for a refund):
   - "Refund" → open the existing Supervisor PIN dialog (title "Refund Rs <netAmount> — supervisor PIN")
     → POST /auth/supervisor { pin } → token → saveBillRefund({ refInvoiceNo, lines, payType, refNo,
     cashierId, print: true }, token). Wrong PIN → stay in the PIN dialog as today. Cancel → back to the refund
     dialog, nothing saved.
   - Guard against a double Enter / double tap with a ref (savingRef), as in the payment dialog.
   - 200 → close the dialog, message "Refund <invoiceNo> — Rs <netAmount> back to the customer (<Cash/Card/…>)";
     printed false → also the printError with "Print again" (POST /invoices/{invoiceNo}/print?copy=false), as
     after a sale. Then reload the status bar and focusScan().
   - 400 → show the message in the dialog (e.g. another till user refunded it meanwhile), call getRefundBill
     again so Sold / Refunded / Left are fresh, keep the dialog open.
     401 → "The PIN was not accepted — try again." and ask the PIN again.
   - The page never sends prices or amounts and never refunds more than Left on its own either — but the till is
     the one that decides; always show ITS message.

5) Bill copy dialog: a refund bill made this way shows "Refund of <refInvoiceNo>" in the preview header (the
   paper already prints "REFUND OF BILL : …"). Sale bills: the preview shows a small barcode-style line
   "||| <invoiceNo> |||" at the bottom where the real barcode is printed.

6) Keys dialog and "Print list": the Refund row keeps its key; its description becomes "Refund against the bill".

7) Layout check at 1366×768 and 1920×1080, touch: the dialog with a 12-line bill fits without a page scroll bar
   (the lines table scrolls inside), tick boxes and Refund qty cells at least 44 px high, the REFUND TOTAL and
   the typed quantity readable from one metre. Try: scan a bill → tick one line → qty 1 of 3 → Refund → PIN →
   done; scan the same bill again → that line shows Refunded 1, Left 2.
```

---

## Prompt 46 — Cashier billing: refund payment dialog — nothing to type, the amount is the refund total

No backend change. In refund mode the "Refund — CASH" dialog asks for "Cash paid out" in an empty box. A refund
always pays back exactly the refund total, so the cashier should only confirm.

```
Change the payment dialog in src/pages/CashierBilling.tsx (refund mode only). Sales are not changed.

1) Refund — CASH:
   - No input box. Show instead, big (text-4xl bold, red):   "Pay the customer   Rs <total>"
     and under it, muted: "Give this amount from the drawer, then press Complete."
   - Hide "Cash due", the quick cash buttons (Exact, 500, 1000, …) and Change / Short — they are for sales.
   - The NumPad stays only as the big "Complete" key (digit keys hidden or disabled).
   - Complete (button, NumPad key and Enter) is enabled at once and sends
       payments: [{ lineNum: 1, payType: 1, amount: <total>, tendered: <total> }]
     through the same finishSale with the double-sale guard. The focus is on Complete when the dialog opens,
     so Cash key → Enter finishes the refund.

2) Refund — CARD / BANK TRANSFER / CHEQUE: the amount is the refund total and is not typed either; only the
   reference fields stay (Card ref optional, Transfer ref optional, Cheque no required), focused on open.
   Refund — MIXED: not offered in refund mode (disable the Mixed button and its key while REFUND is on, with
   the short grey message "A refund is paid back one way.").

3) Title stays "Refund — CASH" etc.; the Complete button reads "Complete refund (Enter)".
```

---

## Prompt 47 — Cheques: bank CSV upload shows the cheques that were not updated, with CSV export

Backend: `POST api/ChequeCreate/upload` now answers `{ message, result }` and there is a new
`POST api/ChequeCreate/upload/export`. Needs the new ItemApi (no db change).

```
Change the existing cheque bank-statement upload (the screen that posts the CSV to api/ChequeCreate/upload).
Keep the upload part as it is.

1) api: upload answers
     { message, result: { fileName, totalRows,
                          debited[], notFound[], amountMismatch[], alreadyDebited[], notUpdated[] } }
   Each row: { lineNo, bankDate, chequeNumber, bankAmount, dbAmount | null, supplierName | null,
               chequeDate | null, status, message }
   status: "Debited" | "NotFound" | "AmountMismatch" | "AlreadyDebited".
   notUpdated = notFound + amountMismatch (debited by the bank but NOT updated in the database).

2) After the upload, under the upload box, a summary strip:
     Rows in file <totalRows> · Marked debited <debited.length> (green) ·
     Not updated <notUpdated.length> (red, bold when > 0) · Already debited <alreadyDebited.length> (muted)

3) At the BOTTOM of the page: card "Debited by the bank — not updated" listing result.notUpdated:
     Line | Bank date | Cheque no | Bank amount | DB amount | Supplier | Status | Message
   - Status badge: NotFound red "Not in database", AmountMismatch amber "Amount differs".
   - Money right aligned, 2 decimals; DB amount "–" when null.
   - Empty → a green line "All debited cheques were found and updated."
   - Top right of the card: button "Export CSV" (download icon), disabled when the list is empty.
     It posts result.notUpdated as the JSON body to POST api/ChequeCreate/upload/export, gets a blob (text/csv)
     and saves it with the name from Content-Disposition (fallback "Cheques_NotUpdated.csv").
     400 → toast with the message.

4) Two collapsible sections under it (closed by default): "Marked debited (n)" and "Already debited (n)",
   same columns, no export.
```

---

## Prompt 48 — Till: customer display on a second screen (items and total)

No backend change (no TillService, no db). The billing page sends what is on the bill to a second browser window,
`/customer-display`, that sits on a screen facing the customer. Both windows are in the same Chrome on the till PC, so
they talk with a `BroadcastChannel` — it works offline too.

```
1) New file src/lib/customerDisplay.ts
   - const CH = "till.customerDisplay"; one BroadcastChannel(CH), created lazily (no-op when BroadcastChannel is missing).
   - Message types:
       type CdLine  = { name: string; qty: number; unitPrice: number; discount: number; amount: number;
                        priceType: "retail" | "wholesale" };
       type CdState =
         | { kind: "idle" }
         | { kind: "bill"; refund: boolean; lines: CdLine[]; lastIndex: number | null;
             itemCount: number; subTotal: number; discount: number; discountPercent: number | null; total: number }
         | { kind: "paid"; refund: boolean; invoiceNo: string; total: number;
             cashGiven: number | null; change: number | null; payLabel: string };
       messages: { type: "state", state: CdState } | { type: "hello" }
   - publish(state): posts { type: "state", state } and keeps it in localStorage "till.customerDisplay.last" (so a
     reloaded display shows the bill at once). subscribe(fn) for the display page. sayHello() for the display page.
   - openCustomerDisplay(): opens the window (see 4). Remember the window in a module variable; when it is still open
     just focus() it.

2) CashierBilling.tsx — send, never anything secret (no cost, profit, supervisor, cashier PIN):
   - useEffect on [lines, billDiscount, discPct, total, refund, selected]:
       no lines → publish({ kind: "idle" }) — but NOT while a "paid" screen is being held (see below);
       else publish({ kind: "bill", ... }) with lines in bill order, name = the same name the bill grid shows,
       amount = lineAmount(l), lastIndex = the index of the line added or changed last (fall back to the last line).
   - finishSale success → publish({ kind: "paid", invoiceNo, total, payLabel: "Cash" | "Card" | "Bank transfer" |
     "Cheque" | "Mixed", cashGiven / change for cash (null otherwise), refund }). Hold it for 15 s or until the first
     line of the next bill is scanned, whichever comes first, then idle.
   - Void bill / suspend → idle at once. Recall → the recalled bill.
   - Listen on the channel: a "hello" from the display → publish the current state again right away.

3) Opening the display — keep the till screen compact, no new big button:
   - tillShortcuts.ts: new action "customerDisplay", label "Customer display", description "Open the customer
     display on the second screen", default key "Ctrl+Shift+D".
   - Status strip at the top (where online / unsent bills is shown): a small monitor icon (lucide Monitor, 18 px).
     Green when a display answered in the last 10 s (the display sends "hello" every 5 s), grey otherwise.
     Title "Customer display — open (Ctrl+Shift+D)". Click = openCustomerDisplay().
   - Auto open: a checkbox "Open the customer display when the till starts" in the Keys dialog, stored in
     localStorage "till.customerDisplay.auto". When ticked, /billing calls openCustomerDisplay() once on load. If the
     window does not open (pop-up blocked) show once: "Allow pop-ups for this site in Chrome to open the customer
     display automatically" and leave the icon grey.

4) openCustomerDisplay() — put it on the second screen:
   - If window.getScreenDetails exists (Chrome Window Management): await it (Chrome asks once "Manage windows on all
     your displays" — Allow), take the first screen that is not isPrimary (else the current one), and
       window.open("/customer-display", "tillCustomerDisplay",
                   `popup,left=${s.availLeft},top=${s.availTop},width=${s.availWidth},height=${s.availHeight}`)
   - Otherwise (or the permission is refused): window.open with left = window.screen.width, top 0, 1024×768.
   - Remember the chosen screen's left/top in localStorage "till.customerDisplay.pos" and reuse it.

5) New page src/pages/CustomerDisplay.tsx, route "/customer-display" next to "/billing" in App.tsx (outside
   RequireAuth and AppLayout, no toaster, no sign-in). Full window, no scrollbars, cursor hidden, always dark
   (bg #0b1220, white text) whatever the till theme, big tabular numbers, money "Rs 1,234.00" (same money format as
   the till). Shop name: query ?shop=… or localStorage "till.shopName", default "Welcome".
   On load: show localStorage "till.customerDisplay.last", subscribe, sayHello() and then every 5 s.
   "Click anywhere for full screen" hint at the bottom until the first click → requestFullscreen().

   Screens:
   a) idle — shop name large in the middle, "Welcome" under it, a clock (HH:mm) and the date small at the bottom.
   b) bill — two parts:
      - Top band (about 30 % of the height): the last item — name (text-5xl, 2 lines max, ellipsis),
        under it "qty × Rs unit price" and the line amount on the right (text-5xl bold). Wholesale lines get a small
        "Wholesale" chip. A short flash (bg fades from amber) each time lastIndex or its qty changes.
      - Below, left 60 %: the bill list — Item | Qty | Price | Amount, text-2xl, newest at the bottom, auto-scrolls
        to the newest; the last item row highlighted. Line discount as a muted second line "Discount − Rs x".
      - Below, right 40%: Items <itemCount>; Sub total; Discount (only when > 0, with "(10%)" when a percent);
        then TOTAL very big (text-7xl bold, green).
      - Refund: a red band "REFUND" across the top, amounts red, TOTAL label "TO PAY BACK".
   c) paid — middle: "Thank you!" (text-6xl), the payLabel and "Rs total"; for cash: "Cash Rs cashGiven" and
      "Your change Rs change" (text-6xl bold, amber) — change hidden when 0. Refund: "Refund Rs total — thank you".
      Bill number small at the bottom.
   No buttons, nothing to type; keys do nothing (Esc only leaves full screen).

6) Setup (show this in the Keys dialog under the checkbox, muted, small):
   "Customer display: connect the second screen, set Windows to Extend these displays, then press Ctrl+Shift+D.
    Chrome asks once to manage windows — Allow."
```

---

## Prompt 49 — Stock take: count sheets, enter counts, post the difference

Backend: new `api/StockTake/*` (StockSystem.md §6.18). Needs the new ItemApi and back office db update U006.

```
New back office feature "Stock Take". Sidebar: "Stock Take" (lucide ClipboardList) right after "Adjustment History".
Routes: /stock-take (list) and /stock-take/:id (one stock take). Same look as Stock Adjustment.

1) src/services/stockTakeApi.ts (apiClient, same error handling: 400/404 → { message } in a toast)
   type StockTake = { stockTakeId; stockTakeNo; title; freezeAt; catId; subCatId; supId; includeZeroStock;
     status: 1 | 2 | 9; adjNo: string | null; uncountedAsZero: boolean | null; postedAt; postedBy; userId;
     itemCount; countedItems; sheetCount; sheetsDone; sheets?: Sheet[] }
   type Sheet = { sheetId; sheetNo; sheetName; countedBy; status: 1 | 2; lineCount; countedLines }
   type SheetLine = { lineNum; itemId; refCode; barcode; descrip; unitCode; countedQty: number | null; remark;
     countedBy; countedAt; systemQty: number | null }
   type VarianceRow = { itemId; refCode; barcode; descrip; catName; unitCode; sheets; countedQty: number | null;
     costPrice; systemQty; diffQty: number | null; diffValue: number | null; retailPrice; remark }
   createStockTake(body)            POST /StockTake/Create              → { message, data: StockTake }
   searchStockTakes(body)           POST /StockTake/Search              → StockTake[]
   getStockTake(id)                 GET  /StockTake/{id}                → StockTake (with sheets)
   getSheet(id, sheetId, showSys)   GET  /StockTake/{id}/Sheet/{sheetId}?showSystemQty= → { header, sheet, lines }
   addSheet(id, { sheetName, countedBy })               POST /StockTake/{id}/Sheet
   addItem(id, sheetId, { itemId } | { code })          POST /StockTake/{id}/Sheet/{sheetId}/AddItem → SheetLine
   saveCounts(id, sheetId, { counts, countedBy, done, userId })  POST /StockTake/{id}/Sheet/{sheetId}/Counts
   getVariance(id, onlyDiff)        GET  /StockTake/{id}/Variance?onlyDiff=
   postStockTake(id, { uncountedAsZero, reasonId, userId })     POST /StockTake/{id}/Post → { message, data: { adjNo, adjustedItems } }
   cancelStockTake(id, { userId })  POST /StockTake/{id}/Cancel
   userId = the signed-in user's login name everywhere.

2) /stock-take — list
   - Filter: from / to date (default last 90 days), status (All / Counting / Posted / Cancelled), ST number. Search.
   - Table: ST no | Title | Counted as at (freezeAt dd/MM/yyyy HH:mm) | Items (countedItems / itemCount + thin bar) |
     Sheets (sheetsDone / sheetCount) | Status badge (Counting blue, Posted green with adjNo, Cancelled grey) | open →.
   - Button "New stock take" → dialog:
       Title (optional), Category, Sub category (filtered by category), Supplier — the same pickers as Stock Balance,
       "Include items with no stock" (checkbox, off), "Items per sheet" (number, 50).
       Muted note: "The count is taken as at the moment you press Start. The shop can keep selling while you count."
       Start → createStockTake → toast message (it says how many items and sheets) → open /stock-take/:id.
       data.skipped > 0 → also a warning toast "n items are already in another open stock take and were left out".

3) /stock-take/:id — header strip: ST no, title, "Counted as at …", status badge, progress
   "Counted 120 of 340 items · Sheets done 3 of 8". Three tabs: Sheets | Enter counts | Variance.
   Status 2 / 9: everything read only, no Post / Cancel; posted shows "Adjustment ADJ… " as a link to
   /adjustment-history (search by that number).

   a) Sheets tab: table Sheet no | Name | Counted by | Lines counted (x / y) | Status (Open / Done) | actions:
      "Enter counts" (switches to tab b with that sheet), "Print".
      Buttons: "Add sheet" (dialog: name required, counted by), "Print all sheets".
      Print = a print-only A4 layout (window.print, @media print): per sheet a page break, heading
      "STOCK TAKE ST… — Sheet n: name", "Counted as at …", "Counted by ________  Checked by ________", and a table
      # | Item code | Barcode | Description | Unit | Counted (empty box, 30 mm) | Remark (empty).
      Blind count: NO system quantity on the print.

   b) Enter counts tab: sheet picker (Sheet n — name, with x / y counted) at the top, "Counted by" text box.
      - Scan / code box (autofocus): scan or type barcode / item code + Enter → jumps to that line on this sheet and
        selects its Counted box. Not on this sheet → ask "Add <code> to this sheet?" → addItem({ code }) → new line,
        focused. Unknown code → red message under the box.
      - Table: # | Code | Description | Unit | Counted (number input, 3 decimals for KGS items, whole numbers
        otherwise, ≥ 0) | Remark | Counted by / at (muted).
        Enter in Counted → next line's Counted. Empty = not counted. Changed rows get a yellow edge until saved.
      - "Show system qty" switch (off; when on, reload with showSystemQty=true and show a muted System column) —
        for checking a big difference, not for counting.
      - Buttons: Save (sends only changed rows: countedQty null when emptied), "Save and mark done" (done: true),
        "Open again" on a done sheet (done: false). Save every 30 s automatically when something changed, and warn
        before leaving the page with unsaved counts.

   c) Variance tab: getVariance (switch "Only differences and not counted", on by default).
      - Cards: Items counted x / y · Not counted n (amber) · Short Rs (red, shortValue) · Excess Rs (green,
        excessValue) · Net Rs.
      - Table: Code | Description | Category | Sheets | System qty | Counted | Difference (red −, green +) |
        Cost | Value | Remark. Not counted rows: Counted "—" amber, Difference "not counted". Sort by any column;
        default biggest |Value| first. Export CSV of what is shown.
      - Status 1: buttons
          "Post difference" (primary) → confirm dialog:
             "Post ST… ? An adjustment is made for n items (net Rs x). This cannot be undone."
             Radio for items not counted (only when uncountedItems > 0):
               (•) "Leave them as they are" (uncountedAsZero false)
               ( ) "They are not in the shop — set them to 0" (uncountedAsZero true, red text)
             Before posting call getSyncTerminals (the Stock Adjustment page already has it); any active till with
             isStale → amber warning in the dialog: "Till T02 has not uploaded sales since 10:42. Post after all tills
             have uploaded, or the system quantities may be wrong." (Post still allowed.)
             Post → toast message → reload; the variance now shows the posted figures.
          "Cancel stock take" (outline, red) → confirm → cancelStockTake → back to the list.
```

---

## Prompt 50 — Supplier bills → cheques: cheque period, upcoming payments, pay bills by cheque

Backend: Docs/StockSystem.md §6.19. Needs `U007_BackOffice_SupplierPayments.sql` on easyway and the new ItemApi.

```
Supplier bills (pencil notes in the Supplier Ledger) are now paid by cheques, and the payee list is merged into the
supplier. Change four pages. Keep everything else on them as it is.

1) Types / services
   - src/Models/SupplierEntity.ts: add  payeeName?: string | null;  creditDays?: number | null;
   - src/services/supplierLedgerApi.ts:
       SupplierLedgerEntry: add invoiceNo, dueDate, chequeId, chequeNumber, chequeDate, chequeDebited,
                            allocatedAmount, openAmount (all may be null).
       AddLedgerPayload: referenceId becomes optional (empty → the server makes SUP001-00001); add
                         invoiceNo?: string; dueDate?: string | null;
                         allocations?: { ledgerId: number; amount: number }[] | null.
       POST/PUT answer with the saved line (PUT: { message, data }).
       new  getSupplierInvoices(suppId, includePaid=false) → GET /invoices/{suppId}?includePaid=
            rows: { ledgerId, txnDate, referenceId, invoiceNo, remark, dueDate, daysToDue, amount, paidAmount,
                    deductedAmount, openAmount, status: "Open" | "Part paid" | "Paid", paidBy }
       new  getPaymentsDue(toDate?, suppId?) → GET /due?toDate=&suppId=
            rows: { ledgerId, suppId, suppCode, suppName, payeeName, creditDays, txnDate, referenceId, invoiceNo,
                    dueDate, daysToDue, amount, paidAmount, openAmount }
   - src/services/chequeApi.ts: createCheque also sends  suppId?: number | null;
       allocations?: { ledgerId: number; amount: number; deduction: number }[].
       new getChequeBills(chequeId) → GET /{id}/bills
       rows { ledgerId, txnDate, referenceId, invoiceNo, billAmount, paidByCheque, deducted }.
   - All 400 answers carry { message } → show it in a toast.

2) Supplier page (/supplier): two new fields in the add / edit form and two columns in the grid:
     "Payee name (on cheques)"  text, placeholder = the supplier name ("empty = supplier name")
     "Cheque period (days)"     number 0-365, helper "A bill is due this many days after its date"
   Always send both back on update (the API clears them when they are missing).

3) Supplier Ledger page (/supplier-ledger)
   - Add / edit dialog:
       PURCHASE: "Bill no" (invoiceNo, required for a purchase, max 50) | Date | Amount | "Due date" (date,
                 optional — prefilled with date + the supplier's creditDays and following the date until the user
                 changes it; helper "Cheque period n days") | Remark.
       "Reference" becomes read-only text: "auto (SUP001-00001)" on add, the referenceId on edit.
       PAYMENT / RETURN: Date | Amount | Remark, then a table "Pays these bills" from getSupplierInvoices(suppId)
                 (open ones; on edit also the ones this payment already pays): tick box | Bill no | Date | Due |
                 Open | "Pay" amount (prefilled with min(open, what is left of the payment)). Footer "Allocated x of
                 y". Send allocations = the ticked rows (on edit send [] when nothing is ticked). Optional — a
                 payment with no bill ticked is fine.
   - Grid: add columns "Bill no" and "Due" (PURCHASE only; red when due date < today and openAmount > 0) and
     "Open" (PURCHASE: openAmount, green "Paid" badge when 0, amber "Part paid" when 0 < open < amount).
     An entry made by a cheque (chequeId not null: its PAYMENT, and a RETURN "Deducted on cheque …"): show
     "Cheque 900001 · 20 Oct" in the Bill no column, a small
     "Debited" / "Not debited" badge (chequeDebited 1/0), and hide its edit / delete buttons (tooltip "Change it
     on the cheque").
   - Running balance column uses runningBalance from the API (a date range now starts at the opening balance).

4) Cheque Writer page (/cheque-writer)
   - Supplier search: search SUPPLIERS (searchSuppliersByName from supplierzApi) instead of payees. Dropdown row:
     "SUP001 — Suppliers 001  (Payee: Suppliers 001 (Pvt) Ltd)". On pick: payee = supplier.payeeName ||
     supplier.suppName (still editable), keep suppId; supplierName = suppName.
   - Under the form, when a supplier is picked: card "Bills from <suppName>" = getSupplierInvoices(suppId),
     switch "Show paid bills" (includePaid).
       Columns: tick | Bill no | Ref | Date | Due (red "overdue n days" / amber "due in n days" when <= 7) |
                Amount | Paid | Open | Status badge | Paid by (paidBy text, small; "less returns x" when
                deductedAmount > 0).
       Paid rows: no tick box, muted.
       When a bill is ticked, two columns appear in that row (hidden / empty when not ticked):
         "Cheque pay"  number input, prefilled with the bill's open amount (0 .. open), with small quick buttons
                       "Full" (= open) and "Half" (= open / 2, rounded to 2 decimals).
         "Rest"        shown only when cheque pay < open: the rest (= open − cheque pay) and a two-way choice
                       (segmented toggle), default "Still owing":
                         "Still owing"   → part payment: no deduction, the bill stays Part paid and the rest
                                           shows up again in the bills grid and in Upcoming payments.
                         "Less returns"  → the rest was taken off for returns: deduction = rest, the bill becomes
                                           Paid (amber text "returns x").
                       Status preview in the row: "Paid" / "Part paid — x still owing" / "Paid (less returns x)".
       The cheque Amount field is filled with the sum of "Cheque pay" of the ticked bills while the user has not
       typed an amount by hand (after that, show "Bills ticked: x — cheque: y", red when the bills are more than
       the cheque). Under the grid: "Part paid: Rs x still owing" (when any) and "Returns taken off: Rs x — those bills
       are marked paid" (when any).
       Save / print is blocked with a toast when the cheque pay total is more than the cheque amount.
   - createCheque sends suppId and allocations [{ ledgerId, amount: chequePay, deduction }] for the ticked rows,
     deduction = (Rest = "Less returns" ? open − chequePay : 0). A row with cheque pay 0 and a deduction is allowed (a bill
     settled by returns only). None ticked → the cheque is still saved, as an advance in the ledger.
     After save: toast, reload the bills grid.
     (Server side the deduction first uses returns already entered in the ledger that are not set against a bill,
     then adds a RETURN row "Deducted on cheque …"; so a return typed on the ledger page is not counted twice.)
   - New card on the right (or above the chart) "Upcoming payments" = getPaymentsDue(today + 30 days):
       grouped by due date ("Overdue" group first, red), each row: Supplier | Bill no | Open amount, and per
       group the total. Header total of everything. Clicking a row picks that supplier in the form and ticks
       that bill. A select 7 / 14 / 30 / 60 days changes toDate.
   - In the chart (cheques by date), add a second series "Bills due" = sum of openAmount by dueDate from the
     same getPaymentsDue data, so written cheques and coming bills are seen together.

5) Payee page (/payee): payees now live on the supplier. Remove "Payee" from the sidebar; keep the route, and at
   the top of the page show an info banner "Payee names are now set on the Supplier page (Payee name). This list
   is kept for old cheques." with a link to /supplier; hide its add button.

6) Cheque Summary page (/cheque-summary): the row of a cheque written for a supplier gets an expand arrow that
   loads getChequeBills(chequeId): Bill no | Ref | Date | Bill amount | Paid by this cheque | Less returns.
```

---

## Prompt 51 — Supplier Ledger: Refresh button, From / To dates start at today

Backend: nothing new (`POST api/SupplierLedger/search` already filters by date and its running balance starts at the
balance brought forward). UI only.

```
Supplier Ledger page (/supplier-ledger, src/pages/SupplierLedger.tsx):

1) From Date and To Date start filled with TODAY (yyyy-MM-dd) when the page opens.

2) One load function used everywhere, e.g. reloadLedger():
   - no supplier picked → do nothing;
   - both dates filled → searchLedger(suppId, fromDate, toDate), else getLedgerBySupplier(suppId);
   - always also getLedgerSummary(suppId) (the summary cards stay for the whole ledger);
   - loadingLedger while it runs; on error toast "Failed to load ledger".
   Send the dates as plain "yyyy-MM-dd" strings (not new Date(x).toISOString()).
   From after To → toast "From date is after To date" and don't load.

3) Picking a supplier loads with the dates shown (today..today at first), NOT the whole ledger.
   Changing a supplier keeps the dates the user set.
   After Add / Edit / Delete of an entry the grid reloads the same way (same dates).

4) Header buttons (top right, before Print): "Refresh" (outline, RefreshCw icon, spins while loadingLedger),
   disabled when no supplier is picked → reloadLedger() with the dates shown. Only this one Refresh button.

5) Date filter card buttons: "Search" → reloadLedger(); "Today" → both dates = today and reload;
   "All dates" (replaces "Clear") → empty both dates and reload (whole ledger).
   Under the inputs a muted line: "Showing <from> to <to> — balance includes earlier entries" or
   "Showing all dates" when empty.

6) Empty grid for the range → "No entries from <from> to <to>." with a link-button "Show all dates".
```

---

## Prompt 52 — Barcode labels (new, straight to the Zebra) + Label layouts

Backend: `api/Label` (ItemApi) + `DBScript/Updates/U010_BackOffice_LabelLayout.sql`. The server builds the label
itself (ZPL) and sends it to the Zebra — no BarTender, no LocalPrintAgent. **The old "Barcode Printing System" page
(BarcodePrint.tsx → api/Util/printbarcode) stays exactly as it is** — this is a second, new page.

```
Add two new back office pages and a menu entry "Barcode labels" (next to the old barcode page; keep the old one).
New service file src/services/labelApi.ts using the existing api instance (base …/api/):

  type LabelLayout = { labelLayoutId: number; labelKind: 1 | 2; name: string; printerName: string | null; printerAddress: string | null;
    dpi: number; labelWidthMm: number; labelHeightMm: number; labelsAcross: number; rowsPerPage: number;
    gapXMm: number; gapYMm: number; marginLeftMm: number; marginTopMm: number;
    barcodeType: "AUTO" | "CODE128" | "EAN13"; barcodeHeightMm: number;
    showName: boolean; showPrice: boolean; showItemCode: boolean; showDates: boolean;
    darkness: number | null; isDefault: boolean; status: number };
  GET    Label/Layouts?kind=1         → LabelLayout[] (barcode layouts, default first; kind=2 = price layouts, Prompt 53)
  POST   Label/Layouts      body      → { message, data: LabelLayout }   (send labelKind: 1)
  PUT    Label/Layouts/{id} body      → { message, data }
  DELETE Label/Layouts/{id}           → { message }
  POST   Label/Layouts/{id}/Test      → { message, data }   (prints one page with a frame round every label)
  GET    Label/Printers               → string[]  (Windows printers on the server)
  POST   Label/Print { labelLayoutId, skip, items: [{ itemId, qty, price, mfdDate, expDate }] }
                                      → { message, data: { labels, pages, printer, layoutName } }
  Errors: 400/404 { message } → toast.error(message).

PAGE 1 — /label-layouts "Label layouts" (settings page; gear icon link from the Barcode labels page header)
1) Table: Name (Default badge), Size "50 × 25 mm", Across, Rows, Printer (empty = "Server default"), DPI,
   actions Edit, Test print, Delete (confirm). Button "New layout".
2) Dialog (add / edit), sections:
   - Name (required, max 50).
   - Label size: Width mm, Height mm (of ONE label), Labels across (1-10), Rows per page (1-50; help text
     "1 for a roll. More only for sheets that print several rows at once."),
     Gap between columns mm, Gap between rows mm, Left margin mm, Top margin mm. Decimal inputs, step 0.5.
   - Printer: select from GET Label/Printers plus "(Server default)" = null; OR Network address (ip:9100) —
     typing an address clears the select. DPI select 203 / 300 / 600 (help: "in the printer's name, e.g. 203DPI").
     Darkness 0-30, empty = printer's own.
   - Barcode: type AUTO / CODE128 / EAN13 (help: "AUTO = EAN13 for 13 digit barcodes, else Code 128"),
     Barcode height mm (0 = fit the label).
   - Print on label: switches Name, Price, Item code, MFD / EXP dates.
   - "Default layout" switch.
3) Live preview in the dialog: an SVG drawn to scale (fit to the dialog width): one page = rows × across rectangles
   with the gaps and margins, each with grey placeholder bars for the parts that are switched on (name line,
   barcode block, price / code line, dates line). Under it the page size, e.g. "Page 104 × 25 mm".
4) Test print (table row, and in the dialog after saving) → POST Test → toast.success(message).
   Help text: "Prints a frame round every label. If the frames are not on the stickers, change the size, gaps or
   margins."

PAGE 2 — /barcode-labels "Barcode labels"
1) Top bar: Layout select (GET Label/Layouts, default picked; show "50 × 25 mm · 3 across"), "Skip" number input
   only when the layout has more than 1 label per page (0 … across × rows − 1, help: "labels already used on
   the first sheet"), gear link to /label-layouts.
2) Add items: one scan / search box (autofocus). Enter with a barcode → GET Itemz/GetByBarcode?barcode=…;
   text → GET Itemz/Search?query=… and pick from the list. Added item → a row; adding the same item again adds 1
   to its Qty. Focus goes back to the scan box.
3) Rows table: Item code, Name, Price (select: the retail price + the item's price links from
   GET Itemz/PriceLinks/{itemId}, "Rs 175.00"; also editable), Qty (labels, 1-1000), MFD date, EXP date (date
   inputs; only shown when the layout prints dates), remove (X).
   Footer: "<n> items · <total> labels · <pages> pages" where pages = ceil((skip + total) / (across × rows)).
4) "Print labels" (primary, Printer icon, disabled with no rows or while printing) → POST Label/Print with
   dates as plain "yyyy-MM-dd" strings → toast.success(message); keep the rows ("Clear list" button empties
   them). On error keep everything and show the message.
5) Ctrl+P = Print labels on this page.
```

---

## Prompt 53 — Price labels (new, Sinhala, many items) + price layouts

Backend: `api/Label/Price/*` + price layouts in `z_tb_LabelLayout` (`labelKind: 2`), same `U010`. The server draws the
label and prints it through the Windows printer driver (Sinhala works, any printer). **The old "Price Label Print"
page (PricePrint.tsx → api/Util/printprice / printDiscountPrice / printitempricelandscape) stays exactly as it is.**
Do Prompt 52 first (it makes the Label layouts page).

```
1) src/services/labelApi.ts — add to LabelLayout: language: 1 | 2 | 3; rotate: boolean; sinhalaFont: string | null;
   englishFont: string | null; footerText: string | null. Add:
     GET  Label/Layouts?kind=2               → price layouts
     GET  Label/Layouts/{id}/Preview         → PNG (blob) of the layout's test page
     POST Label/Price/Print   { labelLayoutId, language, skip, items: PriceLine[] } → { message, data }
     POST Label/Price/Preview?page=n  same body → PNG (blob)  (responseType "blob"; on 400 read the blob as JSON
                                                             for { message })
     type PriceLine = { itemId: number; qty: number; style: "AUTO" | "PRICE" | "DISCOUNT"; price?: number | null;
       discountAmount?: number | null; discountPercent?: number | null; name?: string | null; sinhalaName?: string | null };

2) Label layouts page (/label-layouts, Prompt 52): two tabs "Barcode labels" (kind 1, as now) and "Price labels"
   (kind 2). "New layout" sends labelKind of the open tab; the kind is never changed on edit.
   Price layout dialog: same Name / Label size / Printer select (NO network address, NO DPI / darkness / barcode
   fields) and Print on label switches Name, Price, Item code (no dates). Extra:
   - Language select: English / Sinhala / Both.
   - "Landscape (turned 90°)" switch = rotate.
   - Sinhala font (default "Iskoola Pota"), English font (default "Courier New") — text inputs, empty = default.
   - Footer text (max 100; "printed on labels without a discount, e.g. the shop slogan").
   - Preview: for a saved price layout show <img> of GET Layouts/{id}/Preview (refresh after Save) instead of the
     SVG sketch.

3) New page /price-labels "Price labels". Menu (src/components/Sidebar.tsx): add it to the "Labels" group between
   "Barcode labels" and "Label layouts" (icon Tag). The old "Price Print" stays in the "Old system" group.
   - Top bar: Layout select (kind 2, default picked, "72 × 25 mm · 1 across"), Language toggle
     English / Sinhala / Both (starts at the layout's language), Skip (only when across × rows > 1), gear → /label-layouts.
   - Scan / search box (autofocus) as on Barcode labels: barcode → GET Itemz/GetByBarcode, text → GET Itemz/Search.
     Added item → row; same item again → Qty + 1. Fill the row from the item: name (inv_Descrip or descrip),
     sinhalaDescrip, retailPrice, discountAmount, discountPercent.
   - Rows table: Item code, Name (editable), Sinhala name (editable, font "Iskoola Pota"), Price (editable),
     Discount Rs (editable), Discount % (editable), Style select Auto / Price / Discount, Qty (1-500), remove.
     Send a field only when the user changed it (else null → the server uses the item's value).
     Style "Discount" with no discount → red row hint "No discount on this item".
   - Right side (or below on small screens): Preview card — POST Price/Preview with the current rows, debounced
     500 ms after any change; show the PNG fit to the card width with a light border; "Page 1 of n" with ‹ › when
     more pages (pages = ceil((skip + total qty) / (across × rows))). Preview error → show its message in the card.
   - Footer: "<n> items · <total> labels · <pages> pages"; buttons "Print price labels" (primary, Printer icon,
     disabled with no rows / while printing) → POST Price/Print → toast.success(message); "Clear list".
   - Ctrl+P = Print price labels on this page.
```

---

## Prompt 54 — Cashier billing: touch keyboard (sign-in, bank transfer / cheque), Menu button, layout rearranged

No backend change. Fixes typing on a touch-only till (no physical keyboard) and moves buttons again. Changes the
layout of Prompt 34 (function bar) and Prompt 32 (pay dialog keypad). Keep every function, rule, PIN check, dialog,
shortcut key and API call exactly as it is — only the on-screen keyboard is new; the rest is WHERE the buttons are.

```
Change src/pages/CashierBilling.tsx, src/components/till/CashierSignIn.tsx, src/components/till/FunctionBar.tsx,
src/components/till/PriceCheckDialog.tsx; add src/components/till/TouchKeyboard.tsx.

1) New shared on-screen keyboard (TouchKeyboard.tsx) — the one PriceCheckDialog has inline today, made reusable:
     props: onKey(k: string) where k is a character, " ", "⌫", "C" or "Enter"; enterLabel?; enterDisabled?
   - Rows: 1 2 3 4 5 6 7 8 9 0 / Q W E R T Y U I O P / A S D F G H J K L - / Z X C V B N M . / # ,
     then Space (wide) · ⌫ · Clear · Enter (primary). Upper case only.
   - Keys h-12, text-lg font-semibold, grid-cols-10, gap 4 px. Every key onMouseDown preventDefault (the input
     keeps focus, the Windows touch keyboard never pops up).
   - PriceCheckDialog uses this component instead of its inline keys (same ⌨ toggle, same behaviour).

2) Cashier sign-in (CashierSignIn.tsx) — the user name cannot be typed on the touch screen (the keypad is digits only):
   - Add a ⌨ button (h-14 w-14, same style as Price check) at the right end of the User name box.
   - When the User name field is active the right side shows the TouchKeyboard instead of the number pad;
     when the Password field is active it shows the number pad as now. The ⌨ button switches between the two
     by hand as well (for a letter password). Tapping a field switches to its pad.
   - TouchKeyboard keys type into the active field with the same rules as press() (max 50, ⌫, C = clear);
     Enter on User name → Password, Enter on Password → Sign in.
   - Make the card wide enough for the keyboard: max-w-5xl, form 2/5, pad 3/5. Must fit 1366×768 without scroll.

3) Pay by Bank transfer / Pay by Cheque dialog — the slip / cheque number and details cannot be typed by touch:
   - For bank / cheque (payOther) the right side of the dialog shows the TouchKeyboard instead of the NumPad;
     it types into "Transfer ref / slip no" / "Cheque no" (max 30, the database limit), Enter = Complete.
   - Label hint under the field: bank → "Slip no and bank, e.g. 458812 BOC"; cheque → "Cheque no and bank,
     e.g. 004512 HNB". Field font as tillInput, upper case.
   - Card / Mixed: the "Card ref / approval no" field gets a small ⌨ button; while it is on, the TouchKeyboard
     replaces the NumPad and types into the card ref. Cash / card amount fields keep the NumPad.
   - Refund by bank / cheque: same as sale.

4) Top toolbar → Search · Reload · Profit · Keys · Theme · [ Menu ▾ ] — then Cashier name / Sign out at the right.
   - "Other item" and "Discount %" move OUT of the top toolbar into the bottom function bar (point 5).
   - New "Menu" button (icon Menu / three lines, same size as Theme) directly right of the Theme toggle.
     Tap → dropdown (Popover, h-12 rows, ↑/↓, Enter, Esc) with: Drawer summary · X report · Day end.
     Each item calls runAction("drawerSummary" | "xReport" | "dayEnd") — same rules as today (disabled while
     paying; Day end disabled while the bill has lines; Day end row in amber text). Shortcut keys (Alt+X, Ctrl+E …)
     still work without opening the menu, and the key chip shows on each menu row.
   - Drawer summary, X report and Day end are REMOVED from the bottom bar (only in the Menu afterwards).

5) Bottom function bar — now sits ONLY under the bill lines (left column), NOT under the right panel.
   Two rows of 9 equal buttons (grid-cols-9, gap 6 px, padding 6 px, h-14, icon above label, text-xs, labels may
   wrap, min-w-0 — no label cut off). Order:
     Row 1 (the bill):  Qty · Price · W/R · Void line · Wholesale · Other item · Discount % · Price check · Void bill
     Row 2 (the drawer): Refund · Bill copy · Reprint · No Sale · Suspend · Recall · Paid In · Paid Out · Opening cash
   - W/R, Void line, Wholesale move here from the right panel (same rules: W/R / Void line need a selected line,
     Wholesale shows the "on" ring in wholesale mode, W/R the ring on a wholesale line).
   - Other item, Discount % move here from the top toolbar (Discount % disabled in refund / with no lines).
   - Colours as now: navy; Void bill red. The F12 cash popover still opens above Paid In and still lists
     Paid In / Paid Out / Opening cash / Drawer summary.

6) Right panel = its own full-height column (w-[26rem]) from below the top toolbar down to the status bar — the
   function bar never runs under it. Top to bottom:
     totals (as now) → keypad (flex-1, the 4×4 keys + Enter, as now) →
     [ Cash ][ Card ][ Mixed ]            (one row of 3, tillPayBtn, as now)
     [ Bank transfer ][ Cheque ]          (one row of 2, h-14, as now)
   The pay buttons are at the BOTTOM of the right column, under the keypad, in line with the function bar.

7) Page = h-screen flex column: top toolbar · main (flex-1 min-h-0: [left: scan box, banners, bill lines flex-1
   scroll, function bar] | [right column]) · status bar (full width). No page scroll bar.
   Check at 1366×768 and 1920×1080, touch: all 18 bottom buttons visible, no button under 56 px, at least 7 bill
   lines visible at 1366×768, keypad keys not smaller than 48 px, sign-in and pay dialogs fit without scrolling.
```

---

## Prompt 55 — Cashier billing: F1 never opens Chrome help; F1 in Search = clear and search again

No backend change. Today the second F1 (pressed while the Search dialog is open) is not stopped, so Chrome opens its
help page (support.google.com) and the till page is left. Cause: in the shortcut handler in CashierBilling.tsx,
`if (dlgRef.current) { … return; }` only calls preventDefault for reprintLast / priceCheck / xReport.

```
Change src/pages/CashierBilling.tsx only.

1) Browser keys never reach Chrome on the till page. In the capture-phase keydown listener that already blocks
   F5 / Ctrl+R (the "Page-reload keys never reload the till" effect), also call e.preventDefault() — WITHOUT
   stopPropagation, so the till's own shortcuts and dialog keys still get the key — for:
     F1 … F12 (any modifiers), Ctrl+F, Ctrl+G, Ctrl+H, Ctrl+J, Ctrl+D, Ctrl+P, Ctrl+S, Ctrl+U, Ctrl+N, Ctrl+T,
     Ctrl+W, Ctrl+Shift+N, Alt+Home, Alt+ArrowLeft, Alt+ArrowRight, BrowserBack / BrowserHome keys.
   This listener works on every screen of the till page: the sign-in screen, the billing page and every dialog.

2) F1 (the "search" action) while a dialog is open:
   - Search dialog open → run the search action again: clear the text and the result rows, index back to 0,
     on-screen keyboard closed, focus the search box (the same as a fresh F1). No second dialog, no flicker.
   - Any other dialog open → do nothing (the key is already blocked by point 1).
   In the shortcut handler change the dialog branch to:
     if (dlgRef.current) {
       e.preventDefault();
       if (action === "search" && srch !== null && !e.repeat) { e.stopPropagation(); runRef.current("search"); }
       return; // other dialogs keep their own keys
     }
   (use a ref for "the Search dialog is open" so the listener does not read a stale value.)
   After the reset, put focus back in the search box (setTimeout 0).

3) Test: F1 → Search opens. Type "sug", F1 → box empty, rows gone, still in Search, cursor in the box. F1 ten
   times fast → still the till page, never the Google help page. F1 / F3 / F7 / Ctrl+F on the sign-in screen and
   in the payment dialog → nothing happens in Chrome. All shortcut keys from the Keys dialog still work as before.
```

---

## Prompt 56 — Cashier billing: No Sale without PIN, cash in drawer only with the PIN, reports in the Menu

Backend: TillService only (no db update). `POST /drawer/nosale` no longer asks for a PIN; new report routes
`POST /cash/summary/print`, `GET|POST /reports/suspended[/print]`, `GET|POST /reports/refunds[/print]?zNo=`.
Day end now ALWAYS prints the CASH IN / OUT slip (opening cash, paid in, paid out) before the Z slip — nothing to do on
the page. Do Prompt 54 first (it makes the Menu button).

```
Change src/services/tillLocalApi.ts, src/lib/tillShortcuts.ts, src/pages/CashierBilling.tsx,
src/components/till/XReportDialog.tsx; add src/components/till/SuspendedReportDialog.tsx and RefundReportDialog.tsx.

1) No Sale — no PIN.
   - tillLocalApi: noSale(cashierId: string, reason: string | null) → POST /drawer/nosale { cashierId, reason }.
   - No Sale dialog: remove the PIN field and the NumPad. Keep the reason chips (Change · Cash count · Wrong change ·
     Other) and the Reason box (TouchKeyboard from Prompt 54 under it while "Other" is picked). "Open drawer (Enter)"
     is enabled as soon as there is a reason (Change is picked by default → one tap / Enter opens the drawer).
   - Remove the "Wrong PIN" handling for No Sale.

2) CASH IN DRAWER and over / short only after the supervisor PIN (blind cash-up).
   Applies to the Drawer summary dialog, the X report dialog and the Z summary dialog after day end.
   - Hide the "= Cash in drawer" / "CASH IN DRAWER" figure and the "Exact / short Rs … / over Rs …" line.
     Opening cash, cash sales, paid in, paid out and the movement list stay visible.
   - In their place a button "Show cash in drawer (PIN)" (outline, h-11, Eye icon). Tap → the supervisor PIN dialog
     (new pinFor "showCash", title "Supervisor PIN — Show cash in drawer"; if hasSupervisorToken() is already true,
     no dialog). After the PIN: the figure appears, and in the Z dialog the over / short line appears under
     "Counted cash" as today. Hidden again when that dialog closes (each dialog opens hidden).
   - Z summary: "Counted cash" stays (the cashier types the count without seeing the expected figure); with the
     TouchKeyboard / NumPad as other number fields.

3) Menu (Prompt 54) — reports, in this order:
     Drawer summary · X report · Suspended bills · Refunds · ── · Day end
   tillShortcuts.ts: add actions "suspendedReport" (label "Suspended bills") and "refundReport" (label "Refunds"),
   no default key. runAction opens the dialogs below. Disabled while paying.

4) Drawer summary dialog: add a "Print" button (Printer icon) in the footer next to Close →
   POST /cash/summary/print (send X-Supervisor-Token when held — then the slip shows CASH IN DRAWER) →
   printed ? toast.success("Drawer summary printed") : toast.error(printError). 400 → toast.info(message).

5) Suspended bills report (SuspendedReportDialog.tsx), max-w-3xl:
   GET /reports/suspended → { takenAt, waiting: Row[], closed: Row[] },
     Row = { suspendId, label, cashierId, lineCount, netAmount, suspendedAt, status (1|2|9), closedAt, closedBy }.
   - "Waiting (n)" table: #, Suspended at (dd/MM HH:mm), Cashier, Note (label), Lines, Amount (right). Total row.
   - "Today — recalled / cancelled (n)" table: #, Status chip (Recalled = primary, Cancelled = destructive),
     Closed at (HH:mm), By, Note, Amount.
   - Empty → "No suspended bills". Footer: Print (POST /reports/suspended/print) · Close.

6) Refunds report (RefundReportDialog.tsx), max-w-3xl:
   GET /reports/refunds → { zNo, zOpen, takenAt, total, rows: [{ invoiceNo, invDate, cashierId, refInvoiceNo,
     lineCount, netAmount, payType }] }. Title "Refunds — Z {zNo}" + "(not closed)" when zOpen.
   - Table: Time (HH:mm), Refund bill, Sale bill (refInvoiceNo or "—"), Cashier, Lines, Paid back (payType name:
     1 Cash, 2 Card, 3 Credit, 4 Voucher, 5 Bank transfer, 6 Cheque), Amount (right, destructive colour).
   - Under it: total per pay type and "Total refunds (n)  Rs …" bold.
   - Tap a row → the bill preview the Bill copy dialog already uses (getInvoice(invoiceNo)), with its Print copy.
   - 400 → "No Z on this till yet". Footer: Print (POST /reports/refunds/print?zNo=) · Close.

7) Both report dialogs: h-12 table rows (touch), scroll inside the dialog (max-h-[60vh]), Esc / Close → focusScan().
   Printing never opens the drawer. All printing answers are { printed, printError } like the X report.
```

---

## Prompt 57 — Cashier billing: ⌨ touch keyboard on every text box that takes letters

No backend change. Prompt 54 added TouchKeyboard (src/components/till/TouchKeyboard.tsx) to sign-in, Price check,
No Sale and bank / cheque pay. These text boxes still have NO way to type letters on a touch-only till:

  1. Suspend bill — "Note / customer name"                       (CashierBilling.tsx, Suspend dialog)
  2. Paid In / Paid Out — "Reason"                                (CashierBilling.tsx, cash dialog)
  3. Other item — "Description"                                   (CashierBilling.tsx, Other item dialog)
  4. Refund against bill — "Scan / enter bill number" (T01-00000123) (RefundBillDialog.tsx, scan box)
  5. Refund against bill — "Card ref / Transfer ref / Cheque no"   (RefundBillDialog.tsx, pay back)
  6. Bill copy — "Invoice no (last digits)"                       (CashierBilling.tsx, Bill copy dialog)

```
Change src/pages/CashierBilling.tsx and src/components/till/RefundBillDialog.tsx. Use the existing TouchKeyboard and
touchValue(value, key, max, clear) — no second keyboard component.

The same rule for every box in the list:
- A ⌨ button (h-12 w-12, outline; "default" variant while on; onMouseDown preventDefault) at the right end of the
  box, in one flex row with it — the same look as the ⌨ in Price check.
- Tap ⌨ → the TouchKeyboard shows inside the dialog (where the NumPad is, the NumPad is hidden while the keyboard is
  on; dialogs without a NumPad show it under the box). Tap ⌨ again → back to the NumPad.
- Keys type into that box with touchValue and the box's own max length (Suspend note 50, Reason 100, Other item
  description 50, bill number 30, ref 30, invoice filter 30); the box keeps focus (no Windows keyboard pops up).
- TouchKeyboard Enter = the dialog's main action, the same as the Enter key in that box today
  (Suspend → Suspend; Paid In/Out → Save; Other item → Add; refund scan → look up the bill; refund ref → Refund;
  Bill copy → open the first match).
- Each dialog opens with the keyboard OFF, except the Suspend dialog: it opens with the keyboard ON (the note is the
  only field). Closing a dialog turns its keyboard off.
- Tapping a number box in the same dialog (Amount, Price, Qty, PIN) turns the keyboard off and goes back to the
  NumPad typing into that box, as today.
- Dialog widths grow so the keyboard fits without scrolling at 1366×768: Suspend max-w-2xl, Paid In / Out max-w-2xl,
  Other item max-w-2xl. Keys never smaller than h-12.

Test on the touch screen with no physical keyboard: suspend a bill with note "MR PERERA", paid out with reason
"TEA 2 CUPS", other item "PLASTIC BAG", refund by typing T01-00000030, refund by cheque with "004512 HNB", bill copy
filter "30" — all without the Windows keyboard ever opening.
```

---

## Prompt 58 — Refund against the bill: "No bill — refund without a receipt" looks like a button

No backend change. In RefundBillDialog.tsx the button is variant="ghost" (no border, no fill), so on the till it
reads as plain text and cashiers do not see that it can be tapped.

```
Change src/components/till/RefundBillDialog.tsx, footer only.
- "No bill — refund without a receipt": variant="outline" (not ghost), border-2 border-warning, icon ReceiptText
  (lucide) before the label, h-12, text-lg font-semibold — the same size as the other footer buttons.
- Put it at the LEFT of the footer (mr-auto), apart from Another bill · Close (Esc) · Refund Rs … on the right,
  so it is not mistaken for the main action.
- Same click as now (onNoReceipt → the old refund mode). Label may wrap to two lines on a narrow screen; never cut off.
- Check at 1366×768: all four footer buttons visible in one row, none smaller than h-12.
```

---

## Prompt 59 — Till: Printer settings in the Menu (Windows printer / COM port / network), printer status dot

Backend: TillService only (no db update). New routes `GET|PUT /printer/settings`, `GET /printer/devices`,
`GET /printer/status`, `POST /printer/test`. Saving needs the supervisor token; the settings are kept on the till in
printer.json and used from the next print (no restart). Print errors are now real: a job the printer did not take is
cancelled and `printError` says why ("Printer 'POS' is not printing … The job was cancelled.").

```
Change src/services/tillLocalApi.ts, src/lib/tillShortcuts.ts, src/components/till/TillMenu.tsx,
src/pages/CashierBilling.tsx; add src/components/till/PrinterSettingsDialog.tsx.

1) tillLocalApi.ts:
   type PrinterSettings = { mode: 1 | 2 | 3; name: string | null; port: string | null; baudRate: number;
     handshake: "None" | "RequestToSend" | "XOnXOff"; address: string | null; charsPerLine: number; drawerPin: 0 | 1;
     cut: boolean; feedLines: number; timeoutSeconds: number; jobTimeoutSeconds: number; checkStatus: boolean };
   type WindowsPrinter = { name: string; port: string | null; driver: string | null; jobs: number;
     problem: string | null; blocked: boolean };
   type PrinterStatus = { ok: boolean; mode: number; target: string; answered: boolean; paperNearEnd: boolean;
     jobs: number; problem: string | null; checkedAt: string };
   getPrinterSettings()  → GET /printer/settings  → { settings: PrinterSettings; savedInFile: boolean }
   savePrinterSettings(s) → PUT /printer/settings (X-Supervisor-Token as other token calls) → same shape; 401 → PIN
   getPrinterDevices()   → GET /printer/devices   → { windowsPrinters: WindowsPrinter[]; comPorts: string[] }
   getPrinterStatus()    → GET /printer/status    → PrinterStatus
   testPrinter(settings: PrinterSettings | null, openDrawer: boolean) → POST /printer/test
                         → { printed, drawerOpened, printError, status: PrinterStatus }   (timeout 15 s for this call)

2) Menu (TillMenu.tsx): add "Printer settings" (icon Printer) after Refunds, before the Day end separator.
   tillShortcuts.ts: action "printerSettings", label "Printer settings", no default key. Disabled while paying.

3) PrinterSettingsDialog.tsx — max-w-3xl, opens with getPrinterSettings() + getPrinterDevices().
   Top: "How is the printer connected?" — three big toggle buttons (h-16, icon + two lines), one is selected:
     [1  Windows printer   USB, through Windows]  [2  COM port   Epson virtual port / serial]  [3  Network   IP address]
   Under it only the fields of the picked mode:
   - 1 Windows printer: a Select (h-12, text-lg) of devices.windowsPrinters by name; each option shows the name and,
     muted, the port (USB001) and driver; a printer with problem shows it in red after the name ("set to 'Use printer
     offline' in Windows"), with jobs > 0 "· 5 jobs waiting". Refresh button (RefreshCw) reloads the list.
     If the saved name is not in the list, show it as the first option with "(not found on this PC)".
     Help text: "Tip: rename the printer in Windows to a short name like POS, and keep the USB cable in the same port."
     Advanced (collapsed): "Wait for Windows queue (seconds)" 2–30, default 4.
   - 2 COM port: Select of devices.comPorts (COM3 …) + Refresh; Baud rate Select 9600 / 19200 / 38400 / 57600 /
     115200 (default 38400); Handshake Select None / RTS/CTS (value "RequestToSend") / XON/XOFF (value "XOnXOff").
     Help text: "Epson: install the EPSON TM Virtual Port Driver, assign the printer to a COM port, then pick it here.
     Baud rate and handshake only matter on a real serial cable." Empty list → "No COM ports on this PC."
   - 3 Network: Address input "192.168.1.50:9100" (TouchKeyboard ⌨ as Prompt 57; the box accepts digits, dots,
     letters, ':'), Timeout (seconds) 1–30, default 5.
   - Modes 2 and 3: switch "Check printer status before printing (paper, cover, power)" = checkStatus, default on;
     hint "Turn off only if this printer does not answer status requests."
   Common (all modes), in a compact 2-column grid:
     Paper width: Select "80 mm — 48 chars" (48) / "80 mm — 42 chars" (42) / "58 mm — 32 chars" (32);
     Drawer pin: "Pin 2 (most drawers)" (0) / "Pin 5" (1); Cut paper (switch); Feed lines before cut 0–10 (NumPad).
   Status box (right or below): getPrinterStatus() of the SAVED settings on open (nothing printed):
     green "Ready — <target>" / red "<problem>" / amber "Paper nearly finished" (paperNearEnd). Re-check button.
   Footer buttons (h-12):
     [Test print] → testPrinter(current form, false): printed ? toast.success("Test slip printed — check the
       ruler line fits on one line") : toast.error(printError). Also refreshes the status box from result.status.
     [Test drawer] → testPrinter(current form, true) (prints the slip AND opens the drawer).
     [Cancel]  [Save] (primary) → savePrinterSettings(form); 401 → the supervisor PIN dialog (pinFor "printer",
       title "Supervisor PIN — Printer settings"), then save again. Saved → toast.success("Printer settings saved"),
       close, refresh the status dot. 400 → toast.error(message) and keep the dialog open.
   Saving does NOT need a test first, but if the last Test print of these exact settings failed, Save asks
   "The test print failed. Save anyway?" (Save anyway / Back).
   savedInFile false → small muted line "Using the settings from appsettings.json (not saved here yet)."

4) Printer status dot in the status bar (next to Online / Offline): getPrinterStatus() on page load, every 60 s,
   and right after any print answer with printError. Green dot + "Printer" when ok; red dot + "Printer: <problem>"
   (truncate, full text in title) when not; amber when paperNearEnd. Tap → opens Printer settings.
   Never poll while a print request is running (the till prints one job at a time).

5) Every printError toast (bill, reprint, No Sale, cash movement, reports, Z / X) gets an action button
   "Printer settings" that opens the dialog. Keep the existing messages.
```

---

## Prompt 60 — Cashier billing: Search / Select item dialog stays fixed at the top (does not jump when results load)

No backend change. Today the Search dialog (F1 / the Search button) opens in the middle of the screen; when the
cashier types the 2nd letter the result rows load, the dialog gets taller and — because the shadcn DialogContent is
centred (top-[50%] translate-y-[-50%]) — the whole dialog jumps up. The text box moves under the cashier's eyes and
the focus "feels" lost. Same for the "Select item — '<text>'" list and the Price check list (Prompt 37).

```
Change the item Search dialog and the "Select item" dialog in src/pages/CashierBilling.tsx (or their own
components under src/components/till/), and the Price check dialog's result list. Do NOT change
src/components/ui/dialog.tsx (other dialogs stay centred).

1) Anchor these dialogs to the top of the screen, not the centre. On their DialogContent add:
     className="top-[4vh] translate-y-0 data-[state=open]:slide-in-from-top-2 data-[state=closed]:slide-out-to-top-2
                max-w-3xl flex flex-col max-h-[92vh]"
   (keep left-[50%] translate-x-[-50%] from the base, so it stays centred left/right).
   The dialog opens at the top and its top edge never moves — not when rows load, not when the list is empty,
   not when the "No item found" line shows, not when the ⌨ on-screen keyboard opens.

2) Layout inside (top → bottom): title, text box + ⌨ button (always the first thing, fixed position), the
   on-screen keyboard when open, then the result list. Only the list area changes: flex-1 min-h-0 overflow-y-auto.
   Give the list area a fixed height while the dialog is open (h-[60vh], or less when the ⌨ keyboard is open —
   e.g. h-[32vh]) so the dialog does not grow or shrink as the cashier types; empty / "Type at least 2 letters" /
   "Searching…" / "No item found" are shown inside that same area.

3) Focus: the text box keeps the focus and the caret position while typing; the result load must not re-mount the
   input or the dialog (no key change, no conditional render of the input). ↑/↓ highlight scrolls the highlighted
   row into view inside the list only (scrollIntoView({ block: "nearest" })), never the page.

4) Check at 1366×768 and 1920×1080: F1 → dialog at the top. Type "s", "su", "sug", backspace to "s", "xyzq" (no
   result) — the text box stays exactly in the same place every time. 5*sugar with several results → Select item
   opens at the top the same way. Open ⌨ → the keyboard appears under the box, the box does not move.
```

---

## Prompt 61 — Cashier billing: scan box finds an item by part of its code

Backend: TillService + till db update U011 (`zf_sp_SearchItems @Codes`). Rule of the scan box (and Price check):
1. exact Barcode → that item only, 2. else exact RefCode → that item only (both `GET /items/find`, unchanged),
3. else `GET /items/search?text=…&codes=true` — RefCode or Barcode containing the text, plus the name; codes
starting with the text first. ItemId is never searched. The Search dialog (F1) is NOT changed.

```
Change src/services/tillLocalApi.ts, src/pages/CashierBilling.tsx, src/components/till/PriceCheckDialog.tsx.

1) tillLocalApi.ts: searchItems(text: string, codes = false) → GET /items/search?text=...&codes=true when codes
   (leave the parameter out when false). The Search dialog keeps calling searchItems(text).

2) CashierBilling.tsx, addItem — after findItem(text) answers 404:
   - today: digits only → "Item '<text>' not found"; with letters → searchItems(text).
   - now: ALWAYS searchItems(text, true) (digits too, when text is 2+ characters):
       0 rows → red toast "No item found for '<text>'" (clear the box, focus stays as today)
       1 row  → add it (getItem(rows[0].itemId)), same as today
       2+     → the "Select item — '<text>'" dialog as today (qty from "5*" kept)
   - findItem (exact barcode, then exact item code, scale sticker) stays first and unchanged.

3) PriceCheckDialog.tsx: the same — after a 404 call searchItems(text, true) instead of only for text with letters.

4) Test: 10034 → white raw 1kg added at once (exact code). 30010883 (its barcode) → same item at once.
   1003 → Select item list: 10030, 10034, 10037, 10038 … first. sugar → list as today. F1 Search "1003" → no rows
   (dialog unchanged).
```
