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
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Authorization;

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
// Production easyway runs on SQL Server 2008 R2 (compatibility level 100): EF must not generate newer SQL
// (OPENJSON for list.Contains, ...). OFFSET/FETCH paging is avoided in the repositories (Take, then skip in memory).
builder.Services.AddDbContext<AppDbContext>(options =>
    options.UseSqlServer(builder.Configuration.GetConnectionString("DefaultConnection"), sql => sql.UseCompatibilityLevel(100)));

builder.Services.AddDbContext<PosDbContext>(options =>
    options.UseSqlServer(builder.Configuration.GetConnectionString("PosConnection"), sql => sql.UseCompatibilityLevel(100)));

builder.Services.Configure<AppSettings>(builder.Configuration.GetSection("AppSettings"));

// ─── Sign-in (Docs/StockSystem.md §6.12) ───
// Tokens from api/Auth/Login, sent as "Authorization: Bearer <token>". Auth:Enforce = true → every route needs a signed-in
// Admin / Back office user except [AllowAnonymous] ones (sign-in, till sync, logo). false = routes stay open while the
// web pages are switched over; api/Users is admin-only either way.
var authKey = AuthTokenService.LoadKey(builder.Configuration);
var authEnforced = builder.Configuration.GetValue("Auth:Enforce", false);
builder.Services.AddSingleton(new AuthTokenService(authKey, builder.Configuration.GetValue("Auth:TokenHours", 12)));
builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(o =>
    {
        o.MapInboundClaims = false;
        o.TokenValidationParameters = AuthTokenService.Validation(authKey);
        o.Events = new JwtBearerEvents
        {
            // SignalR (live sales on the home page) can't send headers over WebSockets — it sends ?access_token=
            OnMessageReceived = ctx =>
            {
                var token = ctx.Request.Query["access_token"].ToString();
                if (token.Length > 0 && ctx.HttpContext.Request.Path.StartsWithSegments("/hubs"))
                    ctx.Token = token;
                return Task.CompletedTask;
            },
            // a disabled user, or one whose role changed, is signed out at once — not when the token expires
            OnTokenValidated = async ctx =>
            {
                var userId = AuthTokenService.UserId(ctx.Principal!);
                var roleClaim = ctx.Principal!.FindFirst(AuthTokenService.RoleIdClaim)?.Value;
                var db = ctx.HttpContext.RequestServices.GetRequiredService<AppDbContext>();
                var current = await db.AppUsers.AsNoTracking()
                    .Where(u => u.UserId == userId && u.Status == 1).Select(u => u.RoleId).FirstOrDefaultAsync();
                if (current == null || current.ToString() != roleClaim)
                    ctx.Fail("User is disabled or changed — sign in again.");
            }
        };
    });
builder.Services.AddAuthorization(o =>
{
    if (authEnforced)
        o.FallbackPolicy = new AuthorizationPolicyBuilder()
            .RequireAuthenticatedUser()
            .RequireRole(UserRoles.AdminName, UserRoles.BackOfficeName)
            .Build();
});

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
builder.Services.AddScoped<IDashboardRepository, DashboardRepository>();
builder.Services.AddScoped<IExportRepository, ExportRepository>();
builder.Services.AddScoped<ICustomerRepository, CustomerRepository>();
builder.Services.AddScoped<ISalesDocRepository, SalesDocRepository>();
builder.Services.AddSingleton<SalesDocPdfService>();
builder.Services.AddScoped<IUserRepository, UserRepository>();

// Register the service
builder.Services.AddControllers();
// live sales on the home page: /hubs/sales → "salesChanged" when tills upload bills (Dashboard:LivePush)
builder.Services.AddSignalR();


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
    // "Authorize" button: paste the token from api/Auth/Login
    c.AddSecurityDefinition("Bearer", new OpenApiSecurityScheme
    {
        Type = SecuritySchemeType.Http, Scheme = "bearer", BearerFormat = "JWT", In = ParameterLocation.Header
    });
    c.AddSecurityRequirement(new OpenApiSecurityRequirement
    {
        { new OpenApiSecurityScheme { Reference = new OpenApiReference { Type = ReferenceType.SecurityScheme, Id = "Bearer" } }, Array.Empty<string>() }
    });
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
app.UseAuthentication();
app.UseAuthorization();



app.MapControllers();
app.MapHub<ItemApi.Hubs.SalesHub>(ItemApi.Hubs.SalesHub.Path).RequireCors("AllowAllOrigins");

app.Run();

Log.CloseAndFlush();
