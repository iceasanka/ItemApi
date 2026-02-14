namespace ItemApi.Service
{
    using Google.Apis.Auth.OAuth2;
    using Google.Apis.Services;
    using Google.Apis.Sheets.v4;
    using Google.Apis.Sheets.v4.Data;
    using ItemApi.Models;
    using Microsoft.Extensions.Options;

    public class GoogleSheetService : IGoogleSheetService
    {
        private readonly SheetsService _service;
        private readonly string _spreadsheetId = "1S394E29YEWtDKjPQgW5zrdFCfDOrMmid0Z-FXmZvOJw";
        private readonly string _sheetName = "AsankaTemp";
        private readonly AppSettings _appSettings;

        public GoogleSheetService(IWebHostEnvironment env, IOptions<AppSettings> appSettings)
        {
            _appSettings = appSettings.Value;
            var credentialPath = Path.Combine(/*env.ContentRootPath*/_appSettings.Apicre, "peppy-road-357-f3c4409465bf.json");

            var credential = GoogleCredential
                .FromFile(credentialPath)
                .CreateScoped(SheetsService.Scope.Spreadsheets);

            _service = new SheetsService(new BaseClientService.Initializer()
            {
                HttpClientInitializer = credential,
                ApplicationName = "Cheque Sync Service",
            });

        }

        //public async Task InsertOrUpdateChequeAsync(ChequeCreate cheque)
        //{
        //    var range = $"{_sheetName}!A2:D";

        //    var getRequest = _service.Spreadsheets.Values.Get(_spreadsheetId, range);
        //    var getResponse = await getRequest.ExecuteAsync();
        //    var rows = getResponse.Values;

        //    int rowIndex = -1;

        //    if (rows != null)
        //    {
        //        for (int i = 0; i < rows.Count; i++)
        //        {
        //            if (rows[i][0].ToString() == cheque.ChequeId.ToString())
        //            {
        //                rowIndex = i + 2;
        //                break;
        //            }
        //        }
        //    }

        //    var newRow = new List<object>
        //{
        //    cheque.ChequeId,
        //    cheque.SupplierName,
        //    cheque.Amount,
        //    cheque.ChequeDate.ToString("yyyy-MM-dd")
        //};

        //    if (rowIndex > -1)
        //    {
        //        var updateRange = $"{_sheetName}!A{rowIndex}:D{rowIndex}";

        //        var updateRequest = _service.Spreadsheets.Values.Update(
        //            new ValueRange { Values = new List<IList<object>> { newRow } },
        //            _spreadsheetId,
        //            updateRange);

        //        updateRequest.ValueInputOption =
        //            SpreadsheetsResource.ValuesResource.UpdateRequest.ValueInputOptionEnum.RAW;

        //        await updateRequest.ExecuteAsync();
        //    }
        //    else
        //    {
        //        var appendRequest = _service.Spreadsheets.Values.Append(
        //            new ValueRange { Values = new List<IList<object>> { newRow } },
        //            _spreadsheetId,
        //            range);

        //        appendRequest.ValueInputOption =
        //            SpreadsheetsResource.ValuesResource.AppendRequest.ValueInputOptionEnum.RAW;

        //        await appendRequest.ExecuteAsync();
        //    }
        //}

        public async Task InsertOrUpdateChequeAsync(ChequeCreate cheque)
        {
            string sheetName = _sheetName;

            // 1️⃣ Read the entire sheet
            var range = $"{sheetName}!A1:N1000"; // adjust max rows if needed
            var getRequest = _service.Spreadsheets.Values.Get(_spreadsheetId, range);
            var response = await getRequest.ExecuteAsync();
            var rows = response.Values;

            if (rows == null || rows.Count == 0)
                throw new Exception("Sheet is empty");

            // 2️⃣ Find the month block in Column A
            int monthStartRowIndex = -1;
            for (int i = 0; i < rows.Count; i++)
            {
                if (rows[i].Count > 0 && DateTime.TryParse(rows[i][0].ToString(), out DateTime rowDate))
                {
                    if (rowDate.Month == cheque.ChequeDate.Month && rowDate.Year == cheque.ChequeDate.Year)
                    {
                        monthStartRowIndex = i;
                        break;
                    }
                }
            }

            if (monthStartRowIndex == -1)
                throw new Exception($"Month {cheque.ChequeDate:MMMM yyyy} not found in sheet");

            // 3️⃣ Table headers are the next row after month label
            int headerRowIndex = monthStartRowIndex + 1;
            int dataStartRowIndex = headerRowIndex + 1;

            // 4️⃣ Column indexes (relative to sheet)
            int dateColIndex = 1;       // Column B → Date
            int supplierColIndex = 5;   // Column F → Sup_Name
            var chequeColIndexes = Enumerable.Range(6, 8).ToList(); // Columns G→N → chq_1 → chq_8

            // 5️⃣ Find the row corresponding to the cheque date
            int targetRowIndex = -1;
            for (int i = dataStartRowIndex; i < rows.Count; i++)
            {
                if (rows[i].Count > dateColIndex)
                {
                    if (int.TryParse(rows[i][dateColIndex].ToString(), out int day))
                    {
                        if (day == cheque.ChequeDate.Day)
                        {
                            targetRowIndex = i;
                            break;
                        }
                    }
                }
            }

            if (targetRowIndex == -1)
                throw new Exception($"Date {cheque.ChequeDate:dd} not found in month block");

            var row = rows[targetRowIndex];

            // 6️⃣ Update Supplier Name (append if exists)
            string existingSupplier = row.Count > supplierColIndex ? row[supplierColIndex]?.ToString() : "";
            string newSupplier = string.IsNullOrEmpty(existingSupplier)
                ? cheque.SupplierName
                : existingSupplier + ", " + cheque.SupplierName;

            var supplierRange = $"{sheetName}!{GetColumnLetter(supplierColIndex + 1)}{targetRowIndex + 1}";
            await UpdateCellAsync(supplierRange, newSupplier);

            // 7️⃣ Insert first empty cheque column
            foreach (var colIdx in chequeColIndexes)
            {
                bool isEmpty = row.Count <= colIdx || string.IsNullOrEmpty(row[colIdx]?.ToString());
                if (isEmpty)
                {
                    var cellRange = $"{sheetName}!{GetColumnLetter(colIdx + 1)}{targetRowIndex + 1}";
                    await UpdateCellAsync(cellRange, cheque.Amount.ToString("N0")); // formatted with thousand separators
                    break;
                }
            }
        }

        // Helper method to update a single cell
        private async Task UpdateCellAsync(string range, string value)
        {
            var valueRange = new ValueRange
            {
                Values = new List<IList<object>> { new List<object> { value } }
            };
            var updateRequest = _service.Spreadsheets.Values.Update(valueRange, _spreadsheetId, range);
            updateRequest.ValueInputOption = SpreadsheetsResource.ValuesResource.UpdateRequest.ValueInputOptionEnum.USERENTERED;
            await updateRequest.ExecuteAsync();
        }

        // Helper method to convert column index to letter (1 = A)
        private string GetColumnLetter(int columnNumber)
        {
            string columnLetter = "";
            while (columnNumber > 0)
            {
                int modulo = (columnNumber - 1) % 26;
                columnLetter = Convert.ToChar(65 + modulo) + columnLetter;
                columnNumber = (columnNumber - modulo) / 26;
            }
            return columnLetter;
        }



    }

}
