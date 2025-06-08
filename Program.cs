using Microsoft.AspNetCore.Builder;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.EntityFrameworkCore;
using Microsoft.OpenApi.Models;
using ItemApi.Data;
using ItemApi.Models;
using ItemApi.Repositories;
using ItemApi.Service;
using Serilog;
using ItemApi.Utility;
using Microsoft.Extensions.Configuration;
using ItemApi.Interface;
using ItemApi.Controllers;
using Microsoft.Extensions.Options;

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
builder.Services.AddDbContext<ItemContext>(options =>
    options.UseSqlServer(builder.Configuration.GetConnectionString("DefaultConnection")));

builder.Services.AddDbContext<StockContext>(options =>
    options.UseSqlServer(builder.Configuration.GetConnectionString("DefaultConnection")));

builder.Services.AddDbContext<ReturnContext>(options =>
    options.UseSqlServer(builder.Configuration.GetConnectionString("DefaultConnection")));

builder.Services.AddDbContext<SupplierContext>(options =>
    options.UseSqlServer(builder.Configuration.GetConnectionString("DefaultConnection")));

builder.Services.AddDbContext<PosCountedStockContext>(options =>
    options.UseSqlServer(builder.Configuration.GetConnectionString("DefaultConnection")));

builder.Services.AddDbContext<GrnTempContext>(options =>
    options.UseSqlServer(builder.Configuration.GetConnectionString("DefaultConnection")));

builder.Services.AddDbContext<PurchaseContext>(options =>
    options.UseSqlServer(builder.Configuration.GetConnectionString("DefaultConnection")));

builder.Services.AddDbContext<PosStockContext>(options =>
    options.UseSqlServer(builder.Configuration.GetConnectionString("PosConnection")));

builder.Services.Configure<AppSettings>(builder.Configuration.GetSection("AppSettings"));



builder.Services.AddScoped<IItemRepository, ItemRepository>();
builder.Services.AddScoped<IStockRepository, StockRepository>();
builder.Services.AddScoped<IReturnRepository, ReturnRepository>();
builder.Services.AddScoped<ISupplierRepository, SupplierRepository>();
builder.Services.AddScoped<IGrnTempRepository, GrnTempRepository>();
builder.Services.AddScoped<IPurchaseRepository, PurchaseRepository>();
builder.Services.AddScoped<StockService>();

builder.Services.AddScoped<IPosStockRepository, PosStockRepository>();
builder.Services.AddScoped<IPosCountedStockRepository, PosCountedStockRepository>();

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

builder.Services.AddSwaggerGen(c =>
{
    c.SwaggerDoc("v1", new OpenApiInfo { Title = "Item API", Version = "v1" });
});

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
