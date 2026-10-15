# Update scripts for deployed databases

Production (`easyway`) and the tills (`z_pos_fnt_db`) were deployed on 2026-10-10. Every database change after that
gets an update script here, to run directly on the deployed databases. The full scripts (`01_` … `07_`) get the same
change, so a new install is still complete.

Rules for every script in this folder:
- one number per change: `U###_BackOffice_<what>.sql` (run on easyway) and / or `U###_Till_<what>.sql` (run on each till)
- **SQL Server 2008 R2**: no `THROW` (procs that raise errors use the `RAISERROR` + TRY/CATCH form of
  `DBScript/Sql2008.ps1`), nothing from `Assert-Sql2008`'s list. Plain ASCII text.
- safe to run again; stops with a message when run on the wrong database
- run in number order; back office before tills unless the script header says otherwise

```
sqlcmd -S <server> -d easyway -E -I -b -i U001_BackOffice_ScaleSticker.sql
sqlcmd -S .\SQLEXPRESS -d z_pos_fnt_db -E -I -b -i U001_Till_ScaleSticker.sql
```

| No | Date | Back office | Till | Needs | What |
|---|---|---|---|---|---|
| U001 | 2026-10-12 | `U001_BackOffice_ScaleSticker.sql` | `U001_Till_ScaleSticker.sql` | new ItemApi + new TillService | scale sticker barcodes: unit code goes to the tills, `zf_sp_FindItem` reads the weight (StockSystem.md §6.14) |
| U002 | 2026-10-12 | - | `U002_Till_XReport.sql` | new TillService (run the script first; the old TillService keeps working after it) | X report: new read-only procedure `zf_sp_GetXReport` - the open Z's totals without closing it (StockSystem.md §6.8) |
| U003 | 2026-10-12 | `U003_BackOffice_PayTypes.sql` | `U003_Till_PayTypes.sql` | new ItemApi (run the back office script BEFORE it) + new TillService (run the till script before it) | bank transfer (PayType 5) and cheque (PayType 6): `BankAmount` / `ChequeAmount` on the Z, both part of `OtherAmount`. Replaces U002's `zf_sp_GetXReport` (StockSystem.md §6.15) |
| U004 | 2026-10-13 | - | `U004_Till_RefundBill.sql` | new TillService (run the script first; the old TillService keeps working after it) | refund against the original bill: `zf_tb_Invoice.RefInvoiceNo`, `zf_tb_InvoiceItem.RefLineNum`, type `zf_tt_RefundLine`, procedures `zf_sp_GetInvoiceForRefund` / `zf_sp_SaveBillRefund`; `zf_sp_GetInvoiceForPrint` returns `RefInvoiceNo`. The bill number barcode on the receipt needs no db change (StockSystem.md §6.16) |
| U005 | 2026-10-13 | `U005_BackOffice_TransferPriceLinks.sql` | - | nothing (no ItemApi / TillService change) | one-time copy of the old price links: creates `z_sp_TransferOldPriceLinks` (active `tb_PriceLink` rows → `z_tb_ItemPriceLink`; a link whose item is not in `z_tb_Item` is not copied, and one already there is set to Status 0). The file changes no data - run `EXEC dbo.z_sp_TransferOldPriceLinks @DryRun = 1;` then `@DryRun = 0`. Tills get the links on their next download (StockSystem.md §6.13) |
| U006 | 2026-10-14 | `U006_BackOffice_StockTake.sql` | - | new ItemApi (run the script BEFORE it) | stock take: tables `z_tb_StockTake` / `z_tb_StockTakeSheet` / `z_tb_StockTakeItem`, type `z_tt_StockTakeCount`, procedures `z_sp_CreateStockTake`, `z_sp_AddStockTakeSheet`, `z_sp_AddStockTakeItem`, `z_sp_SaveStockTakeCounts`, `z_sp_GetStockTakeVariance`, `z_sp_PostStockTake` (posts through `z_sp_SaveStockAdjustment`), `z_sp_CancelStockTake`. Full script: `14_BackOffice_StockTake.sql` (StockSystem.md §6.18) |
| U007 | 2026-10-14 | `U007_BackOffice_SupplierPayments.sql` | - | new ItemApi (run the script BEFORE it) | supplier bills -> cheques: `z_tb_Supplier.PayeeName` / `CreditDays` / `LedgerSeq` (payees merged into suppliers - the script copies `z_tb_Payee` names by supplier name and lists the ones it could not match), `z_tb_SupplierLedger.InvoiceNo` / `DueDate` / `ChequeId`, table `z_tb_SupplierPaymentAlloc` (with `ChequeId`; a cheque can pay a bill less returns - the deduction is set against returns), `z_tb_WrittenCheque.SuppId` / `LedgerId` / `PayeeName` (`PayeeId` may be NULL), type `z_tt_SupplierAlloc` (LedgerId, Amount, Deduction), procedures `z_sp_SaveSupplierLedger`, `z_sp_DeleteSupplierLedger`, `z_sp_AllocateSupplierPayment`, `z_sp_NextSupplierRef`, `z_sp_GetSupplierInvoices`, `z_sp_GetSupplierPaymentsDue`, `z_sp_LinkWrittenCheque`, `z_sp_UnlinkWrittenCheque`; replaces `z_Sp_GetSupplierLedger` / `z_sp_GetSupplierLedger_ByDate` (the old ones need SQL 2012+). Full script: `15_BackOffice_SupplierPayments.sql` (StockSystem.md §6.19) |
| U008 | 2026-10-15 | `U008_BackOffice_PayeeToSupplier.sql` | - | U007 (run it first); no ItemApi / TillService change | one-time move of the payees into the suppliers: creates `z_sp_TransferPayeesToSuppliers`. The file changes no data - run `EXEC dbo.z_sp_TransferPayeesToSuppliers @DryRun = 1;` then `@DryRun = 0`. A payee's supplier name with no supplier becomes a NEW supplier: `SuppCode` = first 4 letters of the name + 001, 002 ... (`Ceylon Biscuits Ltd` -> `CEYL001`), `PayeeName`, phone / account / bank from the payee (empty, never NULL - each run also turns NULLs in those supplier columns into empty: the old ItemApi cannot read them), Status from IsActive. A supplier that exists gets the payee name when it has none. Old cheques get `SuppId` / `PayeeName` (not added to the ledger). `z_tb_Payee` is not changed. Second result set lists every payee and what was done (StockSystem.md §6.19) |
| U009 | 2026-10-15 | `U009_BackOffice_ExportSetting.sql` | - | nothing (no ItemApi / TillService change) | Exports page showed "No exports set up" on production: adds the `SCALE` row to `z_tb_ExportSetting` when missing (and the export tables when missing - same as `05_BackOffice_Export.sql`). An existing row is not changed. Then set the folder on the Exports page (StockSystem.md §6.10) |
