# Data fixes

One-time scripts that correct or move **data** on a deployed database (no table / procedure change - those go in
`../Updates`). Each one is kept here so we know what was changed on production, when and why.

Rules for every script in this folder:
- one number per fix: `F###_BackOffice_<what>.sql` (run on easyway) and / or `F###_Till_<what>.sql` (run on a till)
- **SQL Server 2008 R2** (no `THROW`, `IIF`, `FORMAT`, `CONCAT`; `DECLARE` and `SET` on separate lines). Plain ASCII.
  Keep lines short - long lines get cut when copied from a terminal.
- `@DryRun = 1` at the top: shows what would change and changes nothing; `0` does it, in one transaction
- stops with a message, changing nothing, when the data is not what it expects
- header says what was wrong, what the script does, and where / when it was run

```
sqlcmd -S <server> -d easyway -E -I -b -i F001_BackOffice_NAND001_LedgerAllocations.sql
```

| No | Date | Script | Run on | What |
|---|---|---|---|---|
| F001 | 2026-10-26 | `F001_BackOffice_NAND001_LedgerAllocations.sql` | production 2026-10-26 | Supplier Ledger, Nandana (NAND001) restarted at 0: the cheque payments not set against a bill (1,244,190.00) set against the hand-made purchase "TO get 0", so the page shows no open bill and nothing "Not set against a bill". Only adds `z_tb_SupplierPaymentAlloc` rows |
| F002 | 2026-10-28 | `F002_BackOffice_MinusStockToZero.sql` | not run yet | Opening stock was never loaded, so 1,512 items were below 0 (about -11,700 qty) and their GRNs made no cost batch (U026: a GRN fills the minus first) - no new cost, no price link. Posts ONE stock adjustment through `z_sp_SaveStockAdjustment` (reason 7 Opening stock, quantity mode, user `F002`) that brings every item below 0 up to 0; items above 0 and items no longer in `z_tb_Item` are not touched. Run after U026, then `z_sp_RebuildStockBatches @DryRun = 0`. Dev dry run 2026-10-28: 18 items, +67 |
| F003 | 2026-11-03 | `F003_Till_ZDateFirstBill.sql` (each till) + `F003_BackOffice_ZDateFirstBill.sql` (easyway) | not run yet (dev 2026-11-03: T01 Z10, Z12) | A Z was dated the day it opened, so the Z opened right after a night day end got that night's date (T01 Z12: 2 Nov, its bills 3 Nov) and the Tills page / Day Reports showed it under the wrong day. Sets `BusinessDate` = the date of the Z's first bill on every Z dated before it (till: closed Zs only; back office: from the uploaded bills). Totals and status not changed. Run both (a reconciled Z is not taken again from the till). U044 stops new ones |
