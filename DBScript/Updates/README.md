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
