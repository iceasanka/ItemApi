# Stock System — Ledger, Adjustments, Cashier Sync, Z Reports

> Implementation notes for the stock work added on 2026-09-30.
> UI prompts for Lovable are in [Lovable-UI-Prompts.md](Lovable-UI-Prompts.md).

---

## 1. The idea in one paragraph

Stock is **never** a single "Qty" number that people overwrite. Every movement — GRN, PRN, sale,
refund, adjustment — is **one row** in `z_tb_StockLedger` (`+` in, `-` out) and rows are never
updated or deleted. Current stock is the sum of those rows, kept ready in `z_tb_StockBalance`.
Because of this, cashier tills can work **offline** and upload their sales hours later, in any
order, and the stock still comes out right: `10 − 3 (till 1) − 3 (till 2) = 4` no matter who
uploads first.

```
            BACK OFFICE (easyway db, always online)
   GRN (+qty)   PRN (−qty)   Adjustment (±qty)   Items / prices
        │            │              │                  │  download only
        └────────────┴──────────────┘                  ▼
                     ▼                           CASHIER TILLS (zf_ db each, online/offline)
            z_sp_PostStockMovements  ◄── sales ──   T01, T02, T03 …  bill items only
                     ▼                 (upload only)
     z_tb_StockLedger  →  z_tb_StockBalance
```

Who does what (Food City style):

| | Back office | Cashier till |
|---|---|---|
| Creates | GRN, PRN, stock adjustments, items & prices | sales bills, refunds |
| Stock effect | GRN +, PRN −, adjustment ± | sale −, refund + |
| Network | always online | works offline, uploads when it can |
| Downloads | — | items, prices, stock (display only) |

Nothing is edited by both sides, so there are no sync conflicts to merge.

---

## 2. Files

### SQL (`DBScript/`)
| File | Run on | Notes |
|---|---|---|
| `01_BackOffice_Stock.sql` | back office db (`easyway`) | prefix `z_`. **Already applied to easyway on 2026-09-30.** Re-runnable. |
| `02_FrontCashier_zf.sql` | each till's local db (e.g. `easyway_front` on SQL Express) | prefix `zf_`. Re-runnable. Applied to the test till db `z_pos_fnt_db` (PRASADA1). |
| `03_BackOffice_PriceLink.sql` | back office db (`easyway`) | price links (§6.5). Re-runnable. **Applied to easyway on 2026-10-02.** |
| `04_BackOffice_SalesDashboard.sql` | back office db (`easyway`), after `01` | sales dashboard procs (§6.9). Re-runnable. **Applied to easyway on 2026-10-06.** |
| `05_BackOffice_Export.sql` | back office db (`easyway`) | export settings, log, scale snapshot (§6.10). Re-runnable. **Applied to easyway on 2026-10-08.** |
| `06_BackOffice_SalesDoc.sql` | back office db (`easyway`) | customers, quotations, invoices, PDF settings (§6.11). Re-runnable. **Applied to easyway on 2026-10-08.** |
| `08_Transfer_OldItems.sql` | back office db (`easyway`) | one-time copy of old `tb_Item` / `tb_ItemDet` into `z_tb_Item` / `z_tb_ItemDet` (§6.13). Re-runnable. **Run on easyway on 2026-10-09: 5 419 items copied.** |
| `09_Clean_ItemData.sql` | back office db (Part A) + each till db (Part B) | **clean start before going live**: deletes all items and everything that points at them (stock, till uploads, Z reports, price links, quotations/invoices, GRNs, transfer links) and resets their ids. Report only unless `@Delete = 1`. **Run on easyway on 2026-10-09** (Part A only). |
| `14_BackOffice_StockTake.sql` | back office db (`easyway`), after `01` | stock take (§6.18). Same content as `Updates/U006_BackOffice_StockTake.sql`. Re-runnable. **Applied to the dev easyway (PRASADA1) on 2026-10-14.** |
| `15_BackOffice_SupplierPayments.sql` | back office db (`easyway`) | supplier bills → cheques, payees merged into suppliers (§6.19). Same content as `Updates/U007_BackOffice_SupplierPayments.sql`. Re-runnable. **Applied to the dev easyway (PRASADA1) on 2026-10-14.** |
| `18_Till_ResetCopiedDb.sql` | a NEW till PC whose `z_pos_fnt_db` was restored from another till's backup (`-E`, `-d z_pos_fnt_db`) | makes the copy an empty new till: deletes the copied till's bills / payments / suspended bills / Z reports / drawer log / cash in-out (identities restart: Z 1, bill 1), sets the new terminal via `zf_sp_SetupTerminal` (same LocationId / ApiBaseUrl); keeps items, price links, stock, cashiers, sync times. Guards: `ThisPc` must be this computer's name, no other connection (stop TillService), refuses a db that already has bills of the new code; without `Confirm="YES"` only lists what it would delete. Tested on a restored copy of the dev till 2026-10-16. |
| `17_Till_SqlLogin.sql` | each till's SQL Server (`-E`, as admin) | the SQL login TillService uses (`ice`): mixed mode on when needed (then restart SQL Server), login (no expiry), db_owner user in `z_pos_fnt_db`, fixes the orphaned user of a restored backup. Password given with `-v`, not in the file. Re-runnable. |
| `16_BackOffice_LabelLayout.sql` | back office db (`easyway`) | label layouts for the new barcode labels (ZPL, §6.20) and price labels (§6.21). Same content as `Updates/U010_BackOffice_LabelLayout.sql`. Re-runnable. **Applied to the dev easyway (PRASADA1) on 2026-10-16.** |
| `19_BackOffice_ReturnList.sql` | back office db (`easyway`) | Return Items list → PRN, mobile app scanning (§6.22). Same content as `Updates/U016_BackOffice_ReturnList.sql`. Re-runnable. **Applied to the dev easyway (PRASADA1) on 2026-10-23.** |
| `20_BackOffice_MobileGrn.sql` | back office db (`easyway`) | mobile app GRN drafts (suspended GRN per supplier, §6.23). Same content as `Updates/U017_BackOffice_MobileGrn.sql`. Re-runnable. **Applied to the dev easyway (PRASADA1) on 2026-10-23.** |
| `07_BackOffice_Users.sql` | back office db (`easyway`), after `01` | users, roles, cashier download for tills (§6.12). Re-runnable. **Applied to easyway on 2026-10-09.** `02` got a "Cashier sign-in" section at the end — applied to `z_pos_fnt_db` the same day. |

`01` and `03` re-applied to easyway on 2026-10-06 (`CostPrice` in the till downloads, §6.7); `02` applied to `z_pos_fnt_db`.
Deploy order: back office scripts + ItemApi first, then each till (`02` + TillService) — ItemApi's `SyncItem` reads `CostPrice`.

Run with `sqlcmd -I` (QUOTED_IDENTIFIER must be ON for the filtered index), e.g.
`sqlcmd -S SERVER -d easyway -U user -P *** -I -b -i DBScript\01_BackOffice_Stock.sql`

> The `easyway` database is at **compatibility level 100 (SQL 2008)** even though the server is
> SQL 2022. So the procs avoid `OPENJSON`, `STRING_AGG … WITHIN GROUP` and running `SUM() OVER`;
> batches are passed as **table-valued parameters** (`z_tt_*`). If the level is ever raised, nothing breaks.

### C# (API)
| Area | Files |
|---|---|
| Data | `Data/AppDbContext.StockLedger.cs` — DbSets (read-only) + calls to every `z_sp_*` proc with TVPs |
| Models | `Models/StockLedger.cs`, `StockBalance.cs`, `StockAdjustment.cs`, `StockQueryModels.cs`, `SyncModels.cs`, enums in `Common/Meta.cs` |
| Repos | `StockLedgerRepository`, `StockAdjustmentRepository`, `SyncRepository` (+ interfaces) |
| Controllers | `StockLedgerController`, `StockAdjustmentController`, `SyncController` |
| Changed | `TempPurchaseSummaryController.Commit` (was a stub) and new `TempPurchaseReturnSummaryController.Commit` → post to stock. `ItemzRepository` now sets `UDate` on every item/price save (tills sync on it). |

**Rule:** EF DbSets for the stock tables are for **reading only**. All writes go through the
`z_sp_*` procs, because they update ledger + balance in one transaction.

---

## 3. Back office tables (`z_`)

| Table | Purpose |
|---|---|
| `z_tb_StockLedger` | every movement, insert-only. Unique `(TxnType, DocNo, DocLineNo)` → resending a document never double-counts |
| `z_tb_StockBalance` | current qty + weighted `AvgCost` per `(LocationId, ItemId)` |
| `z_tb_StockAdjustment` / `…Item` | adjustment documents `ADJ00000001` |
| `z_tb_StockAdjReason` | reasons drop-down (seeded: Stock count, Damaged, Expired, Lost/Theft, Found, Own use, Opening stock, Other) |
| `z_tb_Terminal` | registered tills (`TerminalId`, `TerminalCode` = invoice prefix `T01`) |
| `z_tb_SalesInvoice` / `…Item` / `z_tb_SalesPayment` | bills uploaded from tills |
| `z_tb_ZReport` / `…Item` | cashier day end: till figures next to server figures (`Srv*`) |
| `z_tb_System.ADJNO` | new counter column for adjustment numbers (next to `PNO`, `PRNO`) |
| `z_tb_ItemPriceLink` | extra retail prices per item + location (§6.5). Delete = `Status 0`; one active link per price |
| `z_tb_StockBatch` / `z_tb_StockBatchMove` | FIFO cost batches: one row per stock-in (price, cost, qty left) / what each ledger row took or put (§6.30) |
| `z_tb_System.StockBatchAt` | when the batches of the location were built; `NULL` = batches off (§6.30) |

`TxnType` (also `Meta.StockTxnType`): **1** GRN (+), **2** PRN (−), **3** Sale (−), **4** Sale refund (+), **5** Adjustment (±), **7** Opening (±).

### Procs
| Proc | Does |
|---|---|
| `z_sp_PostStockMovements` | **the only writer** of ledger + balance. Skips lines already posted. Updates balance with `Qty = Qty + x` (atomic — two tills can't overwrite each other). AvgCost moves on GRN lines only. Calls `z_sp_ApplyStockBatches` |
| `z_sp_ApplyStockBatches` / `z_sp_RebuildStockBatches` | FIFO cost batches + the prices that follow them / build them again from the whole ledger (`@DryRun`) (§6.30) |
| `z_sp_PostGrn` / `z_sp_PostPrn` (→ `z_sp_PostPurchaseDoc`) | post `z_tb_TempPurchase` lines, set summary + lines `Status = 2`. Refuses a second post |
| `z_sp_SaveStockAdjustment` | numbers (`ADJ` + `ADJNO`), saves and posts in one transaction |
| `z_sp_SyncSalesInvoices` | stores a batch of bills from one till + posts sale/refund movements. Duplicates skipped. Re-checks any mismatched Z the late bills belong to |
| `z_sp_SubmitZReport` → `z_sp_ReconcileZReport` | stores the till's Z and compares it with what the server received |
| `z_sp_GetZMissingInvoices` | invoice numbers inside the Z's `FromSeq..ToSeq` that never arrived |
| `z_sp_GetItemsForSync` / `z_sp_GetStockBalanceForSync` / `z_sp_GetPriceLinksForSync` | "changed since" downloads for a till |
| `z_sp_AddPriceLink` / `z_sp_DeletePriceLink` | price links from Item Entry (errors 50041–50045) |

Business errors are `THROW 50001–50099`; the API turns them into **HTTP 400 `{ message }`**.

---

## 4. Till tables (`zf_`)

| Table / proc | Purpose |
|---|---|
| `zf_tb_Config` | one row: TerminalId, TerminalCode, LocationId, API URL, `LastInvoiceSeq`, last sync times (**server** time) |
| `zf_tb_Item`, `zf_tb_StockBalance`, `zf_tb_ItemPriceLink` | downloaded copies (never edited on the till) |
| `zf_tb_Invoice` / `…Item` / `…Payment` | bills, `Synced` flag |
| `zf_tb_ZReport` / `…Item` | Z per shift: 0 open, 1 closed, 2 submitted, 3 reconciled, 4 mismatch |
| `zf_sp_SetupTerminal` | one-time setup |
| `zf_sp_OpenZ` | open Z (called at sign-on; SaveInvoice also opens one if needed) |
| `zf_sp_SaveInvoice` | allocates `T01-00000123`, checks `Amount = Qty*Price − Disc`, payments = net and (sales only) each price (§6.5), saves |
| `zf_sp_VoidInvoice` | only an **unsent** bill in the **open** Z. After upload → do a refund bill |
| `zf_tb_SuspendedBill` / `…Item` | suspended (parked) bills, §6.6. Status 1 suspended, 2 recalled, 9 cancelled |
| `zf_sp_SuspendBill` / `zf_sp_GetSuspendedBills` / `zf_sp_RecallSuspendedBill` / `zf_sp_CancelSuspendedBill` | suspend / list / recall (once only) / cancel |
| `zf_sp_FindItem` | barcode, then RefCode, then scale sticker (§6.14) — or `@ItemId`; 2nd result set = the item's active price links |
| `zf_sp_SearchItems` | cashier search by name: every word in `Descrip` or `Inv_Descrip`, max 50 (needs SQL Server 2016+) |
| `zf_fn_BillLineCost` / `zf_sp_GetBillProfit` | cost + profit per bill line, the discount cap (§6.7) |
| `zf_sp_GetInvoicesByDate` / `zf_sp_GetInvoiceForPrint` | bill copies (§6.7) |
| `zf_sp_GetInvoiceForRefund` / `zf_sp_SaveBillRefund` (`zf_tt_RefundLine`) | refund against the original bill: what is left on each line / save, never more than was sold (§6.16) |
| `zf_tb_DrawerLog` / `zf_sp_LogDrawer` | every cash drawer opening (§6.7) |
| `zf_tb_CashMovement` / `zf_sp_AddCashMovement` / `zf_sp_GetCashSummary` | opening cash, paid in, paid out, expected cash (§6.8) |
| `zf_sp_GetUnsyncedInvoices` / `zf_sp_GetInvoicesByNo` / `zf_sp_MarkInvoicesSynced` | upload queue |
| `zf_sp_CloseZ` / `zf_sp_GetZForSubmit` / `zf_sp_SetZStatus` | day end |
| `zf_sp_GetXReport` | X report: the open Z's totals, read only (§6.8) |
| `zf_sp_UpsertItems` / `zf_sp_UpsertStockBalance` / `zf_sp_UpsertPriceLinks` | apply downloads |

Invoice numbers are made **on the till** (`TerminalCode-8 digits`) so two tills can never clash
while offline — the central `z_tb_System` counters can't be used offline.

---

## 5. API

### Stock (back office)
| Method | Route | Notes |
|---|---|---|
| POST | `api/TempPurchaseSummary/Commit/{grnNo}?userId=` | GRN → stock (+), item cost + price links (§6.1). 400 if not found / already posted / no qty |
| POST | `api/TempPurchaseReturnSummary/Commit/{prnNo}?userId=` | PRN → stock (−) |
| GET | `api/StockLedger/Balance/{itemId}` | one item's stock |
| GET | `api/StockLedger/ItemStock/{itemId}` | Item Entry stock panel: balance, AvgCost, open cost batches (§6.30) + FIFO value, last GRN, last sale, sold last 30 days, last 10 movements |
| POST | `api/StockLedger/SearchBalances` | `{ query, catId, supId, onlyNegative, page, pageSize }` → `{ total, rows }` |
| GET | `api/StockLedger/ItemCard?itemId=&fromDate=&toDate=` | opening, movements with running balance, closing (default last 30 days) |
| GET | `api/StockAdjustment/Reasons` | drop-down |
| POST | `api/StockAdjustment/Save` | see below |
| GET | `api/StockAdjustment/GetByAdjNo/{adjNo}` | header + lines with item names |
| POST | `api/StockAdjustment/Search` | `{ adjNo, fromDate, toDate, reasonId }` |

### Sync (tills + back office)
| Method | Route | Caller | Notes |
|---|---|---|---|
| POST | `api/Sync/Terminal` | back office | register/enable/disable a till `{ terminalId, terminalCode, terminalName, status }` |
| GET | `api/Sync/Terminals` | back office | last upload, open Z count, `isStale` |
| GET | `api/Sync/Items?terminalId=&since=` | till | `{ serverTime, rows }` — store `serverTime`, send it as `since` next time |
| GET | `api/Sync/StockBalances?terminalId=&since=` | till | same pattern |
| GET | `api/Sync/PriceLinks?terminalId=&since=` | till | same pattern; deleted links come with `status 0` |

### Price links (Item Entry)
| Method | Route | Notes |
|---|---|---|
| GET | `api/Itemz/PriceLinks/{itemId}` | active links, lowest price first |
| POST | `api/Itemz/AddPriceLink` | `{ itemId, retailPrice, wholesalePrice?, costPrice?, remark?, userId? }` → `{ message, data }`. 400 on duplicate / normal price / ≤ 0 |
| DELETE | `api/Itemz/PriceLink/{priceLinkId}?userId=` | `Status = 0` |
| POST | `api/Itemz/UpdateRetailPrice` | `{ itemId, retailPrice, userId? }` → changes only `z_tb_ItemDet.RetailPrice` (+ `UDate`, so tills pick it up). 400 when ≤ 0, above the MRP, equal to an active link, or the quantity prices would no longer be below it. Used by the mobile app Price Link page |

`api/Itemz/AddItemDet` and `UpdateItemDet` now refuse bad quantity prices with 400 `{ message }` (§6.5).
| POST | `api/Sync/Invoices` | till | `{ terminalId, invoices:[…] }` → `[{ invoiceNo, result: Inserted/Duplicate }]`. **Empty list = heartbeat** |
| POST | `api/Sync/ZReport` | till | `{ result: { status 3/4, … , mismatchNote }, missingInvoiceNos: [] }` |
| GET | `api/Sync/ZReport/{terminalId}/{zNo}` | back office | Z with per-item till vs server |
| POST | `api/Sync/ZReport/{terminalId}/{zNo}/Reconcile` | back office | check again |
| POST | `api/Sync/ZReports/Search` | back office | `{ fromDate, toDate, terminalId, status }` |

---

## 6. Flows

### 6.1 GRN / PRN
1. Back office enters the GRN/PRN as today (temp tables).
2. **Commit** → `z_sp_PostGrn` / `z_sp_PostPrn` → ledger + balance, `Status = 2`.
   Prices: each GRN line becomes a cost batch at its selling price + cost (§6.30). A selling price other than the
   item's `RetailPrice` is stock at a price link (made when there is none, Remark `From GRN…`). The item's and the
   link's `CostPrice` = the oldest batch left at that price, so a new cost shows only when the older stock is sold.
   (U025 set the item's cost to the GRN cost straight away, also for another price — replaced by U026.)
3. After commit the document is final. To correct it, do a stock adjustment (or a PRN).

### 6.2 Stock adjustment — any time
`POST api/StockAdjustment/Save`
```json
{
  "reasonId": 2, "remark": "Rat damage", "userId": "admin",
  "lines": [
    { "itemId": 12, "adjQty": -3 },                 // quantity mode: remove 3
    { "itemId": 40, "adjQty": 5, "reasonId": 5 },    // quantity mode: add 5, own reason
    { "itemId": 77, "countedQty": 18 }              // count mode: set stock to 18
  ]
}
```
- **Quantity mode** (`adjQty`, ±): safe **any time**, even while tills are offline.
- **Count mode** (`countedQty`): the server works out `countedQty − current balance`.
  ⚠️ If a till still holds unsent bills for that item, they are deducted **again** when they
  arrive → the count ends up too low. So the UI calls `GET api/Sync/Terminals` first and warns
  when any till `isStale` (no upload for 30 min — change `SyncRepository.StaleAfter`). Best
  practice: count after the Z reports are reconciled, or before opening.
- Saved = posted immediately. There is no draft/edit; mistakes are fixed with another adjustment.
- Opening stock for a new system = one adjustment with reason **Opening stock** in count mode.

### 6.3 Selling (till)
1. Bill → `zf_sp_SaveInvoice` (works offline). Price charged is stored, so later price changes
   don't change old bills.
2. Background job every ~1 min: `zf_sp_GetUnsyncedInvoices(50)` → `POST api/Sync/Invoices` →
   `zf_sp_MarkInvoicesSynced` with **every** returned invoiceNo (Inserted *and* Duplicate).
   If nothing is waiting, still POST an empty list (heartbeat → `LastSyncAt`).
3. Every ~5 min: `GET api/Sync/Items?since=LastItemSyncAt` → `zf_sp_UpsertItems(rows, serverTime)`;
   same for price links and stock balances. The cashier's **Reload** button (TillService `POST /sync/now`)
   does all of this immediately and answers how many items / price links changed.
4. **Never block a sale because stock shows 0** — the till's copy may be old. Negative stock shows
   up on the back office balance screen (`onlyNegative`).

### 6.4 Cashier day end (Z)
1. `zf_sp_CloseZ` → totals from local bills.
2. Upload any unsent bills first, then `zf_sp_GetZForSubmit` → `POST api/Sync/ZReport`.
3. Answer:
   - **3 Reconciled** → `zf_sp_SetZStatus(z, 3)`. Done.
   - **4 Mismatch** → `missingInvoiceNos` → `zf_sp_GetInvoicesByNo` → `POST api/Sync/Invoices`
     → submit the Z again. (Late bills also trigger an automatic re-check on the server.)
4. Back office sees all Zs on the Z report screen; a Z stuck on 4 needs a look (`mismatchNote`,
   item diff table).

Reconcile compares: invoice count (incl. voided), line count, net qty, net sales, per-item qty and
amount, and gaps in the invoice sequence. The till (`zf_sp_CloseZ`) and the server
(`z_sp_ReconcileZReport`) must use the **same rules** — change both together.

### 6.5 Prices at the till — quantity prices and price links
A sale line's price is one of:
1. **Open price item** — whatever the cashier types.
2. **Quantity price** (`QtyLevel2..4` / `PriceLevel2..4` on `z_tb_ItemDet`): "buy at least MinQty → pay Price
   each". The level with the **highest MinQty the line's Qty reaches** wins (MinQty and Price both > 0);
   none reached → `RetailPrice`. Applied automatically by the billing page as the quantity changes.
   Item Entry and the API keep levels sane: both values or neither, MinQty > 1 and going up, Price going
   down and below RetailPrice (`ItemzRepository.ValidatePriceLevels`).
3. **Price link** (`z_tb_ItemPriceLink`): an extra retail price for the same item, e.g. old stock at the old
   MRP. When an item has links the cashier must pick the price (normal price or a link) on **every** scan.
   A link price is used for any quantity — no quantity price on top.

4. **Wholesale line** (line `PriceType 2`): price type is **per line**, so a retail bill can have wholesale lines
   and a wholesale bill retail lines (supervisor PIN once per bill). A wholesale line uses the item's
   `WholesalePrice` (> 0), or a price link's `WholesalePrice`, for any quantity; an item without a wholesale
   price falls back to 1–3. Only a line marked `PriceType 2` may carry a wholesale price — a retail line charged
   a wholesale price is refused. The bill's `@PriceType` is only the default for lines that send none; the bill is
   stored as `PriceType 2` when any line is wholesale. Stored on `zf_tb_InvoiceItem.PriceType` /
   `z_tb_SalesInvoiceItem.PriceType` (lines from older tills take the bill's type). The page goes back to retail
   after every bill.

5. **Other item** (`ItemId 0` + `LineDescrip`): an item that is not in the item list. The cashier types the
   name and price (> 0, 51010 otherwise); no price check. Stored on `zf_tb_InvoiceItem` / `z_tb_SalesInvoiceItem`
   with its `LineDescrip`; **no stock movement**. In Z reports all other-item lines of a Z are one group,
   `ItemId 0`, shown as "Other items (not in item list)". `LineDescrip` is the list to add to Item Entry later.

`zf_sp_SaveInvoice` refuses a **sale** line whose price is none of these (51008 "Price of X has changed…",
e.g. a price changed by a sync in the middle of a bill) and lines for items the till doesn't have (51007).
Refunds are not price-checked — they give back what was charged.
The page (Lovable Prompt 8, `quantityPrice()`) and `zf_sp_SaveInvoice` must use the same rule — change both together.
The old system's unit price levels (`tb_PriceLevel`, e.g. cloth by the yard) are **not** carried over.

### 6.6 Suspend / recall a bill (till only)
The cashier can put the bill on the screen aside before payment (customer forgot something, next customer
waiting) and recall it any time later — after other bills, a restart or a day end. TillService routes:
`POST /suspended` (→ `suspendId`), `GET /suspended`, `POST /suspended/{id}/recall`, `DELETE /suspended/{id}`;
`GET /sync/status` returns `suspendedBills`. UI: Lovable Prompt 13.

- A suspended bill is **not an invoice**: no invoice number, no Z, never uploaded, no stock. It lives only in
  that till's `zf_tb_SuspendedBill` / `zf_tb_SuspendedBillItem`. Day end does not touch it.
- Lines keep qty, line discount, `PriceType`, `LineDescrip` (other items) and the picked `PriceLinkId`.
  Prices are not checked on suspend.
- **Recall is once only** (Status 1 → 2, 51032 otherwise), so a bill can't be paid twice. The recall answer
  carries each item as it is **now**; the page re-prices real items (prices may have changed while suspended)
  and drops items that are gone, inactive or sale-locked. Paying it then goes through `zf_sp_SaveInvoice` and
  its price check like any other bill.
- Cancel = Status 9. Rows are never deleted (audit: `ClosedAt`, `ClosedBy`).

### 6.7 Receipts, bill copies, cash drawer, profit view, bill discount % (till only, 2026-10-06)
All in TillService + the till db; UI: Lovable Prompts 14 and 15.

**Printing** — TillService prints ESC/POS straight to the thermal printer (`Printer:Name` = Windows printer name,
or `Printer:Address` = `ip:9100`). No BarTender on tills. Shop name / address / footer come from
`receipt-template.txt` next to `TillService.exe` (tags `<C> <R> <B> <H> <2>`, read on every print). The rest of the
layout (ItemCode · MktPrice · OurPrice · Qty · Nett, totals, CASH / BALANCE, items / pcs, YOUR SAVINGS) is
`Printing/ReceiptBuilder.cs`. Names print in English (`Inv_Descrip`), since receipt printers can't print Sinhala text.
- `POST /invoices` saves → prints → opens the drawer when any payment is cash (`PayType 1`, also cash refunds);
  card / credit / voucher only → no drawer. Answer `{ invoiceNo, printed, drawerOpened, printError }`. **A print
  problem never undoes the sale** — the page shows `printError` and offers a reprint.
- Cash `Tendered` is now stored per payment (`zf_tb_InvoicePayment.Tendered`) so the receipt and copies show
  CASH and BALANCE. `MktPrice` = the item's `MaxPrice` at the time of sale (`zf_tb_InvoiceItem.MktPrice`).
- **Day file**: `Receipt:SaveFolder\yyyy-MM-dd.txt`, one per day: every bill as printed, copies, No Sale, and
  `[time] Uploaded to back office: …` lines from the sync job. It is a journal only — the bills live in the db.

**Bill copy** — `GET /invoices?date=` (bills of a day on this till), `GET /invoices/{no}`, `POST /invoices/{no}/print`
prints `***** COPY RECEIPT *****` + "Copy Taken" date/time. No PIN, never opens the drawer. Only bills of **this**
till (they live in its db).

**Reprint last bill** (2026-10-12) — `POST /invoices/last/print`: one key, no dialog. Prints a COPY RECEIPT of the
newest bill on this till (highest `InvoiceSeq`, sale or refund, any cashier) → `{ invoiceNo, printed, printError }`;
400 when the till has no bill yet. TillService only — **no database change**, no update script. UI: Lovable Prompt 36.

**Price check** (2026-10-12) — scan or search an item to see its prices and stock without touching the bill. The page
uses the existing `GET /items/find`, `/items/search` and `/items/{id}` (prices, quantity prices, price links,
`stockQty`); `GET /sync/status` now also gives `lastStockSyncAt` (how old that stock is). Cost only with the
supervisor PIN: `GET /items/{id}/cost` (`X-Supervisor-Token`, 401 without) → `{ itemId, costPrice, priceLinks:
[{ priceLinkId, costPrice }] }`, 0 / no cost = null, a link without its own cost shows the item's (same rule as the
profit view). TillService only — **no database change**, no update script. UI: Lovable Prompt 37.

**Cash drawer** — kick command `ESC p` through the printer (`Printer:DrawerPin` 0 = pin 2). Every opening is a row in
`zf_tb_DrawerLog` (Kind 1 bill, 2 No Sale; `Opened 0` = the printer didn't take it). **No Sale**:
`POST /drawer/nosale { cashierId, reason }` — **no PIN** (a `pin` sent is ignored); the cashier and reason are logged
and the drawer opens with no slip (2026-10-25; `Receipt:PrintNoSaleSlip` true = print a small NO SALE slip).

**Till reports (Menu)** — `POST /cash/summary/print` (DRAWER SUMMARY slip of the open Z), `GET|POST /reports/suspended[/print]`
(waiting + today's recalled / cancelled), `GET|POST /reports/refunds[/print]?zNo=` (refund bills of the open Z, else the
last one). Day end always prints the CASH IN / OUT slip (opening cash, paid in, paid out) before the Z slip.
`Receipt:PrintCashInDrawer` false = no CASH IN DRAWER on Z / X / drawer summary slips; the billing page shows it only
after the supervisor PIN.

**Profit view and bill discount %**
- Cost prices now go to the tills: `z_sp_GetItemsForSync` → `CostPrice` (= `z_tb_ItemDet.CostPrice`),
  `z_sp_GetPriceLinksForSync` → link `CostPrice`. The till re-downloads all items and links once after the upgrade.
- Cost is **never** sent to the page without the supervisor PIN: `POST /auth/supervisor` now also returns a
  `token` (12 h, `Till:SupervisorTokenHours`, in memory only); the page sends it as `X-Supervisor-Token`.
  `DELETE /auth/supervisor` locks again.
- `POST /bill/profit { items }` (token) → per line `unitCost / cost / profit`, bill `profit`, `maxDiscount`,
  `maxDiscountPercent`, `discountBase`. Rule = `zf_fn_BillLineCost` (one place, used by the save too):
  unit cost = the picked price link's cost, else the item's cost; profit = Amount − Qty × cost. **Other items and
  items without a cost count as 0 profit**, so they never allow a bigger discount. Lines now send `priceLinkId`.
- **Bill discount** needs the token (401 otherwise) and on a sale may not be more than the bill profit
  (51012 "Discount is more than this bill allows (max Rs x)"). As a %: send `discountPercent` and
  `discount = ROUND(base × % / 100, 2)`, base = all lines except `NoDiscount` items (51014 when it doesn't match).
  The % is printed (`DISCOUNT 10%`) and kept on suspend / recall. `UnitCost` is stored per line for profit reports.
  Refunds are not capped.
- `DiscountPercent`, `UnitCost`, `Tendered` and the drawer log stay on the till (not uploaded yet).

### 6.8 Opening cash, Paid In, Paid Out (till only, 2026-10-06)
Cash put into / taken out of the drawer without a sale, per Z, in `zf_tb_CashMovement` (Kind **1** opening cash,
**2** paid in, **3** paid out). UI: Lovable Prompt 16.
- `POST /cash/movements { kind, amount, reason, cashierId, pin }` → saves (`zf_sp_AddCashMovement`), opens the drawer,
  prints a slip (paid out has a signature line), day file, `zf_tb_DrawerLog` Kind 3/4/5.
  **Opening cash and paid out need the supervisor PIN every time**; paid in does not. Paid out needs a reason (51053)
  and can't be more than the cash in the drawer (51054).
- **Opening cash** = the float handed to the till before it opens. Entering it opens a Z if none is open, so it can be
  entered before the first bill. One per Z: typed again **before the Z's first bill** it replaces the old one
  (old row Status 9); once the Z has bills and an opening cash, 51051 — use Paid In / Paid Out. A forgotten float can
  still be entered once after bills.
- `GET /cash/summary` → open Z's `openingCash, hasOpeningCash, cashSales, paidIn, paidOut, expectedCash` + movements.
  `zNo null` or `hasOpeningCash false` → the page asks for the opening cash.
- **Day end**: `zf_sp_CloseZ` stores `OpeningCash, PaidIn, PaidOut, ExpectedCash` (= opening + `CashAmount` + paid in
  − paid out) on `zf_tb_ZReport`, and `POST /z/close` returns them and prints a Z slip (`Receipt:PrintZReport`) with
  "CASH IN DRAWER" and lines for the counted amount and a signature. The opening cash belongs to that Z only — the next
  Z starts at 0 until a new opening cash is entered.
- **Cash in / out list at day end** (2026-10-12): when the Z has any paid in or paid out, `POST /z/close` prints a
  "CASH IN / OUT" slip **before** the Z slip — each movement (time, number, cashier, amount, reason) and the totals,
  which are the Z slip's "+ Paid in" / "− Paid out". Opening cash is not listed (it is on the Z slip). No movements →
  only the Z slip. Follows `Receipt:PrintZReport`; day file either way. If the list fails to print the Z slip still
  prints and `printError` says so. TillService only — no database change, no page change.
- Uploaded to the back office since 2026-10-25 (U018, §6.25 Day Reports); the Z upload is unchanged (`CashAmount`
  still means cash sales only).
- **X report** (2026-10-12) — a reading in the middle of the shift, nothing is closed. `zf_sp_GetXReport` works out the
  open Z's totals with the **same rules as `zf_sp_CloseZ`** (change both together) but writes nothing; `GET /x` returns
  them in the `/z/close` shape (`closedAt` null, `status` 0), `POST /x/print` also prints an "X REPORT — Z n NOT
  CLOSED" slip (always, whatever `Receipt:PrintZReport` says; day file too). No PIN, no drawer, any number of times;
  400 when no Z is open. Not sent to the back office. Till db update: `Updates/U002_Till_XReport.sql`.
  UI: Lovable Prompt 38.

### 6.9 Sales dashboard — today live + date range analysis (back office, 2026-10-06)
UI: Lovable Prompts 17 (home page) and 18 (sales analysis). SQL: `04_BackOffice_SalesDashboard.sql`.

**Live flow**: till bill paid → TillService uploads it at once (`Sync:PushEachBill`, default true; false = every
30 s) → `POST api/Sync/Invoices` stores it → if any bill was new and `Dashboard:LivePush` is true, ItemApi sends
SignalR **`salesChanged`** `{ terminalId, newBills, at }` on **`/hubs/sales`** → open home pages reload
`GET api/Dashboard/Today`. Measured: under 1 s from Pay to the push. A till that is offline sends its bills when it
reconnects (the push comes then). With auto update off, or the hub not connected, the page has a Refresh button.

**API**
| Method | Route | Notes |
|---|---|---|
| GET | `api/Dashboard/Today?terminalId=` | server date: `totals`, `terminals` (each till: bills, sales, profit, `lastBillAt`, `isOnline` = heard from in 2 min), `hourly` (24 rows), `topItems` (10), `livePush` |
| GET | `api/Dashboard/Sales?fromDate=&toDate=&terminalId=&top=20` | max 366 days: `totals`, `daily` (every day, gaps = 0), `terminals`, `hourly`, `topItems` (by sales), `topProfitItems`, `categories` |

**Numbers** (one rule, `z_fn_SalesLines`): voided bills left out, refunds negative; a line's net = its amount less
its share of the bill discount; unit cost = the **till's cost** (`z_tb_SalesInvoiceItem.TillUnitCost`, uploaded now
by tills) → else AvgCost at upload (`CostPrice`) → else the item's cost now; profit = net − qty × cost, **only for
lines with a known cost**. Sales without a cost (other items, items with no cost) are `uncostedSales`, not in profit
or margin. `marginPct` = profit / `costedSales`. Bills from before this change have no till cost, so their profit
uses AvgCost and can differ from what the till showed.

**Deploy order**: `01` + `04` on easyway → ItemApi (its TVP has the new `UnitCost` column, so an old ItemApi fails
uploads against the new `01` until restarted — tills just retry) → each till: `02` **then** the new TillService (it
reads `UnitCost` from `zf_sp_GetInvoicesByNo`; an old `02` stops its uploads).

---

### 6.10 Exports to a folder — weighing scale item file (back office, 2026-10-08)
UI: Lovable Prompt 20 (common "Exports" page). SQL: `05_BackOffice_Export.sql`. Code: `ExportController`,
`ExportRepository`. The file is written **only when someone presses Export** (not when an item is saved).

**Scale file** (`SCALE`, default `ScaleItem.txt`): one line per item, CRLF, no header, UTF-8 without BOM (plain ASCII
for English names) — `PLU#Description#Price#`, e.g. `10001#Cashew Nut 1kg#6200.00#`.
- Scale item = active item (`Status 1`) whose unit at the location is **KGS** (`z_tb_ItemDet.UnitId` → `z_tb_Unit.UnitCode`).
- PLU = **RefCode**, digits only, padded to 5 (`5` → `00005`). Price = `RetailPrice` (per kg), 2 decimals.
  Name = `Descrip` with `#` and line breaks replaced by a space, cut to `NameMaxLength` (default 30, 0 = no limit).
- Left out, with the reason shown on the page: no / non-numeric / longer than 5 digits RefCode, no description,
  price ≤ 0, sale locked, and **both** items when two have the same PLU (the scale finds items by PLU).
- Lines sorted by PLU. The file is **overwritten in place** (locked while written, flushed, closed, time set to now) —
  the same as saving a downloaded copy over it — so the scale program sees it **modified** and reloads it (2026-10-29;
  before, a `<file>.tmp` renamed over it was not seen as a change by the scale). In use by the scale → tried again ~5 s.

**Folder** = a folder the **API server** can see (local drive or `\\SCALE-PC\Import`). For a share, the IIS app pool /
service account needs write access. Saving the settings checks that the folder exists.

**Changed since last export**: `z_tb_ScaleExportItem` holds what the last successful export sent; the preview marks
each line `new` / `changed` (code, price or name) / `same`, and lists `removed` items (sent last time, not now).
Download sends the same file to the browser but does **not** count as an export.

**API**
| Method | Route | Notes |
|---|---|---|
| GET | `api/Export` | every export: folder, file name, `nameMaxLength`, last export (time, user, lines) |
| GET | `api/Export/{code}` | one |
| PUT | `api/Export/{code}` | `{ folderPath, fileName, nameMaxLength, userId }` → `{ message, data }`; 400 bad / missing folder |
| GET | `api/Export/SCALE/Preview` | `{ setting, filePath, lines[], skipped[], removed[], newCount, changedCount, hasChanges }` |
| POST | `api/Export/SCALE/Run` | `{ userId }` → `{ message, data: { filePath, lineCount, skippedCount, newCount, changedCount, removedCount, exportedAt } }`; 400 folder not set / not found / no write access (logged as failed) |
| GET | `api/Export/SCALE/Download` | the file as an attachment |
| GET | `api/Export/{code}/Log?top=20` | `z_tb_ExportLog`: status 1 written / 9 failed + error |

To add another export: a row in `z_tb_ExportSetting` and a branch in `ExportController` / `ExportRepository`.

---

### 6.11 Quotations and invoices — A4 PDF (back office, 2026-10-08)
UI: Lovable Prompts 21 (customers + document settings) and 22 (quotations & invoices). SQL: `06_BackOffice_SalesDoc.sql`.
Code: `CustomerController`, `SalesDocController`, `SalesDocRepository`, `Service/SalesDocPdfService.cs` (QuestPDF).

**Document only**: no stock movement, no customer balance, no tax. (Till bills are `z_tb_SalesInvoice`, a separate thing.)
- Numbers: `QT000001…` and `INV000001…` from `z_tb_SalesDocCounter` (row locked in the save transaction; never reused).
- **Quotation**: editable while open. Valid until = date + `QuotationValidDays` unless given. **Make invoice** copies it
  into a new invoice (`FromDocId`) and marks it **invoiced** — once.
- **Invoice**: editable while open (customer, dates, lines, discount, notes); the number and the quotation link stay.
  Cancel needs a reason. Cancelling an invoice that came from a quotation sets the quotation back to **open**, so it can
  be invoiced again. An invoiced quotation can't be edited or cancelled — change (or cancel) its invoice instead.
  Cancelled documents can't be edited.
- Customer: pick from `z_tb_Customer` (name, address, phone, email — kept simple) **or** type a one-off name. The name,
  address and phone are **copied onto the document**, so editing / deleting a customer never changes old documents.
- Lines: `itemId` (its description is filled in when left blank) or `itemId 0` + typed description (service, transport…).
  Qty > 0 (3 decimals), price ≥ 0, line discount 0…qty×price; amount = qty × price − discount. Document discount
  0…sub total. Max 200 lines. Prices are whatever is typed — the UI fills them from the item.
- PDF: company name / address / phone / email / logo and terms from `z_tb_SalesDocSetting` (logo file in `Uploads/`).
  Cancelled documents print a red CANCELLED box with the reason. QuestPDF Community licence (free under USD 1M revenue).

**API**
| Method | Route | Notes |
|---|---|---|
| GET | `api/Customer?text=&top=50` | active customers by name (text = name or phone) |
| GET / POST / PUT / DELETE | `api/Customer[/{id}]` | `{ name, address, phone, email, userId }`; duplicate name → 400; delete = Status 0 |
| POST | `api/SalesDoc/Search` | `{ docType, fromDate, toDate, customerId, text, status, page, pageSize }` → `{ total, rows }` (rows carry `fromDocNo` / `invoiceDocNo`) |
| GET | `api/SalesDoc/{id}` | `{ doc (with items), fromDocNo, invoiceDocId, invoiceDocNo }` |
| POST | `api/SalesDoc` | `{ docType, docDate, validUntil, customerId | custName+custAddress+custPhone, reference, notes, discount, userId, items:[{ itemId, descrip, qty, unitPrice, discount }] }` |
| PUT | `api/SalesDoc/{id}` | open quotations and invoices (same body; `docType` ignored) |
| POST | `api/SalesDoc/{id}/Cancel` | `{ reason, userId }` |
| POST | `api/SalesDoc/{id}/ToInvoice` | `{ docDate, userId }` → the new invoice |
| GET | `api/SalesDoc/{id}/Pdf?download=false` | A4 PDF, inline (view / print) or as a download |
| GET / PUT | `api/SalesDoc/Settings` | `{ companyName, companyAddress, companyPhone, companyEmail, quotationValidDays, quotationTerms, invoiceTerms, userId }` |
| GET / POST / DELETE | `api/SalesDoc/Settings/Logo` | multipart `file` (PNG/JPG ≤ 2 MB) |

Note: easyway is at compatibility level 100, so EF's `list.Contains(...)` (translated to `OPENJSON`) fails there —
`SalesDocRepository` looks items up one by one for that reason.

---

### 6.12 Sign-in — back office users and till cashiers (2026-10-09)
UI: Lovable Prompts 23 (back office sign-in + Users page) and 24 (till sign-in). SQL: `07_BackOffice_Users.sql` + the
"Cashier sign-in" section of `02`. Code: `AuthController`, `UsersController`, `UserRepository`, `Service/AuthTokenService.cs`,
`Common/PasswordHasher.cs`; TillService `Auth/CashierSessions.cs`, `POST /auth/cashier`.

**One user list** (`z_tb_User`), kept in the back office. Role decides where the user can sign in:
| Role | Back office | Till | Users page |
|---|---|---|---|
| 1 Admin | ✓ | ✓ | ✓ |
| 2 Back office | ✓ | — | — |
| 3 Cashier | — | ✓ | — |

- User name (`LoginName`): 3–20 letters / digits / `. _ -`, any case, **never changes** (it is the `CashierId` on till
  bills). Users are never deleted — disabled (`Status 0`). There is always one active admin (can't disable / demote the
  last one or yourself).
- Password: 6+ characters for Admin / Back office, 4+ for cashiers. Stored as PBKDF2-SHA256 (100 000 rounds, salted);
  SQL never sees a password. 5 wrong passwords → locked 5 minutes (an admin's password reset unlocks).
- **First admin**: on a new system `GET api/Auth/Status` says `setupNeeded`; the sign-in page then offers
  `POST api/Auth/Setup` (only while there is no active admin).

**Back office** — `POST api/Auth/Login` → JWT (`Auth:TokenHours`, 12), sent as `Authorization: Bearer`. Every request
re-checks the user: disabled, or role changed → 401 at once. `Auth:Enforce`:
- `false` (default, while the web pages are switched over): routes stay open, `api/Users` is admin-only anyway.
- `true`: every route needs an Admin / Back office token except sign-in (`api/Auth/Status|Setup|Login`), the till sync
  routes (`api/Sync/Items|StockBalances|PriceLinks|Invoices|ZReport` POST|`Cashiers`) and the PDF logo. The live sales hub
  takes the token as `?access_token=` (SignalR). PDFs must be fetched with the header (blob), not opened as a bare URL.
- `Auth:JwtKey`: set 32+ random characters **on the server** (not in git). Empty = a new key each start (restart signs
  everyone out).
- The request log (`logs/`) never writes the body of `api/Auth/*` / `api/Users/*` or the hub query string.

**Tills** — `GET api/Sync/Cashiers?terminalId=&since=` (header `X-Terminal-Key` = `Sync:TerminalKey`, same value in
each TillService) sends every user changed since `since`; Admin / Cashier users that are active come with
`canUseTill true` and their hash, the rest with no hash. TillService stores them in `zf_tb_Cashier` with the other
downloads (5 min / Reload) and signs out anyone who lost access. `POST /auth/cashier` checks the password **on the
till** — sign-in works offline. With `Till:RequireSignIn` the till refuses billing routes without `X-Cashier-Token`, and
the `CashierId` it stores is always the signed-in cashier's.

**Supervisor PIN** (2026-10-29, U028) — set per user on the Users page:
- **Cashier admin**: an Admin or Cashier user with a supervisor PIN (`z_tb_User.TillPinHash`, 4–8 digits, PBKDF2 like
  the password; given when the user is made, or with the shield button). It comes down with the cashiers
  (`zf_tb_Cashier.PinHash`, active till users only) and approves at **every till**: every PIN prompt (refund, bill
  discount, wholesale, profit view, price check cost, throw a bill away, opening cash / paid out, printer and card
  machine settings ...) is checked by TillService against the PINs of the cashier admins. `Till:SupervisorPin` in
  appsettings is used only while no user on that till has a PIN.
- **Ask the supervisor PIN** (`z_tb_User.TillAskPin`, on by default): off = while that user is signed in the till
  asks no PIN at all — TillService lets every approval through and the billing page skips the PIN dialog.
- Changes reach the tills with the cashier download (≤ 5 min / Reload); "Ask the PIN" applies to a cashier already
  signed in from their next request.

**API**
| Method | Route | Notes |
|---|---|---|
| GET | `api/Auth/Status` | `{ setupNeeded, enforced }` |
| POST | `api/Auth/Setup` | `{ loginName, userName, password }` → `{ token, expiresAt, user }`; 400 once an admin exists |
| POST | `api/Auth/Login` | `{ loginName, password }` → `{ token, expiresAt, user: { userId, loginName, userName, roleId, roleName, ... } }`; 401 `{ message }` |
| GET | `api/Auth/Me` | the signed-in user (401 → sign in again) |
| POST | `api/Auth/ChangePassword` | `{ currentPassword, newPassword }` |
| GET | `api/Users?text=&includeDisabled=` | admin only |
| POST | `api/Users` | `{ loginName, userName, roleId, password, phone, email, pin, askPin }` |
| PUT | `api/Users/{id}` | `{ userName, roleId, status, phone, email, askPin }` (user name can't change; askPin left out = unchanged) |
| POST | `api/Users/{id}/ResetPassword` | `{ newPassword }` — also unlocks |
| POST | `api/Users/{id}/Pin` | `{ pin }` — supervisor PIN at the till (4–8 digits, Admin / Cashier); empty = removed |
| GET | `api/Sync/Cashiers?terminalId=&since=` | tills, `X-Terminal-Key` |

**Turning it on** (in this order): run `07` (+ `02` on each till) → deploy ItemApi with `Auth:JwtKey` and
`Sync:TerminalKey` → paste Lovable Prompt 23, open the web app, create the first admin, add users → set
`Auth:Enforce: true` and restart ItemApi → each till: new TillService with the same `Sync:TerminalKey`, press Reload
(cashiers come down) → paste Prompt 24 → `Till:RequireSignIn: true`, restart TillService.

---

### 6.13 Old item master → new (2026-10-09)
`08_Transfer_OldItems.sql` → `EXEC dbo.z_sp_TransferOldItems @DryRun = 1` (report only, rolled back), then `@DryRun = 0`.
The full mapping is in the script header. In short:
- **RefCode** = old `Ref_Code` when filled (the 5-digit **scale code**, 194 items — 175 KGS + 19 others), else old
  `Item_Code`. So the scale export (§6.10) works, and cashiers type a scale item's scale code at the till.
- **Retail price** = `ERet_Price` (what the old tills charged); `PRet_Price` is ignored. Wholesale / cost / average
  cost / sale lock / reorder / unit (by code) copied. Quantity prices copied only when they pass the Item Entry rules.
- **Not linked**: category, sub-category, supplier (left NULL by choice). Every item's old codes — item code, ref code,
  category, sub-category, supplier, unit — are in **`z_tb_ItemOldCode`** (`OldItemCode` → `ItemId`), so links can be
  added later without the old tables.
- **Not copied**: stock (load an opening adjustment), sales history.
- **Price links** (2026-10-13, `Updates/U005_BackOffice_TransferPriceLinks.sql`): `EXEC dbo.z_sp_TransferOldPriceLinks
  @DryRun = 1` (then `0`) copies the **active** `tb_PriceLink` rows (Status `1`; `0` deleted and `3` closed by a
  purchase are left) to `z_tb_ItemPriceLink` through `z_tb_ItemOldCode`: `Price` → `RetailPrice`, `EWholePrice`,
  `CostPrice` (0 → NULL). Skipped and listed: item not copied, a price that is not a price (a barcode typed in), the
  item's own retail price, the same price twice, a link that is already there (so a second run adds nothing).
  Every run also deletes (Status 0 + new `UDate`, so the tills drop them) the price links whose item is no longer
  in `z_tb_Item`.
- Re-run: already copied items are left alone; `@UpdateExisting = 1` refreshes them from the old tables (overwrites
  edits made in the new system).

Run on easyway 2026-10-09: 5 419 copied, 0 skipped; checked retail and cost prices of every item against the old
tables (0 differences). Units LTR / PKT are not in `z_tb_Unit`, so 6 items have no unit. Old item 3256325 (SERA PEPPER
POWDER) has a code that is also the barcode of 4555655957 (CHAMINDA NOODLES) — typing 3256325 at the till finds the
noodles; scan its own barcode instead.

### 6.14 Scale sticker barcodes at the till (2026-10-12)
The weighing scale prints a 10-digit barcode: **5 digits scale code + 5 digits weight in grams**.
`1000801410` = RefCode `10008`, 1.410 kg → the bill line is qty 1.410 × the item's price (190.00 → 267.90, the
sticker's total). The price always comes from the till's item, never from the sticker.

- `zf_sp_FindItem`: barcode, then RefCode exactly as before. Only when nothing matches and the code is 10 digits it is
  read as a sticker: the item must be a **scale item (unit KGS)**, active, with a RefCode of digits only, up to 5
  (padded with leading zeros like the PLU in the scale export, §6.10). The item comes back with `ScaleQty` (kg).
  Weight `00000`, a non-KGS item or an unknown scale code = not found.
- The till knows the unit now: `z_sp_GetItemsForSync` sends `UnitCode` → `zf_tb_Item.UnitCode`. Adding the column
  clears `LastItemSyncAt`, so the till downloads every item again on its next sync.
- Typing the 5-digit scale code alone still works as before (qty 1, or `1.25*10008`).
- TillService `/items/find` returns `unitCode` and `scaleQty`; the page uses `scaleQty` as the line quantity
  (Lovable Prompt 33). Until the page is changed a sticker scan adds the item with qty 1.

**Deploy order**: `01` on easyway → ItemApi → each till: `02` **then** the new TillService (an old TillService can't
download items against the new `02` — its item table has no `UnitCode` column) → press Reload → paste Prompt 33.

### 6.15 Bank transfer and cheque payments (2026-10-12)
Two more payment types: **5 bank transfer**, **6 cheque**. UI: Lovable Prompts 39 (till) and 40 (Tills & Z Reports).
SQL: `Updates/U003_BackOffice_PayTypes.sql`, `Updates/U003_Till_PayTypes.sql` (and the full scripts `01`, `02`).

- **Bills need no table change**: `PayType` was always a plain INT on `zf_tb_InvoicePayment` / `z_tb_SalesPayment`, and
  the upload carries it. `RefNo` (30) = cheque number (**required**, checked by TillService) or the transfer
  reference (optional). `POST /invoices` now refuses a `payType` outside 1–6.
- **Z split**: `zf_tb_ZReport` and `z_tb_ZReport` get `BankAmount` and `ChequeAmount`. **Both are part of
  `OtherAmount`**, which keeps its meaning (everything that is not cash or card) — so old and new tills / Zs add up
  the same way and nothing in the reconcile changes (payment types are not compared). "Credit / voucher" on a slip or
  screen = `OtherAmount − BankAmount − ChequeAmount`. NULL = not split (Z from before, or an old TillService).
  `zf_sp_CloseZ` fills them, `zf_sp_GetXReport` returns them, `zf_sp_GetZForSubmit` → `POST api/Sync/ZReport`
  (`bankAmount`, `chequeAmount`, optional) → `z_sp_SubmitZReport @BankAmount, @ChequeAmount`.
- **Receipt**: `BANK TRANSFER <ref>` / `CHEQUE <no>`. **Z and X slips**: lines "Bank transfer" and "Cheque" (when not 0)
  between Card and "Credit / voucher".
- **Drawer and cash**: neither opens the drawer nor counts as drawer cash (`ExpectedCash` is cash only).
- **Dashboards** (§6.9) still show Cash / Card / Other; Other includes both. Not split there yet.
- **Mixing versions**: new TillService on a till db without U003 → bills save, the Z closes, but the split is 0
  (`GetIfThere`); old TillService on an updated till db works; a new till talking to an old ItemApi → the back office
  keeps only "Other". The new ItemApi **needs** U003 on easyway first (the Z list reads the new columns).

**Deploy order**: `U003_BackOffice` on easyway → ItemApi → each till: `U003_Till` → new TillService → Prompts 39, 40.

### 6.16 Refund against the original bill + bill number barcode (till only, 2026-10-13)
The customer brings the receipt back; the cashier scans the barcode under it, picks the lines and the quantities, and
the till gives back exactly what was paid for them. UI: Lovable Prompt 45. SQL: `Updates/U004_Till_RefundBill.sql`
(and the full script `02`). **No back office change, no ItemApi change.**

- **Barcode on the receipt**: every sale bill ends with its number (`T01-00000351`) as a CODE128 barcode — bars only,
  no text (the number is already printed at the top), `Receipt:BillBarcodeHeight` dots high (default 40 = 5 mm of
  paper, 0 = none; raise it if the scanner struggles). Not on refund bills or voided bills. Copies have it too.
  Needs only the new TillService. Bills printed before it have no barcode — type the number from the top of the bill.
- **Lookup** `GET /invoices/{no}/refund` → `zf_sp_GetInvoiceForRefund`: the sale bill with, per line, `qty`,
  `refundedQty`, `leftQty`; `canRefund` false + `reason` for a refund bill, a voided bill or a bill with nothing left.
- **Save** `POST /refunds { refInvoiceNo, lines: [{ refLineNum, qty }], payType, refNo }` → `zf_sp_SaveBillRefund`.
  The page sends only which lines and how much; **price, discounts and amount come from the sale bill**:
  - a line can never give back more than `sold − already refunded` (the sale bill row is locked while the refund is
    saved, so two refunds can't both pass). **No PIN lifts this.**
  - line discount: in proportion to the quantity; the last part of a line takes what is left of it.
  - the sale's bill discount: in proportion to the refunded line amounts; the refund that brings back the last of
    the bill takes what is left — the refunds of a bill add up to its net amount. (A kg line refunded in several
    parts can differ by a cent: each part is `ROUND(qty × price, 2)`.)
  - the whole amount goes back one way (`payType` 1–6; a cheque needs `refNo`). Cash opens the drawer.
  - needs the **supervisor token** (`X-Supervisor-Token`) every time → 401 without it.
  `POST /refunds/check` (same body, no token) returns the same amounts without saving — the screen shows them first.
- **What is stored**: a normal refund bill (`InvType 2`, own number, open Z, uploaded like any bill — the back office
  puts the stock back as it always did for refunds) made by `zf_sp_SaveInvoice`, plus `zf_tb_Invoice.RefInvoiceNo` and
  `zf_tb_InvoiceItem.RefLineNum`. `UnitCost` / `MktPrice` are copied from the sale line, so the profit taken back is
  the profit that was made. The refund receipt prints `REFUND OF BILL : T01-00000351`.
- **Only on the till that made the bill** (the till has no other till's bills): another till answers
  "Bill not found on this till." The back office is not told which bill a refund belongs to (`RefInvoiceNo` is not
  uploaded yet) — both would need the back office (see §8).
- **Refund mode without a bill** (`POST /invoices` with `invType 2`) still exists for a customer without a receipt:
  it has no "more than sold" check, because there is no bill to check against.
- **Mixing versions**: new TillService on a till db without U004 → selling, bill copies and the barcode work; the
  refund routes answer 400 "This till's database needs an update…". Old TillService on an updated db works.

**Deploy order**: each till: `U004_Till` → new TillService → Prompt 45.

### 6.17 Customer display on a second screen (till page only, 2026-10-14)
A second Chrome window, `/customer-display`, on the screen facing the customer: the last item scanned, the bill list,
the total, and after payment "Thank you" with the cash given and the change. UI: Lovable Prompt 48.
- **No backend change**: no TillService, no db, no update script. The billing page sends the bill to the display
  window with a browser `BroadcastChannel` (same Chrome, same PC), so it works offline. Nothing secret is sent (no cost,
  profit or PIN).
- Opening: `Ctrl+Shift+D` or the monitor icon in the till's status strip; optional auto-open on start (needs pop-ups
  allowed for the till site). Chrome's window management permission (asked once) puts it on the second screen.
- Windows must be set to **Extend these displays**. Both windows must be in the same Chrome profile (two `--kiosk`
  windows with different `--user-data-dir` would not see each other).

### 6.18 Stock take — count sheets, counts, post the difference (back office, 2026-10-14)
UI: Lovable Prompt 49. SQL: `Updates/U006_BackOffice_StockTake.sql` (full script `14_BackOffice_StockTake.sql`).
Code: `StockTakeController`, `StockTakeRepository`, `Data/AppDbContext.StockTake.cs`, `Models/StockTake.cs`.

1. **Create** (`ST00000001`) with a filter (category / sub category / supplier, items with stock only or every active
   item). `FreezeAt` = now: the count is "as at" this moment. One sheet per category, a new one every
   `itemsPerSheet` (default 50). Items already in another stock take that is still counting are left out (`skipped`).
2. **Count**: print the sheets (blind — no system qty unless `showSystemQty=true`), type the counts per sheet, mark it
   done. Extra sheets ("Store room") and items found on the shelf but not on a sheet can be added; an item on two
   sheets counts as the **sum** of both. A count can be cleared (null) and changed until the post.
3. **Variance**: per item counted vs **system qty as at `FreezeAt`** = `SUM(z_tb_StockLedger.Qty WHERE TxnDate <=
   FreezeAt)`, the difference and its value at AvgCost (cost when the line was made). Totals: short, excess, net.
4. **Post**: one stock adjustment through `z_sp_SaveStockAdjustment` (quantity mode, reason 1 "Stock count",
   `AdjDate = FreezeAt`, remark "Stock take ST… counted …", each line's remark = the ST number). Only items with a
   difference are posted; no difference at all → posted with no adjustment (`adjNo` null). Items nobody counted are
   **left alone**, unless `uncountedAsZero` (then they are counted as 0 — the item is gone).
   After the post the variance is read from the adjustment, so it never changes again. Cancel = Status 9, nothing posted.

Why "as at `FreezeAt`" and not the balance at post time: the shop keeps selling while people count. A sale after the
count is in the balance but was still on the shelf when counted → it must not be "found" again; a till bill from
**before** the count that uploads late is in the ledger by its till time → it is allowed for at post time. So the
count can take hours and the tills can be offline, as long as they have uploaded before the **post** (the UI warns
about stale tills, like count-mode adjustments, §6.2).
- Not covered: a GRN posted with a `PDate` before `FreezeAt` for goods that arrived **after** the count (GRN lines use
  the GRN date, often midnight). Don't receive goods into the counted area during the count, or date that GRN later.
- Values use the cost when the line was made; the posted adjustment uses AvgCost at post time (`TotalAdjValue`).

| Method | Route | Notes |
|---|---|---|
| POST | `api/StockTake/Create` | `{ title, catId, subCatId, supId, includeZeroStock, itemsPerSheet, userId }` → `{ message, data }` (header + sheets) |
| POST | `api/StockTake/Search` | `{ fromDate, toDate, status, stockTakeNo }` → list with `itemCount, countedItems, sheetCount, sheetsDone` |
| GET | `api/StockTake/{id}` | header + sheets (`lineCount`, `countedLines`, `status` 1 open / 2 done) |
| GET | `api/StockTake/{id}/Sheet/{sheetId}?showSystemQty=` | `{ header, sheet, lines }` for entering / printing |
| POST | `api/StockTake/{id}/Sheet` | `{ sheetName, countedBy }` → new empty sheet |
| POST | `api/StockTake/{id}/Sheet/{sheetId}/AddItem` | `{ itemId }` or `{ code }` (barcode, then item code) → the new line |
| POST | `api/StockTake/{id}/Sheet/{sheetId}/Counts` | `{ counts: [{ itemId, countedQty, remark }], countedBy, done, userId }` — only the items sent change |
| GET | `api/StockTake/{id}/Variance?onlyDiff=` | `{ header, itemCount, countedItems, uncountedItems, itemsWithDiff, shortValue, excessValue, netValue, rows }` |
| POST | `api/StockTake/{id}/Post` | `{ uncountedAsZero, reasonId, userId }` → `{ message, data: { adjNo, adjustedItems } }` |
| POST | `api/StockTake/{id}/Cancel` | `{ userId }` — only while counting |

Proc errors (not found, already posted, negative count, item not on the sheet, item in another open stock take,
nothing counted) → 400 `{ message }`.

**Deploy order**: `U006_BackOffice` on easyway → ItemApi → Prompt 49. Tills: nothing.

### 6.19 Supplier bills → cheques (back office, 2026-10-14)
UI: Lovable Prompt 50. SQL: `Updates/U007_BackOffice_SupplierPayments.sql` (full script `15_BackOffice_SupplierPayments.sql`).
Code: `SupplierLedgerController`, `SupplierLedgerRepository`, `Data/AppDbContext.SupplierLedger.cs`,
`Models/SupplierPayments.cs`, `ChequeCreateController` (`AddCheque`, `{id}/bills`).

1. **Bill received** (the GRN comes later): Supplier ledger → add a PURCHASE with the supplier's bill number
   (`invoiceNo`, unique per supplier) and amount. `referenceId` left empty → `SUPPCODE-00001` (counter
   `z_tb_Supplier.LedgerSeq`, also for payments and returns). `dueDate` left empty → bill date + the supplier's
   **cheque period** `z_tb_Supplier.CreditDays` (0 when not set).
2. **Upcoming payments**: `GET api/SupplierLedger/due` = every bill not fully paid that is due by `toDate` (default
   today + 30), overdue ones included — shown on the cheque writer by due date.
3. **Write a cheque**: pick the supplier (search `api/Supplierz`; the payee printed is `PayeeName`, else `SuppName`) →
   the grid shows its bills (`GET api/SupplierLedger/invoices/{suppId}`, open ones first). Tick bills and the amount
   paid on each; `AddCheque` with `suppId` + `allocations` saves the cheque **and** one PAYMENT row in the ledger
   (credit = cheque amount, remark "Cheque 900001 dated … for INV-1, INV-2", `ChequeId` set) in one transaction
   (`z_sp_LinkWrittenCheque`). `z_tb_WrittenCheque.LedgerId` = that payment row; `z_tb_SupplierPaymentAlloc` = which
   bills it paid and how much. The cheque may be more than the bills ticked (an advance); not less.
   **Part payment** (e.g. half now): `amount` < open and `deduction` 0 → the bill stays Part paid, the rest stays
   open (bills grid, upcoming payments) for a later cheque. The cheque writer's default for the rest is "still owing".
   **Less returns**: a bill's `amount` = "cheque pay", `deduction` = what was taken off it for returns, so the bill is
   settled by `amount + deduction` (→ Paid when that is all that was open). The deduction is set against the
   supplier's RETURN rows not yet set against a bill (oldest first); what is left becomes a new RETURN row
   "Deducted on cheque 900003 (returns) for B-778" (`ChequeId` set, so it goes when the cheque is deleted). Every
   allocation the cheque made has `z_tb_SupplierPaymentAlloc.ChequeId`; deleting the cheque undoes all of them.
   A return the cheque used can't be deleted, nor lowered below what the cheque took from it.
4. **Track it**: a bill shows Open / Part paid / Paid and `paidBy` ("900001 (25,000.00)"); a cheque's bills:
   `GET api/ChequeCreate/{id}/bills`; the ledger shows the cheque number, cheque date and whether the bank debited it.
   A cash payment / return entered on the ledger page can pay bills too (`allocations`).

Rules (procedure errors → 400 `{ message }`): a bill can't be paid more than its amount; a paid bill can't be deleted
or lowered below what is paid; a cheque's payment row can't be edited / deleted on the ledger page — delete the cheque
(its payment goes, its bills are open again); a cheque in the ledger can't change its amount (`PUT` → 400).
`PUT` / `sync` of a cheque keep `suppId` / `ledgerId` even when the page does not send them.

**Payees merged into suppliers**: `z_tb_Supplier.PayeeName` + `CreditDays`. U007 copied each `z_tb_Payee` name to the
supplier with the same name and set `SuppId` on old cheques the same way (old cheques get no ledger rows); payees that
match no supplier are listed by the script. **U008** (`z_sp_TransferPayeesToSuppliers`, dry run first) makes those a
new supplier each — `SuppCode` from the name (`Ceylon Biscuits Ltd` → `CEYL001`), payee name, phone / account / bank
from the payee — and links their old cheques; applied to dev on 2026-10-15 (Sup1 → SUP004, Sup2 → SUP005). `z_tb_Payee` and
`api/Payee` stay for old cheques (read only from now on); `z_tb_WrittenCheque.PayeeId` may be NULL.
U007 also replaces `z_Sp_GetSupplierLedger` / `z_sp_GetSupplierLedger_ByDate`: the old ones used
`SUM() OVER (ORDER BY)` (SQL 2012+); the running balance of a date range now starts at the opening balance.

| Method | Route | Notes |
|---|---|---|
| GET | `api/SupplierLedger/{suppId}` | lines + `invoiceNo, dueDate, chequeId, chequeNumber, chequeDate, chequeDebited, allocatedAmount, openAmount, runningBalance` |
| POST | `api/SupplierLedger/search` | `{ suppId, fromDate, toDate }` → same lines |
| POST | `api/SupplierLedger` | `{ suppId, txnDate, type, invoiceNo, referenceId?, remark, debitAmount, creditAmount, dueDate?, allocations? }` → the saved line |
| PUT | `api/SupplierLedger/{ledgerId}` | same; `allocations` null = what it pays stays, `[]` = pays no bill |
| DELETE | `api/SupplierLedger/{ledgerId}` | |
| GET | `api/SupplierLedger/invoices/{suppId}?includePaid=` | bills: `amount, paidAmount, deductedAmount, openAmount, status, paidBy, dueDate, daysToDue` |
| GET | `api/SupplierLedger/due?toDate=&suppId=` | open bills due by `toDate`, all suppliers: `suppName, payeeName, invoiceNo, dueDate, daysToDue, openAmount` |
| POST | `api/ChequeCreate/AddCheque` | + `suppId`, `allocations: [{ ledgerId, amount, deduction }]` (all optional — without them it works as before; `deduction` = returns taken off that bill) |
| POST | `api/Util/printCheque` | same body and same saving as `AddCheque` (the Cheque Writer's Print button); the cheque is saved — and refused if the ledger refuses it — **before** it is printed |
| GET | `api/ChequeCreate/{id}/bills` | the bills this cheque paid: `billAmount, paidByCheque, deducted` |
| GET/PUT | `api/Supplierz` | + `payeeName`, `creditDays` (send them back on PUT, or they are cleared) |

`GoogleSheetService` now opens its credential file on first use, so a missing file only fails the sheet sync (which
the callers already catch), not every cheque route.

**Deploy order**: `U007_BackOffice` on easyway → ItemApi → Prompt 50. Tills: nothing.

**Supplier Ledger overview (U015, 2026-10-23).** With no supplier picked, the Supplier Ledger page shows every
supplier with ledger entries: what we owe, overdue, due in the next 7 days, open bills, purchases / payments this
month, open bills by days late (not due, 1-30, 31-60, 61-90, over 90 — days past `DueDate`; a bill with no due date
is "not due"), purchases / payments / returns per month for 12 months, the biggest balances, and a sortable list
(filters: we owe / overdue / due in 7 days / paid in advance / settled; CSV export). Click a supplier to open its
ledger (all dates). A supplier's ledger also shows its aging, monthly chart, average days to pay (days from bill to
payment, weighted by the amount — compared with the cheque period), payments / returns not set against a bill
(`Balance = OpenAmount − Unallocated`), quick date ranges, opening / closing balance of the dates shown, filters by
type / open bills / text, and CSV export. Read-only procedures, no table change.

| | Route | |
|---|---|---|
| GET | `api/SupplierLedger/overview` | `z_sp_GetSupplierLedgerOverview`: per supplier `purchases, payments, returns, balance, openBills, openAmount, notDue, overdue, dueIn7, over1To30, over31To60, over61To90, over90, oldestDueDate, unallocated, avgDaysToPay, lastPurchaseDate, lastPaymentDate` |
| GET | `api/SupplierLedger/monthly?suppId=&months=12` | `z_sp_GetSupplierLedgerMonthly`: `monthStart, purchases, payments, returns` (months with entries only; max 60) |

**Deploy order**: `U015_BackOffice` on easyway → ItemApi → back office UI. The old UI keeps working with the new
ItemApi; the new UI needs the new ItemApi (without it the overview shows "Failed to load the supplier overview").

### 6.20 Barcode labels straight to the Zebra — ZPL, label layouts (back office, 2026-10-16)
UI: Lovable Prompt 52. SQL: `Updates/U010_BackOffice_LabelLayout.sql` (full script `16_BackOffice_LabelLayout.sql`).
Code: `Controllers/LabelController.cs`, `Repositories/LabelRepository.cs`, `Service/ZplLabelBuilder.cs`,
`Service/RawPrinter.cs` (same as TillService's).

**The old barcode print is kept as it is**: BarcodePrint page → `POST api/Util/printbarcode` → LocalPrintAgent
(localhost:9001) → BarTender `StickerExpireDatePrint.btw` on `AppSettings:PrinterZebra`. The new route needs neither
BarTender nor LocalPrintAgent: ItemApi builds the label as ZPL and sends it RAW to the printer.

**Label layouts** (`z_tb_LabelLayout`) — one row per sticker roll / sheet, picked on the page when printing:
- `LabelWidthMm` × `LabelHeightMm` = ONE label; `LabelsAcross` (1-10) labels side by side; `RowsPerPage` (1-50) rows
  in one print page; `GapXMm` between columns, `GapYMm` between rows; `MarginLeftMm` / `MarginTopMm`.
  Page width = margin + across × width + (across − 1) × gap. Labels fill left → right, top → bottom.
- **Roll with gaps (die-cut)**: `RowsPerPage` = 1 — the printer finds each row by the gap itself. More rows only for
  sheets / continuous media.
- `Dpi` 203 / 300 / 600 (the print head, e.g. "ZDesigner ZP888 **203DPI**"). `Darkness` 0-30 or NULL.
- Printer: `PrinterName` (Windows printer **on the API server**) → else `PrinterAddress` (`ip:9100`) → else
  `AppSettings:PrinterZebra`. ItemApi in IIS: the printer must be installed for all users on the server (the app pool
  account opens it); a network Zebra by address avoids that.
- What is printed: name (`Inv_Descrip`, else `Descrip` — the printer font has no Sinhala), barcode + its number,
  item code (`RefCode`) and price, MFD / EXP. Font sizes follow the label height; a name that does not fit gets the
  smaller font, then is cut. The price shrinks to fit next to the item code.
- Barcode: `AUTO` = EAN-13 for a 13-digit barcode with a right check digit, else Code 128; `EAN13` on a barcode that
  is not valid EAN-13 prints Code 128. No barcode on the item → its `RefCode` (the till finds items by RefCode too).
  A barcode too wide for the label, or no room left for the barcode, is a 400 with what to change.
- One default (`IsDefault`); deleting it (Status 0) makes the next one by name the default. A new install gets
  "50 x 25 mm, 1 across".

| Method | Route | |
|---|---|---|
| GET | `api/Label/Layouts?all=` | layouts, default first (`all=true` also deleted) |
| GET/POST/PUT/DELETE | `api/Label/Layouts[/{id}]` | add / change / delete (Status 0) a layout |
| POST | `api/Label/Layouts/{id}/Test` | one page with a frame round every label + sample text — check size / gaps / margins |
| GET | `api/Label/Printers` | Windows printers on the API server |
| POST | `api/Label/Print` | `{ labelLayoutId (null = default), skip, items: [{ itemId, qty, price, mfdDate, expDate }] }` → `{ labels, pages, printer, layoutName }`. `price` null = retail price at the location. `skip` = labels already used on the first sheet. Max 1000 per item, 5000 per print |
| POST | `api/Label/Zpl` | same body, returns the ZPL text instead of printing |

Pages that come out the same are sent once with `^PQ` (100 labels of one item on a 1-across roll = one page × 100).

**Deploy order**: `U010_BackOffice` on easyway → ItemApi → Prompt 52. Tills: nothing.

### 6.21 Price labels without BarTender — Sinhala, discounts, any printer (back office, 2026-10-16)
UI: Lovable Prompt 53. SQL: same `U010` (layouts with `LabelKind = 2`). Code: `Service/PriceLabelRenderer.cs`,
price part of `Repositories/LabelRepository.cs`, `api/Label/Price/*`.

**The old price print is kept as it is** — PricePrint page → `api/Util/printprice` (`PricePrint.btw`),
`printDiscountPrice` (`DiscountPrint.btw` when `tax3` amount, else `DiscountPercentagePrint.btw` when `tax2` %),
`printitempricelandscape` (`LandScapePricePrint.btw`) → LocalPrintAgent → BarTender → `AppSettings:PrinterName`
(PegasusPR8003, 80 mm receipt printer). What the old one does, from the code and the templates' own previews:
- one item, one copy; reads the OLD item master (`Items/GetItemWithDetailsByBarcode`); the page may change every value
  before printing (not saved).
- label ≈ 72 × 25 mm: left item code / English name / price (Courier New bold), right the Sinhala name; discount:
  right "Save <amount>" + now price (`price − tax3`); discount %: "Save <tax2>" (no % sign) and **no price**.
- the "Sinhala" tick prints the Sinhala name and blanks the English one; without it the other way round — never both.
- weak spots: Discount print on an item without a discount opens an empty template path (BarTender error box on the
  server, the page still says "sent"); LocalPrintAgent's errors never reach the page (message boxes on the server).

**New**: price layouts (`z_tb_LabelLayout.LabelKind = 2`, own default) with the same size / across / rows / gaps /
margins as barcode labels, plus `Language` (1 English, 2 Sinhala, 3 both), `Rotate` (landscape: label turned 90°),
`SinhalaFont` (NULL = Iskoola Pota), `EnglishFont` (NULL = Courier New, as the old labels), `FooterText` (line on
labels without a discount). The server DRAWS the label (GDI+, Sinhala shaped by Windows) and prints it through the
Windows printer driver — the Pegasus as before, or an A4 laser with sheets of shelf labels. Same drawing → PNG preview.
- Layout of one label: wide (width ≥ 1.8 × height) = the old design — left code / English name (both) / price, right
  the big name; narrow = the same parts one under the other. Each text is as big as its box allows.
- Style per item: `AUTO` (discount label when there is a discount, else price), `PRICE`, `DISCOUNT` (400 when there is
  no discount — the old empty-template case). Amount wins over % (as old). Amount → "Save Rs x" + "Now Rs y";
  % → "Save x%" without price (as old). Discount more than the price → 400.
- Values: item code `RefCode`, name `Inv_Descrip` (else `Descrip`), `SinhalaDescrip`, price / discount from
  `z_tb_ItemDet` (`RetailPrice`, `DiscountAmount`, `DiscountPercent`) at the location — the page may send its own
  (`price`, `discountAmount`, `discountPercent`, `name`, `sinhalaName`), only for that print.
- Some items have English typed in `SinhalaDescrip`: the font follows the text, and "both" does not print the same
  name twice. A font that is not on the server is a 400 (Windows would print Sinhala as boxes).
- Printer: layout `PrinterName` → else `AppSettings:PrinterName`. Errors (printer not found …) come back as 400.
  ItemApi in IIS: the printer must be installed for all users on the server.

| Method | Route | |
|---|---|---|
| GET | `api/Label/Layouts?kind=2` | price layouts (kind 1 = barcode, none = both) |
| POST/PUT | `api/Label/Layouts` | + `labelKind` (on add; never changes), `language`, `rotate`, `sinhalaFont`, `englishFont`, `footerText` |
| GET | `api/Label/Layouts/{id}/Preview` | a price layout's test page as PNG (sample label, frames) — nothing printed |
| POST | `api/Label/Layouts/{id}/Test` | prints that test page (both kinds) |
| POST | `api/Label/Price/Print` | `{ labelLayoutId (null = default price layout), language (null = layout's), skip, items: [{ itemId, qty, style, price, discountAmount, discountPercent, name, sinhalaName }] }` → `{ labels, pages, printer, layoutName }`. Max 500 per item, 1000 per print |
| POST | `api/Label/Price/Preview?page=0` | same body → that page as PNG with label frames |

A barcode layout sent to a price route (or the other way round) is a 400. First install adds "Price 72 x 25 mm"
(default) and "Price landscape 72 x 100 mm" (turned) — check both with Test print on the real printer.

**Deploy order**: `U010_BackOffice` on easyway → ItemApi → Prompt 53 (after 52). Tills: nothing.

### 6.22 Return Items list — mobile scan → PRN (back office + mobile app, 2026-10-23)

Items going back to a supplier (damaged, expired, not selling …) are collected in one list, on the **new** system.
The old list (`z_tb_ReturnItem`, old item / supplier codes, `api/Return`, processed into the old `tb_Purchase`) is
not used any more — the table and `api/Return` are left as they were so an old app build keeps working until it is
updated.

1. **Scan** — mobile app *Return Stock* (or the back office *Purchasing › Return Items* page): pick the supplier, scan
   the item (camera, typed code or name), qty, reason, **Add**. Scanning the same item again on the phone asks before adding 1. The
   same item for the same supplier that is still *Added* gets the qty added (one row).
2. **Ready** — when the items are checked / packed for the supplier's rep, select them and press **Ready**
   (back: *Not ready* / *Back to Added*).
3. **Process** — the Ready rows of **one** supplier become one PRN: `z_tb_TempPurchaseSummary` (Type 2, Status 1,
   number `PRN` + `z_tb_System.PRNO`, the same counter as Goods Return) + `z_tb_TempPurchase` lines (same item twice →
   one line, cost / sell price from when it was added). With *take them off stock now* (default, always on the phone)
   it is posted at once (`z_sp_PostPrn`, stock −qty, Status 2). Unticked: open the PRN on Goods Return and *Commit
   to stock* there. The rows keep their `PrnNo` (Status 3) and show under *PRN made* for 90 days.
4. **Print** — the return slip on the receipt printer (old `PrinterService` layout, PRN number on the first line).

`z_tb_ReturnList`: `ReturnId, LocationId, ItemId, SuppId, Qty, CostPrice, SellPrice, Reason, Remark, Status (1 Added,
2 Ready, 3 PRN made), PrnNo, Source (1 mobile app, 2 back office), UserId, CDate, UDate`. Items have no supplier yet
(`z_tb_Item.SupId` is empty), so the supplier is picked on the screen; when an item has one, the page uses it.
A PRN does not touch the supplier ledger (same as Goods Return).

| | Route | |
|---|---|---|
| GET | `api/ReturnList?suppId=&status=&days=90` | open rows (Added + Ready) when `status` is empty; `3` = PRN made in the last `days` days. With `descrip, barcode, suppName, stockQty, amount` |
| GET | `api/ReturnList/Lookup?code=` | scanned / typed code (exact barcode, then ref code, then codes containing it) → `itemId, descrip, costPrice, retailPrice, stockQty, suppId` |
| POST | `api/ReturnList` | `{ itemId, suppId, qty, reason?, remark?, source (1 mobile / 2 back office), userId? }` → the row |
| PUT | `api/ReturnList/{id}` | `{ qty, suppId, reason?, remark? }` (not after the PRN) |
| POST | `api/ReturnList/status` | `{ ids, status: 2 Ready / 1 Added }` → `{ changed }` |
| POST | `api/ReturnList/delete` | `{ ids }` → `{ deleted }` (rows with a PRN stay) |
| POST | `api/ReturnList/process` | `{ ids, post = true, refNo?, remark?, print? }` → `{ prnNo, lines, qty, amount, posted, printed, printError }`. 400: not Ready / more than one supplier |
| POST | `api/ReturnList/print` | `{ ids }` → the slip on the receipt printer |

Procs: `z_sp_GetReturnList`, `z_sp_AddReturnListItem`, `z_sp_UpdateReturnListItem`, `z_sp_SetReturnListStatus`,
`z_sp_DeleteReturnListItems`, `z_sp_ReturnListToPrn` (type `z_tt_IdList`). Like the other mobile routes they are not
`[AllowAnonymous]`: with `Auth:Enforce = true` the app would need a sign-in.

**Deploy order**: `U016_BackOffice` on easyway → ItemApi → back office UI → mobile app (new build). Tills: nothing.

### 6.23 Mobile app on the new system — Stock, GRN, Price Link (mobile app, 2026-10-23)
SQL: `Updates/U017_BackOffice_MobileGrn.sql` (full script `20_BackOffice_MobileGrn.sql`). Code: `MobileGrnController`,
`MobileGrnRepository`, `Data/AppDbContext.MobileGrn.cs`, `Models/MobileGrn.cs`; `ItemzController.UpdateRetailPrice`.
Every app page now uses the new tables; the old routes the app used (`api/Items` price link / price, `api/Stocks`,
`api/PosStock`, `api/PosCountedStock`, `api/GrnTemp`, `api/Return`) are left for old app builds only.

**Stock page** — no new API: `Itemz/SearchByCode`, `StockLedger/Balance/{id}` + `ItemCard` (last 30 days),
`Itemz/PriceLinks/{id}`, `Sync/Terminals`, `StockAdjustment/Reasons` + `Save` (one line, user `mobile`, remark
"Mobile app"). Set = count mode (`countedQty`), Add / Remove = quantity mode (`adjQty` ±). The old POS stock, "with /
without POS stock" and Flush data / Flush item are gone: till bills are uploaded about every minute and posted to the
ledger by `api/Sync/Invoices`, so the balance is already after the sales. What is left: a bill made before the count but
still on the till (offline, or in the last minute) is taken off again when it arrives, so a count-mode Set can come out
too low by those bills. The page shows each till's last upload and warns on Set when a till `isStale` (§6.2).
Quantity-mode Add / Remove is safe any time.

**GRN page** — the phone fills a **suspended GRN** of the supplier (`z_tb_TempPurchaseSummary` Type 1, Status 0,
UserId `mobile`, Remark "Mobile GRN"), one open draft per supplier, number `GRN` + `z_tb_System.PNO` taken in one
statement. Same item + cost + selling price again → the qty is added to that line. Nothing moves stock. The back office
opens the draft on **GRN Entry** (search → load), checks it, adds the supplier's invoice no (RefNo), saves and commits.
Once it is saved there (Status 1) or its user changes, the phone starts a new draft for the next delivery. Deleting the
last line deletes the empty draft. The line's selling price is only recorded (posting does not change the item price) —
the app points to Price Link when it differs. The old app's "Item Ref" running number has no column in the new tables
and was dropped.
⚠ GRN Entry shows the next number (`PNO`) when it opens and takes it only when it saves: if the phone makes a draft in
between, the office save fails on the duplicate number (unique `GrnNo`) — clear the page to get the next number.

| Method | Route | Notes |
|---|---|---|
| GET | `api/MobileGrn?suppId=` | the supplier's open draft lines, newest first (with item cost / price now and stock); `[]` = no draft |
| POST | `api/MobileGrn/line` | `{ suppId, itemId, qty, costPrice, sellPrice }` → `{ grnNo, idx }`. 400: qty ≤ 0, price < 0, unknown item / supplier |
| PUT | `api/MobileGrn/line/{idx}` | `{ qty, costPrice, sellPrice }`. 400 when the draft was taken over by the back office |
| DELETE | `api/MobileGrn/line/{idx}` | → `{ grnNo, linesLeft }` (0 = the draft was deleted too) |

**Price Link page** — `Itemz/PriceLinks`, `AddPriceLink`, `PriceLink/{id}` (delete) and the new
`Itemz/UpdateRetailPrice` (§5, Price links).

**Deploy order**: `U017_BackOffice` on easyway → ItemApi → mobile app (new build). Back office UI and tills: nothing.

### 6.24 Mobile app downloads (back office Tools → Mobile App, 2026-10-23)

The app files are copied by hand into the server folder **MobileApp** (next to `ItemApi.dll`; `MobileApp:Folder` in
appsettings for another place — use one outside the site if a publish deletes extra files). The API makes the folders.

- Android: `MobileApp\*.apk` or `MobileApp\Android\*.apk` — the newest file is offered, older ones are listed.
- iPhone (later): `MobileApp\iOS\link.txt` — one line, the App Store / TestFlight link (an iPhone can't install a
  downloaded file); an `.ipa` in `MobileApp\iOS` is listed for download.

The page shows a QR code a phone scans to download. It uses the host the back office was opened from, so open the
back office with the server's IP (not `localhost`) to get a QR code a phone can use. No DB change.

| Method | Route | Notes (all open — a phone's browser has no token) |
|---|---|---|
| GET | `api/MobileApp` | `{ android: [{ fileName, sizeBytes, modified }], ios: [...], iosLink }`, newest first |
| GET | `api/MobileApp/{android\|ios}/Latest` | the newest file (404 when none); Android is always saved as `IRM.apk` |
| GET | `api/MobileApp/{android\|ios}/Download/{fileName}` | that file — a plain name in the folder only |

### 6.25 Day Reports — any day, any time (back office Sales → Day reports, 2026-10-25)
SQL: `Updates/U018_BackOffice_DayReports.sql` (full script `21_BackOffice_DayReports.sql`) and
`Updates/U018_Till_CashMovementUpload.sql` (full script `02_FrontCashier_zf.sql`). Code: `DayReportController`,
`DayReportRepository`, `Data/AppDbContext.DayReport.cs`, `Models/DayReportModels.cs`; TillService `SyncWorker`
(`UploadCashMovementsAsync`); back office `pages/DayReports.tsx`, `services/dayReportApi.ts`.

**Opening cash / paid in / paid out now go up to the back office.** `zf_tb_CashMovement` has `Synced` / `SyncedAt`
like the bills; every sync run (straight after the bills) sends the unsent rows to `POST api/Sync/CashMovements`
(`z_sp_SyncCashMovements` → `z_tb_CashMovement`, key TerminalId + the till's MoveId, a resend replaces the row) and
marks them (`zf_sp_MarkCashMovementsSynced`, only rows still at the Status sent). An opening cash typed again (old row
Status 9) is sent again. The first run after the update sends the whole history. A till db without U018, or an older
ItemApi (404), is skipped with one log line — bills and the Z still go up. The Z upload itself is unchanged.

**The page** — pick a day (and a till, or all): **Summary** (sales before discounts, item / bill discounts, refunds,
net sales; cash / card / bank / cheque / credit; drawer: opening + cash − refunds + paid in − paid out = expected cash;
per till; print 80mm / A4), **Day end (Z)** (the Zs of that business date with their cash in / out, link to the Z
detail), **Paid in / out** (each one: time, till, Z, reason, cashier; print), **Items** (every item: sold, refunded,
net qty, price, bills, discount, amount; other items one row per typed name; print A4), **Bills** (every bill incl.
refunds and voided) → **Bill copy** (lines, discounts, payments; print 80mm / A4 marked COPY). The bill number box at
the top opens any bill, any day. Rules as the till Z and the dashboard: voided bills left out of the sums, refunds
negative. Bills and cash movements count by their own date (till clock); the Zs by their business date. Item amounts
are after the item discount and before the bill discount (that is on the bill only).

| Method | Route | |
|---|---|---|
| GET | `api/DayReport?date=&terminalId=` | `{ date, terminalId, tills: [...], zReports: [...], cashMovements: [...] }` (no date = today) |
| GET | `api/DayReport/Items?date=&terminalId=` | `z_sp_DayReportItems` |
| GET | `api/DayReport/Bills?date=&terminalId=` | `z_sp_DayReportBills` (voided too, Status 9) |
| GET | `api/DayReport/Bill/{invoiceNo}` | header + `lines` + `payments`; 404 when the back office does not have it |
| POST | `api/Sync/CashMovements` | till → `{ terminalId, movements: [{ moveId, zNo, kind, amount, reason, cashierId, createdAt, status }] }` → `{ received }` |

**Deploy order**: `U018_BackOffice` on easyway → ItemApi → back office UI → on each till `U018_Till` → TillService.
The till script first is fine too (the old TillService ignores the new columns). No billing page change.

### 6.26 Voids & No Sale — for stopping cash loss (back office Day reports → Voids & No Sale, 2026-10-25)
SQL: `Updates/U019_BackOffice_VoidReport.sql` (full script `22_BackOffice_VoidReport.sql`) and
`Updates/U019_Till_VoidLog.sql` (full script `02_FrontCashier_zf.sql`). Code: `DayReportController` (`Loss`),
`SyncController` (`TillLog`), `Data/AppDbContext.DayReport.cs`; TillService `POST /void-log`, `SyncWorker`
(`UploadTillLogAsync`); billing page `CashierBilling.tsx` (`logVoids`); back office `pages/DayReports.tsx`.

**The till logs every line taken off a bill before payment** in `zf_tb_VoidLog` (`zf_sp_LogVoid`, via
`POST /void-log`): **Void line** (Kind 1), **Void bill** (Kind 2, every line, same GroupNo) and a **qty made smaller**
with the Qty key (Kind 3, the qty taken off, at the old price). Cashier, open Z, item, qty, price, amount; `Refund` = a
line of a refund bill. The log never blocks the cashier: a till db without U019 answers `{ logged: false }`, a
TillService error is ignored. Saved bills are not voided here — that is the existing bill void (Status 9) / refund.

**Up to the back office**: every sync run (after the cash movements) sends unsent rows of `zf_tb_VoidLog` and
`zf_tb_DrawerLog` (every drawer opening: bill, No Sale, opening cash, paid in, paid out — `Synced` / `SyncedAt` added,
the old history goes up once) to `POST api/Sync/TillLog` → `z_tb_TillVoidLog`, `z_tb_TillDrawerLog` (keys TerminalId +
the till's id; rows never change, a resend is skipped). A till db without U019 or an older ItemApi (404) is skipped
with one log line.

**The tab** (one day, a till or all): totals (voids total, void lines, void bills, qty cuts, No Sale, refunds);
**per cashier** — bills, sales, void lines / void bills / qty cuts (count · Rs), voids total, **void %** = voids ÷
(sales + voids), No Sale (and how many did not open the drawer), refunds, voided saved bills; a row is red when void %
is over 3 or No Sale over 5; **void lines** (time, till, cashier, kind, item, qty, price, amount; refund-bill lines
faded and left out of the sums); **No Sale** (time, till, cashier, reason); **refunds and voided bills** (from the
Bills list, click = bill copy). Print A4.

| Method | Route | |
|---|---|---|
| GET | `api/DayReport/Loss?date=&terminalId=` | `{ date, terminalId, cashiers: [...], voids: [...], noSales: [...] }` |
| POST | `api/Sync/TillLog` | till → `{ terminalId, voids: [...], drawer: [...] }` → `{ voids, drawer }` |

**Deploy order**: `U019_BackOffice` on easyway → ItemApi → back office UI → on each till `U019_Till` → TillService →
billing page. Until a till has all of them its refunds show but no voids / No Sale.

### 6.27 Bill recovery after a power cut + Abandoned bills (billing page / Day reports → Abandoned bills, 2026-10-26)
SQL: `Updates/U022_Till_DraftBill.sql` (full script `02_FrontCashier_zf.sql`) and
`Updates/U022_BackOffice_AbandonedBills.sql` (full script `23_BackOffice_AbandonedBills.sql`). Code: TillService
`POST /draft` and `/draft/*` routes, `TillDb` (draft methods, `SaveInvoiceAsync` / `SuspendBillAsync`), `SyncWorker`
(`UploadAbandonedBillsAsync`); billing page `CashierBilling.tsx` + `lib/billDraft.ts`; ItemApi `SyncController`
(`AbandonedBills`), `DayReportController` (`Abandoned`); back office `pages/DayReports.tsx`.

Before this the bill on the screen lived only in the browser: a power cut, a crash or a closed browser lost it and left
no trace.

**Saved as it changes**: a moment (0.3 s) after each change the page sends the WHOLE bill to `POST /draft` →
`zf_tb_DraftBill` + `zf_tb_DraftBillItem` (key `DraftKey`, a GUID the page makes on the first line). The whole bill,
not only the change: it is a few KB to the till's own service and takes ~3 ms, and a lost or late change can never
leave the till with a different bill than the screen. One save at a time; changes made meanwhile go in the next;
`SaveSeq` goes up with each save and an older one arriving late is ignored. The cashier never waits for it.
Status bar: "Bill saved 10:42:05" (green), "slow … ms" (≥ 500 ms, yellow), "Bill NOT saved" (red, the till service
does not answer - retried every 3 s), "Auto-save OFF". TillService logs `POST /draft` only when it fails or is slow.

**Closed with the bill**: Pay and Suspend send `draftKey`; TillService saves the bill / suspend AND closes the draft
(`zf_sp_CloseDraftBill`, Status 1 paid / 2 suspended) in ONE transaction - a power cut can never leave a paid bill
that is offered again. Void bill or the last line voided → `POST /draft/{key}/close` (Status 3). A closed draft keeps
its header 7 days so a save still on its way can't open it again.

**After a restart**: when a cashier signs in, the page asks `GET /draft/open`. Each bill left open shows "Unfinished bill
found" (cashier, lines, total, last change) - no Esc / click outside, the cashier must choose:
- **Take bill back** → `POST /draft/{key}/recover`: lines come back like a recalled suspended bill (item as it is now;
  a price change is noted), the bill goes on under the same key. An exchange held for the bill comes back; its
  supervisor approval is asked again at Pay.
- **Throw away** → reason + supervisor PIN → `POST /draft/{key}/discard`.
Both are logged in `zf_tb_AbandonedBill` (+ items): the lines as they were, who found it, when, and later how the bill
ended (`FinalStatus` 1 paid, 2 suspended, 3 voided, 8 thrown away).

**Option**: Menu → "Auto-save bill: ON / OFF" (per till, `localStorage till.autoSaveBill`, default ON). Changed only with
no bill on the screen; OFF needs the supervisor PIN. A till db without U022 shows "till database needs update U022".

**Up to the back office**: every sync run sends unsent abandoned bills to `POST api/Sync/AbandonedBills` →
`z_tb_TillAbandonedBill` + `z_tb_TillAbandonedBillItem` (key TerminalId + AbandonId). A bill whose end changes later is
sent again and its end updated. A till db without U022 or an older ItemApi (404) is skipped with one log line.

**The tab** (one day by the last change, a till or all): abandoned bills (count · Rs), thrown away, taken back then
voided, taken back and paid, tills that stopped; each bill: last change, till / Z, cashier, lines, amount, when the
till was back, **off for** (last change → back: how long the till was off / stuck), what happened, by whom; click a row
for its items. Red rows = thrown away, or taken back then voided. Print A4.

| Method | Route | |
|---|---|---|
| POST | `/draft` (TillService) | `{ draftKey, saveSeq, cashierId, invType, priceType, discount, discountPercent, pageState, items }` → `{ saved, status, enabled, ms }` |
| POST | `/draft/{key}/close` | `{ status: 3 }` → `{ ok }` |
| GET | `/draft/open` | open drafts, newest first |
| POST | `/draft/{key}/recover?cashierId=` | the bill with its lines (like a recall) |
| POST | `/draft/{key}/discard` | **token** `{ cashierId, reason }` → `{ ok }` |
| GET | `api/DayReport/Abandoned?date=&terminalId=` | `{ date, terminalId, bills: [...], lines: [...] }` |
| POST | `api/Sync/AbandonedBills` | till → `{ terminalId, bills: [...], lines: [...] }` → `{ bills }` |

**Deploy order**: `U022_BackOffice` on easyway → ItemApi → back office UI → on each till `U022_Till` → TillService →
billing page. The old TillService / page keep working after the till script; the new page on a till without U022
simply does not save.

### 6.28 Settings — general and per user (back office Settings → System settings, 2026-10-27)
SQL: `Updates/U023_BackOffice_Settings.sql` (full script `24_BackOffice_Settings.sql`) and
`Updates/U023_Till_Settings.sql` (full script `02_FrontCashier_zf.sql`). Code: ItemApi `SettingsController`,
`SettingRepository`, `AppDbContext.Setting.cs`, `SyncController` (`Settings`); TillService `GET /settings`,
`POST /bill/profit`, `SyncWorker.DownloadSettingsAsync`; back office `pages/SystemSettings.tsx` +
`services/settingsApi.ts`; billing page `CashierBilling.tsx`.

**One list, two levels**: `z_tb_Setting` holds every setting (key, group, label, help text, type `bool` / `choice`,
choices, default) and its **general** value (NULL = the default). Scope 1 = general only; scope 2 = a user can also
have their **own** value (`z_tb_UserSetting`, no row = the general value). A value for a user: own value → general
value → default. The list belongs to the scripts: a new setting is one more row in `24_` (and in an update script),
no table change. Admins change values on the Settings page (General tab: one control per setting, "Back to the
default"; Per user tab: a table of users × per-user settings, "Default (…)" = the general value).

**To the tills**: every download run (≤ 5 min, or Reload) TillService gets the WHOLE list from `GET api/Sync/Settings`
(general values with `loginName` null, then users' own values by login name - a few rows, no secrets, no terminal key)
and `zf_sp_SaveSettings` replaces `zf_tb_Setting` / `zf_tb_UserSetting` - so a value reset on the back office is gone
from the till too. A till keeps working with the copy it has while offline. `GET /settings` gives the signed-in
cashier's values; the page reads them at sign-in, after Reload and every 2 minutes. No copy (older till db, older
ItemApi) = the old behaviour.

**Settings now**:
| Key | Scope | Default | What |
|---|---|---|---|
| `Till.BillDiscSkipItemDisc` | general | 0 (off) | on: the bill discount % is worked out only on lines WITHOUT an item discount (like NoDiscount items). Example: Rs 1000 no discount + Rs 450 (500 less 10 %) + Rs 200 → 10 % bill discount of 1200 = Rs 120, not of 1650 |
| `Till.ProfitView` | per user | 1 | the Profit button on the till: 0 hidden, 1 shown - supervisor PIN, 2 shown - no PIN (owners / supervisors) |

**Bill discount rule** lives in the till db: `zf_fn_BillLineCost.InDiscountBase` = 0 for NoDiscount items and, with
the setting on, lines with an item discount (line `Discount` > 0). The page's base (`POST /bill/profit` →
`discountBase`, `leftOutLines`) and the check in `zf_sp_SaveInvoice` use the same function, so they never differ. The
discount dialog and the bill show "% of Rs …" when lines are left out. Each sale line keeps it
(`zf_tb_InvoiceItem.InDiscBase`); a refund (`zf_sp_SaveBillRefund`) or an exchange gives back the bill discount in
proportion to the lines it was taken off only - a refunded item-discount line gives back none of it (before: every
line shared it, NoDiscount items too). Bills saved before U023 (NULL) and a bill whose discount was typed as an
amount with no line in the base: every line shares it, as before. The cap (max discount = bill profit) is unchanged.
Not sent to the back office: the Sales dashboard / Day report profit still spread the bill discount over every line.

**Profit without the PIN**: `POST /bill/profit` answers a signed-in cashier whose `Till.ProfitView` is "2" without
`X-Supervisor-Token` (checked by TillService against the till's copy, not by the page). A bill discount still needs
the PIN. "0" hides the button (and closes the view if it was open).

| Method | Route | |
|---|---|---|
| GET | `api/Settings` | **admin** - every setting with its general value, `userValues` |
| PUT | `api/Settings/{key}` | **admin** `{ value }` (null = the default) |
| GET | `api/Settings/Users` | **admin** - `{ settings (per user), users: [{ userId, loginName, userName, roleId, status, values }] }` |
| PUT | `api/Settings/User/{userId}/{key}` | **admin** `{ value }` (null = the general value) |
| GET | `api/Sync/Settings?terminalId=` | till ← `[{ loginName, settingKey, value }]` |
| GET | `/settings` (TillService) | `{ enabled, loginName, values: { key: value } }` |

**Deploy order**: `U023_BackOffice` on easyway → ItemApi → back office UI → on each till `U023_Till` → TillService →
billing page. Old TillService / page keep working after the till script (no settings come down until the new
TillService; the rule stays off).

### 6.29 Card machine — PAX A910 (ECR) on the till (billing page Menu → Card machine, 2026-10-27)
SQL: `Updates/U024_Till_CardMachine.sql` (full script `02_FrontCashier_zf.sql`). Code: TillService `PaxA910Ecr/` (the
C# rewrite of the old Java POS card code `edc.ecr` + `PAX-A910_JAVA.dll`, copied from
`C:\Users\prasada\Desktop\ECR\PaxA910Ecr_CSharp`), `Ecr/` (`EcrSettingsStore` → `ecr.json`, `CardMachine`,
`SimulatedPaxTransport`), `/ecr/*` routes, `POST /invoices`; billing page `CashierBilling.tsx`,
`components/till/EcrSettingsDialog.tsx`. Details and routes: TillService README "Card machine".

**Per till, on / off** (Menu → Card machine, supervisor PIN to save): ON = Card and the card part of Mixed go straight
to the machine — no PIN, no typed card reference ("Continue on the card machine", Rs on the screen, nothing else can be
done until it answers); the till refuses a typed card line on a sale. OFF = typed by hand as before. The same window:
USB port (Auto finds the PAX port) or network address, the machine's own slip, **Check** (machine connected, ECR app
open), **Last transaction**, and the card payments to check.

**Flow** (the old POS's, `CardPaymentService.Pay`): machine ready → its last transaction (this EcrRef already approved
→ used) → card → charge (amount in cents, EcrRef) → no answer → last transaction again. Approved only for exactly the
amount asked; a decline shows the bank's reason and the cashier can try again or pay another way.

**Never lost, never charged twice**: `zf_tb_CardPayment` gets the charge BEFORE the machine is asked, under the bill's
key (its draft key, §6.27). EcrRef = 3-digit terminal + 9-digit row id. Pay again for the same bill — the bill save
failed (price changed, …), or a power cut and the bill taken back — and the approved charge is used, not made again;
a retry after a decline / no answer sends the same EcrRef, so the machine's last transaction shows a payment the
customer made after all. Another amount while one is approved for the bill → refused (pay that amount, or void it on
the machine). The bill and its card payment are saved in ONE transaction (`zf_sp_UseCardPayments`); the card payment
line's `RefNo` = last 4 digits + approval code + the machine's invoice number (on the receipt and the back office).

**To check**: approved but on no bill (customer charged, no bill), approved for another amount, no answer → red
"N card payments to check" on the status bar → Menu → Card machine: **Ask the machine** (its last transaction) or
**Voided on machine** (supervisor PIN + reason, Status 5).

**Not done (on purpose, first step)**: voids and refunds to a card on the machine (done on the machine by hand, as
before; the refund bill's card line is typed); card details are not sent to the back office (only the payment line's
RefNo goes up with the bill).

**Test without the machine**: TillService `Ecr:Simulator` true (pretend machine: cents .13 declined, .44 no answer,
.77 answer lost but paid). First real test: Rs 1.00 on the A910 — it must show Rs 1.00 (amount sent in cents).

**Deploy order**: on each till `U024_Till` → TillService → billing page → Menu → Card machine: Check, then switch ON.

### 6.30 Cost batches (FIFO) — prices follow the stock (back office, 2026-10-28, U026)
Every stock-in is a **batch** (`z_tb_StockBatch`): selling price, cost, qty in, **qty left**. Stock-outs take from
the batches; `z_tb_StockBatchMove` keeps what each ledger row took. `z_sp_PostStockMovements` calls
`z_sp_ApplyStockBatches` for every movement, in the same transaction.

| Movement | Batch |
|---|---|
| GRN line | new batch at the line's selling price + cost. Selling price = `RetailPrice` (or 0) → `SellPrice NULL` = **normal price** (follows `RetailPrice` when it is changed). Another price → **price link** stock (`PriceLinkId`; the link is made when there is none) |
| Refund, + adjustment, opening | new batch at the normal price (a refund at an active link's price: that link), cost = that price's cost now |
| Sale, PRN, − adjustment | takes from the batches left: **same price** as the line first, then the normal price, then the rest — **oldest first** |
| Stock below 0 | a stock-out takes what is there, the rest is not in any batch; the next stock-in fills the minus first. An item's open batches = its balance (0 while below 0) |

Then, per item of the movement:
1. **Cost** — the item's `CostPrice` = the cost of the oldest normal-price batch left; each link's `CostPrice` = its
   oldest batch left. The till shows this in the profit view and uses it for the bill discount cap.
2. **Link price sold out** → the link is deleted (`Status 0`). Links that never had a batch (typed in Item Entry, old
   links) are not touched.
3. **Normal price sold out, a link price still has stock** → the oldest such price becomes the item's `RetailPrice`
   (+ the link's `WholesalePrice`, if it has one) and that link is deleted. So when only one price is left there is no link.
4. A link deleted in Item Entry → its stock is normal-price stock. `RetailPrice` changed to a link's price → that link goes.
5. `UDate` moves only on a change, so the tills download the new prices / links on their next sync.

Example: item 150 / cost 100 with 10 in stock; GRN 10 at 170 / cost 120 → link 170 / cost 120, item stays 150 / cost 100.
The 10 at 150 sell → `RetailPrice` 170, cost 120, no link.

- Cost typed in Item Entry is overwritten by the batch cost on the item's next movement.
- `AvgCost` (`z_tb_StockBalance`) and the sale lines' `CostPrice` are unchanged; FIFO sale cost =
  `z_tb_StockBatchMove.Qty × z_tb_StockBatch.CostPrice` (not used by a report yet).
- **Switching on** (database with stock movements): `EXEC dbo.z_sp_RebuildStockBatches @LocationId = 1, @DryRun = 1;`
  replays the whole ledger, lists the items with a new `RetailPrice` / `CostPrice` and the links added / deleted /
  re-costed, then rolls back. `@DryRun = 0` keeps it and sets `z_tb_System.StockBatchAt` — until then
  `z_sp_ApplyStockBatches` does nothing. Run it again any time the batches look wrong. A new / cleaned database
  (`01_`, `09_`) starts with the batches on.

### 6.31 GRN scan — read an invoice photo with AI, match the lines to our items (R&D, 2026-10-29)
Goal: a photo of a supplier invoice becomes a GRN draft. **Step 1 — read**: no db change, no item
matched, nothing saved to a GRN. Code: `Controllers/GrnScanController.cs`, `Service/GrnScanReader.cs`,
`Models/GrnScanModels.cs`.

- `POST api/GrnScan/Read` (multipart: `files` = 1–4 photos of ONE invoice, pages in order, JPG / PNG / WEBP / HEIC,
  10 MB each; `supplierId` optional, only echoed for now) → `{ model, images, ms, supplierId, header: { supplierName,
  invoiceNo, invoiceDate, vatNo, pageText, totalGross, totalDiscount, netTotal }, lines: [...], check, inputTokens,
  outputTokens, savedAs }`. 400 / 502 / 504 `{ message }`.
- Each line as printed: `supplierCode` (the supplier's own code — the key for matching in step 2), `description`,
  `barcode`, `saleCases` / `salePieces` or `saleQty`, free qty the same way, `caseSize`, `unitPrice`, `grossAmount`,
  `discount` (scheme disc), `mrp`, `unclear` / `note`. ItemApi adds `qty` (= cases × case size + pieces), `freeTotal`,
  `unitCost` (= (gross − discount) ÷ qty), `amountDiff` (qty × price − gross), `status` ok / check / error and
  `issues`. `check`: lines ok / to check / with error, the line sums against the printed total, line numbers that
  jump, the same supplier code twice.
- `GET api/GrnScan/Models` — the Gemini models the key can use.
- Google Gemini API (`generateContent`, JSON answer in a fixed schema, temperature 0). Config `GrnScan`: `ApiKey` —
  the key from Google AI Studio, kept in `appsettings.json` (never sent to the page);
  `Model` (default `gemini-3.5-flash`; `gemini-2.5-flash` is closed to new keys); `SaveFolder` (default `Uploads/GrnScan`, git-ignored: each read keeps the
  photos, `gemini.json` and `result.json` to compare accuracy; `""` = nothing kept); `TimeoutSeconds` (120).
  Free tier: a daily request limit, and Google may use what is sent to improve its products.
- The request log never writes the body of `api/GrnScan/*` (photos).

**Step 2 — our item for each line** (U029, `25_BackOffice_GrnScan.sql`, `Service/GrnScanMatcher.cs`, back office
page Purchasing → **GRN Scan** `/grn-scan`):
- `z_tb_SupplierItemMap`: supplier + the supplier's item code → ItemId (no code printed: their item name, capitals,
  letters and digits only, is the key). Keeps the supplier's own name of the item (the remark) and the case size.
- Matching (`z_sp_GrnScanMatch`, done by `Read` when `supplierId` is sent): saved match by code → by name → a printed
  barcode of one active item. `matchedBy` code / name / barcode. A matched line gets price checks: unit cost
  ≥ 10 % from our cost price ("right item? right qty?") and MRP ≠ our price → `status` check.
- No match: `suggestions` = the 5 closest item names (shared letter triples, + same pack size 500G / 1KG / 450ML,
  + the item's first word starts the supplier's name, + the item's supplier is this supplier). Supplier short forms
  (SLT = Sunlight, CMFT = Comfort, WLT = Wonderlight) are not guessed — the first time a person picks.
- `POST api/GrnScan/Match { supplierId, lines }` — checks + matching again without a new AI read (another supplier,
  a fixed qty). `GET api/GrnScan/Items?supplierId=&text=` — item picker (every word typed in the name; a code /
  barcode typed exactly comes first). `POST api/GrnScan/SaveMatches { supplierId, lines: [{ supplierCode,
  description, itemId, caseSize }] }` — keeps the picks (the same code / name again replaces its match).
  `GET api/GrnScan/Maps?supplierId=` / `DELETE api/GrnScan/Maps/{mapId}` — the saved matches, remove a wrong one.
- Page: supplier first, photos (phone camera or files), Read invoice (≈ 1 minute); each line shows what was read,
  qty (cases × size + pieces), cost a piece, MRP and our item (saved match, or the 3 closest names to click, or
  search); the pencil fixes a misread number (checked again, no new AI read); **Save matches** keeps the picks. The
  last scan stays on the page through a refresh (sessionStorage, not the photos). No GRN, stock or price change.

**Step 3 — GRN draft** (U030, `z_sp_GrnScanMakeDraft`, `POST api/GrnScan/MakeDraft`):
- Page: a **Use** box on each line (leave a line out), then **Make GRN draft** — supplier invoice no and date (from
  the read, can be changed), selling price = our price now or the printed MRP (a price other than ours makes a price
  link at the commit, §6.30). Every line in use needs our item and no reading error (fix it with the pencil, or
  leave it out).
- A NEW suspended GRN (Status 0, UserId `scan`, next GRN number, RefNo = the invoice no, remark "GRN scan - invoice
  … of …"). Line qty = qty + free; CostPrice = (gross − line discount) ÷ (qty + free) — the commit takes the line cost
  for the stock cost, so free goods and the scheme discount lower the cost of every piece; GAmount = the line amount
  after its discount (GRN total = the invoice after line discounts). Open it on GRN Entry, check and commit as usual —
  nothing goes to stock before.
- The same invoice no of the supplier on another GRN → 409 `{ sameInvoice: true }`; the page asks "make it anyway?"
  (`allowSameInvoice`). The matches of every line are saved again (`UseCount` = invoices it was used on).

**Saved scans** (U031, `z_tb_GrnScan`, `Service/GrnScanStore.cs`): every `Read` is kept (`scanId` in the answer); the
page saves its work 2 s after each change (`PUT api/GrnScan/Scans/{id}` { supplierId, result, state: { picks, skip }
}). **Saved scans** on the page: `GET api/GrnScan/Scans?all=` (open ones; all = also those made into a GRN),
**Open** = `GET api/GrnScan/Scans/{id}` + the photos `GET …/Scans/{id}/Photo/{page}` (no new AI read; matches saved
since then apply, the picks stay), **Flush selected** = `POST api/GrnScan/Scans/Flush { scanIds }` (the rows and
their photo folders are deleted; saved matches and GRNs stay). `MakeDraft` with `scanId` marks the scan Status 1 +
GrnNo.

Next step (not built): 4. photos from the mobile app.

### 6.32 Supplier bills paid in cash from a till (2026-10-29, U032)
SQL: `26_BackOffice_TillPayments.sql` + a section of `02`. Code: `SupplierLedgerController` (`TillPay`),
`SyncController` (`TillPayRequests`), `Data/AppDbContext.TillPay.cs`; TillService `Sync/SyncWorker.cs`,
`GET /payrequests`, `POST /cash/movements { requestId }`; pages Supplier Ledger and the billing page.

1. **Supplier Ledger**: tick bills (PURCHASE with something open) and, if wanted, returns (RETURN with credit left) →
   **Pay from till** → cash to pay (default = bills open − returns left; less = a **part payment**), the till (or any
   till), the paid out reason ("Supplier <name>: <bill nos>"). → `z_tb_TillPayRequest` Status 0 + its lines. A bill /
   return can wait on one request only. The page lists the supplier's till payments (waiting / paid / cancelled);
   a waiting one can be cancelled.
2. **Till**: TillService downloads the waiting requests for it or any till every sync run (~30 s,
   `zf_tb_PayRequest`). The billing page shows **Pay supplier (n)** next to Menu → the list → **Pay** opens the Paid Out
   with the amount and reason filled in and locked; supervisor PIN, drawer check, slip and drawer as any paid out
   (`zf_sp_PayPayRequest` = `zf_sp_AddCashMovement` + the request paid, one transaction). The paid out also goes up with
   the cash movements (Day Reports).
3. **Back office** (the till sends it up at once): `z_sp_TillPayRequestsPaid` adds a **PAYMENT** row (credit = the
   cash, date = the till's date, remark "Cash at till T01 (paid out N, request N) - …") and settles the bills: the
   returns ticked first (what is still left on each), then the cash, **oldest bill first**, each bill no more than its
   ticked amount / what is open. Less cash than bills − returns → the rest stays open on the last bills. The request
   becomes Paid (till, cashier, time, the PAYMENT ref). A resend is skipped (`z_tb_TillPayReceipt`); a request paid
   twice (two tills before a sync, or after a cancel) gets one more PAYMENT row "PAID AGAIN - check", not set against
   bills — the balance stays right.

| Method | Route | Notes |
|---|---|---|
| GET | `api/SupplierLedger/TillPay?suppId=&status=` | requests, newest first (`refs`, `billsAmount`, `returnsAmount`, paid details) |
| POST | `api/SupplierLedger/TillPay` | `{ suppId, terminalId (null = any), amount, remark, lines: [{ ledgerId, amount }] }` |
| POST | `api/SupplierLedger/TillPay/{id}/Cancel` | waiting only |
| GET | `api/Sync/TillPayRequests?terminalId=` | till: what it may pay now |
| POST | `api/Sync/TillPayRequests` | till: `{ terminalId, rows: [{ requestId, moveId, zNo, amount, cashierId, paidAt }] }` → `{ received }` |

Supplier Ledger page (same change): the supplier search is in the title row, the summary is one row of small tiles
(purchase, paid, balance, overdue, due in 7 days, open bills, returns, days to pay, not set against a bill), the charts
open with **Charts**, the date filter is tighter.

---

## 7. Status values
| Where | Values |
|---|---|
| `z_tb_TempPurchaseSummary.Status` | 0/1 as before, **2 = posted to stock** (`Meta.PurchasePostedStatus`) |
| `z_tb_ZReport.Status` | 2 received, 3 reconciled, 4 mismatch |
| `z_tb_StockTake.Status` / `z_tb_StockTakeSheet.Status` | 1 counting, 2 posted, 9 cancelled / 1 open, 2 done (§6.18) |
| `z_tb_SupplierLedger.Type` | 1 PURCHASE (bill, debit), 2 PAYMENT (credit), 3 RETURN (credit); a bill is Open / Part paid / Paid by its allocations (§6.19) |
| `zf_tb_ZReport.Status` | 0 open, 1 closed, 2 submitted, 3 reconciled, 4 mismatch |
| Invoice `InvType` / `Status` | 1 sale, 2 refund / 1 completed, 9 voided |
| Invoice `PriceType` | 1 retail, 2 = has wholesale line(s) |
| Invoice line `PriceType` | 1 retail, 2 wholesale price on this line |
| Payment `PayType` | 1 cash, 2 card, 3 credit, 4 voucher, 5 bank transfer, 6 cheque (§6.15) |
| `zf_tb_SuspendedBill.Status` | 1 suspended, 2 recalled, 9 cancelled |
| `zf_tb_DrawerLog.Kind` | 1 after a cash bill, 2 No Sale, 3 opening cash, 4 paid in, 5 paid out |
| `zf_tb_CashMovement` `Kind` / `Status` | 1 opening cash, 2 paid in, 3 paid out / 1 active, 9 replaced |
| `z_tb_ExportLog.Status` | 1 written, 9 failed |
| `z_tb_SalesDoc` `DocType` / `Status` | 1 quotation, 2 invoice / 1 open, 2 invoiced (quotation), 9 cancelled |
| `z_tb_Customer.Status` | 1 active, 0 deleted |
| `z_tb_User` `RoleId` / `Status` | 1 Admin, 2 Back office, 3 Cashier / 1 active, 0 disabled |

---

## 8. Known gaps / TODO
- [ ] **Security:** the till sync routes (`api/Sync/Items|StockBalances|PriceLinks|Invoices|ZReport`) are still open
  (`[AllowAnonymous]`, tills have no user token). Only `api/Sync/Cashiers` needs the shared `Sync:TerminalKey`. Give them
  the same key (or a per-terminal key) before going live. The rest of the API is behind sign-in once `Auth:Enforce` is on (§6.12).
- [ ] **Sign-in:** the `userId` fields that pages send in request bodies are still trusted as sent; with sign-in on, the
  server could take the user from the token instead.
- [ ] **Refund against a bill (§6.16):** works only on the till that made the bill, and the back office does not get
  `RefInvoiceNo`. Refunding at any till needs a bill lookup + "already refunded" count on the back office (online only).
- [ ] **Till app:** the `zf_` database is ready, but the cashier program (billing screen + background sync job) still has to be built. It needs a local service/app that talks to the `zf_` db — a pure web page can't work offline against SQL.
- [ ] **Item delete:** `DeleteItemzAsync` hard-deletes. Tills never hear about deletes, and an item with stock history loses its name on reports. Prefer `Status = 0` (inactive) — tills already get `Status` and `zf_sp_FindItem` ignores inactive items.
- [ ] **Location code:** `z_tb_System.LocaId` is `'01'` but everything else uses `LocationId = 1`. `z_sp_SaveStockAdjustment` maps `1 → '01'`. Existing GRN/PRN code still hard-codes `"01"`.
- [ ] **Old stock tables:** `z_tb_Stock_Temp` / `tb_*` stock logic (`StocksController`) is untouched and separate from this ledger. Decide when to switch reports over.
- [ ] **Opening stock:** load current stock once as an adjustment (reason 7, count mode) before going live, or the ledger starts at 0.
- [ ] `z_tb_TempPurchaseSummary` GetAll/Search (GRN screen) don't filter `Type`, so PRNs show there too.

---

## 9. How it was tested (2026-09-30)
- SQL, inside a rolled-back transaction on easyway: GRN post, PRN post, double-post refused,
  count + quantity adjustment, invoice upload + resend (Duplicate), Z mismatch → missing invoice
  listed → late invoice auto-reconciles, balance = SUM(ledger).
- `zf_` script + scenario on a throw-away database (created and dropped).
- Every new API endpoint called against a running build; test rows removed afterwards and
  `ADJNO` reset to 0. The stock tables on easyway are empty.
