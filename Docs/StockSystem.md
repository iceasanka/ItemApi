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

`TxnType` (also `Meta.StockTxnType`): **1** GRN (+), **2** PRN (−), **3** Sale (−), **4** Sale refund (+), **5** Adjustment (±), **7** Opening (±).

### Procs
| Proc | Does |
|---|---|
| `z_sp_PostStockMovements` | **the only writer** of ledger + balance. Skips lines already posted. Updates balance with `Qty = Qty + x` (atomic — two tills can't overwrite each other). AvgCost moves on GRN lines only |
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
| `zf_sp_FindItem` | barcode, then RefCode — or `@ItemId`; 2nd result set = the item's active price links |
| `zf_sp_SearchItems` | cashier search by name: every word in `Descrip` or `Inv_Descrip`, max 50 (needs SQL Server 2016+) |
| `zf_sp_GetUnsyncedInvoices` / `zf_sp_GetInvoicesByNo` / `zf_sp_MarkInvoicesSynced` | upload queue |
| `zf_sp_CloseZ` / `zf_sp_GetZForSubmit` / `zf_sp_SetZStatus` | day end |
| `zf_sp_UpsertItems` / `zf_sp_UpsertStockBalance` / `zf_sp_UpsertPriceLinks` | apply downloads |

Invoice numbers are made **on the till** (`TerminalCode-8 digits`) so two tills can never clash
while offline — the central `z_tb_System` counters can't be used offline.

---

## 5. API

### Stock (back office)
| Method | Route | Notes |
|---|---|---|
| POST | `api/TempPurchaseSummary/Commit/{grnNo}?userId=` | GRN → stock (+). 400 if not found / already posted / no qty |
| POST | `api/TempPurchaseReturnSummary/Commit/{prnNo}?userId=` | PRN → stock (−) |
| GET | `api/StockLedger/Balance/{itemId}` | one item's stock |
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

---

## 7. Status values
| Where | Values |
|---|---|
| `z_tb_TempPurchaseSummary.Status` | 0/1 as before, **2 = posted to stock** (`Meta.PurchasePostedStatus`) |
| `z_tb_ZReport.Status` | 2 received, 3 reconciled, 4 mismatch |
| `zf_tb_ZReport.Status` | 0 open, 1 closed, 2 submitted, 3 reconciled, 4 mismatch |
| Invoice `InvType` / `Status` | 1 sale, 2 refund / 1 completed, 9 voided |
| Invoice `PriceType` | 1 retail, 2 = has wholesale line(s) |
| Invoice line `PriceType` | 1 retail, 2 wholesale price on this line |
| Payment `PayType` | 1 cash, 2 card, 3 credit, 4 voucher |
| `zf_tb_SuspendedBill.Status` | 1 suspended, 2 recalled, 9 cancelled |

---

## 8. Known gaps / TODO
- [ ] **Security:** `api/Sync/*` is open like the rest of the API. Add a per-terminal API key header before going live.
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
