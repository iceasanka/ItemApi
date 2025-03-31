using ItemApi.Models;
using System.Drawing.Printing;
using System.Runtime.InteropServices;
using System;
using System.Drawing;
using Serilog;
using System.Text.Json;

namespace ItemApi.Service
{
    public class PrinterService
    {
        private const string PrinterName = "PegasusPR8003"; // Replace with the printer name as configured on the system

        public void PrintProcessedData(List<ReturnItem> processedItems)
        {
            // Prepare the text to print
            var printText = FormatProcessedData(processedItems);

            // Set up the printer
            PrintDocument printDocument = new PrintDocument();
            printDocument.PrinterSettings.PrinterName = PrinterName;

            printDocument.PrintPage += (sender, e) =>
            {
                e.Graphics.DrawString(printText, new Font("Courier New", 10, FontStyle.Bold), Brushes.Black, new PointF(0, 0));
            };

            // Print the document
            try
            {
                printDocument.Print();
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex}");
                throw;
            }
        }

       

        private string FormatProcessedData(List<ReturnItem> processedItems)
        {
            // Header section
            string header = "IRESHA FOOD CITY-Return Items\n";
            // Header section
            header += "----------------------------\n";

            // Column Headers
            header += "ItemCode   C.Price   Qty   Netv\n";
            header += "----------------------------\n";

            // Body section
            string body = "";
            decimal subTotal = 0;
            int itemCount = 1; // Counter for item numbering

            foreach (var item in processedItems)
            {
                // Calculate net value
                decimal netValue = item.Cost_Price  * (decimal)item.Qty;
                subTotal += netValue;

                // Append item details
                body += $"{itemCount++} - {item.Descrip}\n"; // Description with numbering
                body += $"{item.Item_Code,-12} {item.Cost_Price,-5} {item.Qty,-5} {netValue,-15}\n";
            }

            // Footer section
            string footer = "----------------------------\n";
            footer += $"Sub Total: {subTotal}\n";
            footer += $"Date: {DateTime.Now:yyyy-MM-dd}\n";
            footer += $"Time: {DateTime.Now:HH:mm:ss}\n";
            footer += "----------------------------\n";
            footer += "Thank you!";

            // Combine all sections
            return header + body + footer;



        }

        public void PrintCombinedData(List<Dictionary<string, object>> cashData, decimal cashTotal,
                                     List<Dictionary<string, object>> creditData, decimal creditTotal,
                                     List<Dictionary<string, object>> debitData, decimal debitTotal)
        {
            // Format the data as three tables
            string printContent = FormatCombinedData(cashData, cashTotal, creditData, creditTotal, debitData, debitTotal);

            // Set up the printer
            PrintDocument printDocument = new PrintDocument();
            printDocument.PrinterSettings.PrinterName = PrinterName;

            // Determine the paper size dynamically
            PaperSize paperSize = CalculatePaperSize(printContent);
            printDocument.DefaultPageSettings.PaperSize = paperSize;

            // Print event handler
            printDocument.PrintPage += (sender, e) =>
            {
                //e.Graphics.DrawString(printText, new Font("Courier New", 10, FontStyle.Bold), Brushes.Black, new PointF(0, 0));
                e.Graphics.DrawString(printContent, new Font("Courier New", 10, FontStyle.Bold), Brushes.Black, new PointF(0, 0));
            };

            // Print the document
            try
            {
                printDocument.Print();
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex}");
                throw;
            }
        }

        // Method to format the combined data
        private string FormatCombinedData(List<Dictionary<string, object>> cashData, decimal cashTotal,
                                  List<Dictionary<string, object>> creditData, decimal creditTotal,
                                  List<Dictionary<string, object>> debitData, decimal debitTotal)
        {
            string content = "";

            // Cash Breakdown Section
            content += "========== TOTAL CASH ==========\n";
            content += $"{"Cash",-10}{"Qty",-10}{"Amount",-15}\n";
            content += "------------------------------------------\n";

            foreach (var row in cashData)
            {
                // Extract and convert values from JsonElement
                decimal cash = row["cash"] is JsonElement cashElement ? cashElement.GetDecimal() : 0;
                int qty = row["qty"] is JsonElement qtyElement ? qtyElement.GetInt32() : 0;
                decimal amount = cash * qty;

                content += $"{cash,-10}{qty,-10}{amount,-15}\n";
            }
            content += $"------------------------------------------\n";
            content += $"Total: {cashTotal}\n\n";

            // Credit Table Section
            content += "========== CASH IN ==========\n";
            content += $"\n";
            content += $"\n";
            content += $"{"Description",-20}{"Amount",-15}\n";
            content += "------------------------------------------\n";
            foreach (var row in creditData)
            {
                string credit = row["credit"] is JsonElement creditElement ? creditElement.GetString() : string.Empty;
                decimal amount = row["amount"] is JsonElement amountElement ? amountElement.GetDecimal() : 0;

                content += $"{credit,-20}{amount,-15}\n";
            }
            content += $"------------------------------------------\n";
            content += $"Total Credit: {creditTotal}\n\n";

            // Debit Table Section
            content += "========== CASH OUT ==========\n";
            content += $"\n";
            content += $"\n";
            content += $"{"Description",-20}{"Amount",-15}\n";
            content += "------------------------------------------\n";
            foreach (var row in debitData)
            {
                string debit = row["debit"] is JsonElement debitElement ? debitElement.GetString() : string.Empty;
                decimal amount = row["amount"] is JsonElement amountElement ? amountElement.GetDecimal() : 0;

                content += $"{debit,-20}{amount,-15}\n";
            }
            content += $"------------------------------------------\n";
            content += $"Total Debit: {debitTotal}\n\n";

            // Final Cash Balance
            decimal totalCashBalance = cashTotal + creditTotal - debitTotal;
            content += $"\n";
            content += $"\n";
            content += $"==========CASH BALANCE ==========\n";
            content += $"\n";
            content += $"\n";
            content += $"Cash Balance: {totalCashBalance}\n";
            content += $"\n";
            content += $"\n";
            content += $"Date: {DateTime.Today.ToString()}\n";
            content += $"                                 \n";
            content += $"                                 \n";
            content += $"                                 \n";

            return content;
        }


        // Method to calculate paper size based on content
        private PaperSize CalculatePaperSize(string content)
        {
            float charWidth = 7f;   // Approximate width of a character in Courier New, 10pt
            float lineHeight = 15f; // Approximate height of a line in Courier New, 10pt

            string[] lines = content.Split('\n');
            int numberOfLines = lines.Length;
            int maxLineLength = 0;

            foreach (string line in lines)
            {
                if (line.Length > maxLineLength)
                    maxLineLength = line.Length;
            }

            int paperWidth = (int)(maxLineLength * charWidth) + 50; // Add padding
            int paperHeight = (int)(numberOfLines * lineHeight) + 50; // Add padding

            return new PaperSize("Custom", paperWidth, paperHeight);
        }
    }

}
