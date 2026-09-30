using Microsoft.EntityFrameworkCore;
using Microsoft.OpenApi.Models;
using ItemApi.Data;
using ItemApi.Models;
using ItemApi.Repositories;
using ItemApi.Service;
using Serilog;
using ItemApi.Utility;
using ItemApi.Interface;
using Microsoft.AspNetCore.Http.Features;

var builder = WebApplication.CreateBuilder(args);


// Configure Serilog
Log.Logger = new LoggerConfiguration()
    .ReadFrom.Configuration(builder.Configuration)
    .Enrich.FromLogContext()
     .WriteTo.Console()
     //.WriteTo.File("Logs/log-.txt", rollingInterval: RollingInterval.Day)
    .CreateLogger();

builder.Host.UseSerilog();



// Add services to the container.
// Two DbContexts, matching the two actual connection strings this app talks to:
//  - AppDbContext: every entity on "DefaultConnection" (was 19 separate one-DbSet DbContexts).
//  - PosDbContext: the one entity that lives on the separate "PosConnection" database.
builder.Services.AddDbContext<AppDbContext>(options =>
    options.UseSqlServer(builder.Configuration.GetConnectionString("DefaultConnection")));

builder.Services.AddDbContext<PosDbContext>(options =>
    options.UseSqlServer(builder.Configuration.GetConnectionString("PosConnection")));

builder.Services.Configure<AppSettings>(builder.Configuration.GetSection("AppSettings"));

builder.Services.AddScoped<IGoogleSheetService, GoogleSheetService>();



builder.Services.AddScoped<IItemRepository, ItemRepository>();
builder.Services.AddScoped<IStockRepository, StockRepository>();
builder.Services.AddScoped<IReturnRepository, ReturnRepository>();
builder.Services.AddScoped<ISupplierRepository, SupplierRepository>();
builder.Services.AddScoped<IGrnTempRepository, GrnTempRepository>();
builder.Services.AddScoped<IPurchaseRepository, PurchaseRepository>();
builder.Services.AddScoped<StockService>();

builder.Services.AddScoped<IPosStockRepository, PosStockRepository>();
builder.Services.AddScoped<IPosCountedStockRepository, PosCountedStockRepository>();

builder.Services.AddScoped<IFileLocationRepository, FileLocationRepository>();

builder.Services.AddScoped<IChequeCreateRepository, ChequeCreateRepository>();

builder.Services.AddScoped<IPayeeRepository, PayeeRepository>();
builder.Services.AddScoped<ISupplierzRepository, SupplierzRepository>();
builder.Services.AddScoped<ICategoryRepository, CategoryRepository>();
builder.Services.AddScoped<ILocationRepository, LocationRepository>();
builder.Services.AddScoped<ISubCategoryRepository, SubCategoryRepository>();
builder.Services.AddScoped<IUnitRepository, UnitRepository>();
builder.Services.AddScoped<IItemzRepository, ItemzRepository>();
builder.Services.AddScoped<ITempPurchaseSummaryRepository, TempPurchaseSummaryRepository>();
builder.Services.AddScoped<ITempPurchaseRepository, TempPurchaseRepository>();
builder.Services.AddScoped<ITempPurchaseReturnSummaryRepository, TempPurchaseReturnSummaryRepository>();
builder.Services.AddScoped<ITempPurchaseReturnRepository, TempPurchaseReturnRepository>();
builder.Services.AddScoped<IStockLedgerRepository, StockLedgerRepository>();
builder.Services.AddScoped<IStockAdjustmentRepository, StockAdjustmentRepository>();
builder.Services.AddScoped<ISyncRepository, SyncRepository>();
builder.Services.AddScoped<ISystemRepository, SystemRepository>();
builder.Services.AddScoped<ISupplierLedgerRepository, SupplierLedgerRepository>();

builder.Services.AddScoped<ISalaryConfigRepository, SalaryConfigRepository>();
builder.Services.AddScoped<ISalaryEmployeeRepository, SalaryEmployeeRepository>();
builder.Services.AddScoped<ISalaryHolidayRepository, SalaryHolidayRepository>();
builder.Services.AddScoped<ISalaryAttendanceRepository, SalaryAttendanceRepository>();
builder.Services.AddScoped<ISalaryAdvanceRepository, SalaryAdvanceRepository>();
builder.Services.AddScoped<ISalaryPayslipRepository, SalaryPayslipRepository>();
builder.Services.AddScoped<ISalaryCalculationService, SalaryCalculationService>();

// Register the service
builder.Services.AddControllers();


builder.Services.AddCors(options =>
{
    options.AddPolicy("AllowAllOrigins",
        builder =>
        {
            builder.AllowAnyOrigin().AllowAnyMethod().AllowAnyHeader();
        });
});

builder.Services.Configure<FormOptions>(options =>
{
    options.MultipartBodyLengthLimit = 104857600; // 100MB
});


builder.Services.AddSwaggerGen(c =>
{
    c.SwaggerDoc("v1", new OpenApiInfo { Title = "Item API", Version = "v1" });
});

// Add this alongside your existing AddControllers()
//builder.Services.AddControllers()
//    .AddOData(opt => opt
//        .AddRouteComponents("odata", GetEdmModel())
//        .Select()
//        .Filter()
//        .OrderBy()
//        .SetMaxTop(100)
//        .Count());

//static IEdmModel GetEdmModel()
//{
//    var builder = new ODataConventionModelBuilder();
//    builder.EntitySet<GrnHeader>("Grn"); // your GRN model
//    return builder.GetEdmModel();
//}

var app = builder.Build();

// Configure the HTTP request pipeline.
if (app.Environment.IsDevelopment())
{
    app.UseDeveloperExceptionPage();
    app.UseSwagger();
    app.UseSwaggerUI(c => c.SwaggerEndpoint("/swagger/v1/swagger.json", "Item API V1"));
}
else
{
    app.UseExceptionHandler("/Home/Error");
    app.UseHsts();
}

app.UseHttpsRedirection();

// Use the custom request/response logging middleware
app.UseMiddleware<RequestResponseLoggingMiddleware>();

app.UseRouting();
app.UseCors("AllowAllOrigins");
app.UseAuthorization();



app.MapControllers();

app.Run();

Log.CloseAndFlush();
