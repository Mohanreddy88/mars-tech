using HrmsApi.Data;
using HrmsApi.Middleware;
using HrmsApi.Platform;
using HrmsApi.Services;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.Tokens;
using Microsoft.OpenApi.Models;
using System.Text;
using System.Threading.RateLimiting;

// Check for command-line utilities
if (args.Length > 0 && args[0] == "generate-hash")
{
    HrmsApi.HashGenerator.GenerateHash();
    return;
}

var builder = WebApplication.CreateBuilder(args);

// ── Railway Environment Variables Override ──────────────
// Railway provides DATABASE_URL directly as environment variable
var databaseUrl = Environment.GetEnvironmentVariable("DATABASE_URL");
if (!string.IsNullOrEmpty(databaseUrl))
{
    // Parse postgresql://user:pass@host:port/db to .NET connection string format
    var match = System.Text.RegularExpressions.Regex.Match(
        databaseUrl, 
        @"postgresql://([^:]+):([^@]+)@([^:]+):(\d+)/(.+)"
    );
    
    if (match.Success)
    {
        var connString = $"Host={match.Groups[3].Value};Port={match.Groups[4].Value};Database={match.Groups[5].Value};Username={match.Groups[1].Value};Password={match.Groups[2].Value};SSL Mode=Require;Trust Server Certificate=true";
        builder.Configuration["ConnectionStrings:DefaultConnection"] = connString;
        builder.Configuration["UsePostgreSQL"] = "true";
    }
}

var jwtSecretKey = Environment.GetEnvironmentVariable("JWT_SECRET_KEY");
if (!string.IsNullOrEmpty(jwtSecretKey))
{
    builder.Configuration["Jwt:Key"] = jwtSecretKey;
}

// Password for the first Super Admin account (created once, on first start with tenancy on)
var superAdminPassword = Environment.GetEnvironmentVariable("SUPERADMIN_PASSWORD");
if (!string.IsNullOrEmpty(superAdminPassword))
{
    builder.Configuration["Platform:SuperAdminPassword"] = superAdminPassword;
}

// ── Resend API config (replaces SMTP — works on Railway) ────────────────
var resendApiKey  = Environment.GetEnvironmentVariable("RESEND_API_KEY");
var resendFrom    = Environment.GetEnvironmentVariable("RESEND_FROM") ?? "onboarding@resend.dev";
var smtpFromName  = Environment.GetEnvironmentVariable("SMTP_FROM_NAME") ?? "HRMS Payroll";

if (!string.IsNullOrEmpty(resendApiKey))
{
    builder.Configuration["Resend:ApiKey"]    = resendApiKey;
    builder.Configuration["Resend:FromEmail"] = resendFrom;
    builder.Configuration["Email:FromName"]   = smtpFromName;
}

// ── SMTP / Brevo Environment Variables Override ──────────────────────────
var smtpHost     = Environment.GetEnvironmentVariable("SMTP_HOST");
var smtpPort     = Environment.GetEnvironmentVariable("SMTP_PORT");
var smtpUser     = Environment.GetEnvironmentVariable("SMTP_USER");
var smtpPassword = Environment.GetEnvironmentVariable("SMTP_PASSWORD");
var smtpFrom     = Environment.GetEnvironmentVariable("SMTP_FROM");
// BREVO_API_KEY = the HTTP API key (xkeysib-...) from Brevo Settings → API Keys
// If set, it takes priority over SMTP_PASSWORD for the HTTP API transport
var brevoApiKey  = Environment.GetEnvironmentVariable("BREVO_API_KEY");

if (!string.IsNullOrEmpty(smtpHost))     builder.Configuration["Email:SmtpHost"]     = smtpHost;
if (!string.IsNullOrEmpty(smtpPort))     builder.Configuration["Email:SmtpPort"]     = smtpPort;
if (!string.IsNullOrEmpty(smtpUser))     builder.Configuration["Email:SmtpUser"]     = smtpUser;
if (!string.IsNullOrEmpty(smtpPassword)) builder.Configuration["Email:SmtpPassword"] = smtpPassword;
if (!string.IsNullOrEmpty(smtpFrom))     builder.Configuration["Email:FromEmail"]    = smtpFrom;
if (!string.IsNullOrEmpty(brevoApiKey))  builder.Configuration["Brevo:ApiKey"]       = brevoApiKey;

// ── Database ────────────────────────────────────────────
var connectionString = builder.Configuration.GetConnectionString("DefaultConnection");
var usePostgres = builder.Configuration.GetValue<bool>("UsePostgreSQL");

// Enable legacy timestamp behaviour globally: Npgsql will accept DateTime with
// Kind=Local or Kind=Unspecified and store them as UTC without throwing.
// This is the safest fix for an existing codebase where every timestamp column
// is 'timestamp with time zone' and all DateTimes should be treated as UTC.
AppContext.SetSwitch("Npgsql.EnableLegacyTimestampBehavior", true);

// ── Companies (tenancy) ─────────────────────────────────
// Tenancy:Enabled=true → each company has its own database, picked from the web address
// (see HrmsApi/Platform). Off → DefaultConnection is the only company, as before.
builder.Services.Configure<TenancyOptions>(builder.Configuration.GetSection("Tenancy"));
var tenancy = builder.Configuration.GetSection("Tenancy").Get<TenancyOptions>() ?? new TenancyOptions();
builder.Services.AddHttpContextAccessor();
builder.Services.AddScoped<ITenantContext, TenantContext>();
builder.Services.AddSingleton<TenantCatalog>();

builder.Services.AddDbContext<HrmsDbContext>((sp, options) =>
{
    // The current company's database (or DefaultConnection when tenancy is off)
    var cs = sp.GetRequiredService<ITenantContext>().ConnectionString;
    if (usePostgres || cs.Contains("postgres", StringComparison.OrdinalIgnoreCase))
    {
        options.UseNpgsql(cs);
    }
    else
    {
        options.UseSqlServer(cs);
    }
});

if (usePostgres || connectionString?.Contains("postgres") == true)
{
    // Master database: list of companies + Super Admin accounts
    builder.Services.AddDbContext<PlatformDbContext>(options =>
        options.UseNpgsql(TenantContext.ForDatabase(connectionString!, tenancy.MasterDatabase)));
}

// Super Admin login: at most 10 attempts per minute per client address
builder.Services.AddRateLimiter(o =>
{
    o.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
    o.AddPolicy("platform-login", ctx => RateLimitPartition.GetFixedWindowLimiter(
        ctx.Request.Headers["X-Forwarded-For"].FirstOrDefault()?.Split(',')[0].Trim()
            ?? ctx.Connection.RemoteIpAddress?.ToString() ?? "unknown",
        _ => new FixedWindowRateLimiterOptions { PermitLimit = 10, Window = TimeSpan.FromMinutes(1) }));
});

// ── JWT Authentication ──────────────────────────────────
var jwtConfig = builder.Configuration.GetSection("Jwt");
var key = Encoding.UTF8.GetBytes(jwtConfig["Key"]!);

builder.Services.AddAuthentication(options =>
{
    options.DefaultAuthenticateScheme = JwtBearerDefaults.AuthenticationScheme;
    options.DefaultChallengeScheme    = JwtBearerDefaults.AuthenticationScheme;
})
.AddJwtBearer(options =>
{
    options.TokenValidationParameters = new TokenValidationParameters
    {
        ValidateIssuer           = true,
        ValidateAudience         = true,
        ValidateLifetime         = true,
        ValidateIssuerSigningKey = true,
        ValidIssuer              = jwtConfig["Issuer"],
        ValidAudience            = jwtConfig["Audience"],
        IssuerSigningKey         = new SymmetricSecurityKey(key),
        ClockSkew                = TimeSpan.Zero
    };
    options.Events = new JwtBearerEvents
    {
        // Browsers can't set headers on a WebSocket: the live-updates hub gets the token in the query string.
        OnMessageReceived = ctx =>
        {
            var accessToken = ctx.Request.Query["access_token"];
            if (!string.IsNullOrEmpty(accessToken) && ctx.HttpContext.Request.Path.StartsWithSegments("/api/hubs"))
                ctx.Token = accessToken;
            return Task.CompletedTask;
        },
        // Every company shares the signing key, so a token is only valid on the site that issued it.
        OnTokenValidated = async ctx =>
        {
            var tenant = ctx.HttpContext.RequestServices.GetRequiredService<ITenantContext>();
            if (tenant.MultiTenant && ctx.Principal?.FindFirst(TokenService.TenantClaim)?.Value != tenant.TokenScope)
            {
                ctx.Fail("This login belongs to a different company.");
                return;
            }

            // One login at a time: a company user's token must carry their current session id.
            // (Super Admin portal logins use the master database and are not limited here.)
            var principal = ctx.Principal;
            if (principal == null || principal.IsInRole(PlatformController.SuperAdminRole)) return;
            if (!int.TryParse(principal.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value, out var userId)) return;

            var db = ctx.HttpContext.RequestServices.GetRequiredService<HrmsDbContext>();
            var current = await db.Users.AsNoTracking()
                .Where(u => u.Id == userId)
                .Select(u => new { u.CurrentSessionId })
                .FirstOrDefaultAsync();
            if (current == null)
            {
                ctx.Fail("User no longer exists.");
                return;
            }
            // No session recorded yet (logged in before this rule existed): allow until the next login.
            if (current.CurrentSessionId != null
                && principal.FindFirst(TokenService.SessionClaim)?.Value != current.CurrentSessionId)
            {
                ctx.HttpContext.Items["SessionReplaced"] = true;
                ctx.Fail("Signed in elsewhere.");
            }
        },
        // Tell the browser why, so it can explain the sign-out instead of showing errors.
        OnChallenge = async ctx =>
        {
            if (ctx.HttpContext.Items.ContainsKey("SessionReplaced"))
            {
                ctx.HandleResponse();
                ctx.Response.StatusCode = StatusCodes.Status401Unauthorized;
                await ctx.Response.WriteAsJsonAsync(new
                {
                    code    = "session_replaced",
                    message = "You were signed out because your account signed in on another device or browser."
                });
            }
        }
    };
});

builder.Services.AddAuthorization();

// ── CORS — allow Angular dev server and production ─────
builder.Services.AddCors(options =>
{
    options.AddPolicy("AllowAngular", policy =>
    {
        // Check if running in production (behind Nginx proxy)
        var isProduction = builder.Environment.IsProduction() || !string.IsNullOrEmpty(Environment.GetEnvironmentVariable("DATABASE_URL"));
        
        if (isProduction)
        {
            // In production (Railway/Nginx), allow ALL origins (*) since Nginx handles the proxy
            policy.SetIsOriginAllowed(_ => true)  // Allow * (any origin)
                  .AllowAnyHeader()
                  .AllowAnyMethod()
                  .AllowCredentials();
        }
        else
        {
            // In development, restrict to localhost Angular dev server
            policy.WithOrigins("http://localhost:4200", "https://localhost:4200")
                  .AllowAnyHeader()
                  .AllowAnyMethod()
                  .AllowCredentials();
        }
    });
});

// ── Services ─────────────────────────────────────────────
builder.Services.AddHttpClient(); // Default HttpClient
builder.Services.AddHttpClient("Brevo", client =>
{
    client.BaseAddress = new Uri("https://api.brevo.com");
    client.Timeout     = TimeSpan.FromSeconds(30);
}); // Named client for Brevo HTTP API
builder.Services.AddScoped<TokenService>();
builder.Services.AddScoped<IEmailService, EmailService>();
builder.Services.AddScoped<IExportService, ExportService>();
builder.Services.AddScoped<IPdfService, PdfService>();
builder.Services.AddScoped<ITimesheetService, TimesheetService>();
builder.Services.AddScoped<ILeaveService, LeaveService>();
builder.Services.AddScoped<IPayrollCalculationService, PayrollCalculationService>();
builder.Services.AddScoped<IAuditService, AuditService>();
builder.Services.AddScoped<ICompanySettingsService, CompanySettingsService>();
builder.Services.AddSingleton<IPushService, PushService>();   // off until Firebase credentials are configured
builder.Services.AddScoped<INotificationService, NotificationService>();
builder.Services.AddScoped<IAccountService, AccountService>();
builder.Services.AddSignalR();                                   // live school messages (/api/hubs/chat)
builder.Services.AddScoped<HrmsApi.Hubs.IChatNotifier, HrmsApi.Hubs.ChatNotifier>();

// Background email queue — singleton hosted service that survives request lifetime
// Controllers inject IEmailQueue and call Enqueue() — returns instantly, no 504
builder.Services.AddSingleton<BackgroundEmailService>();
builder.Services.AddSingleton<IEmailQueue>(sp => sp.GetRequiredService<BackgroundEmailService>());
builder.Services.AddHostedService(sp => sp.GetRequiredService<BackgroundEmailService>());

builder.Services.AddControllers();

// ── Swagger/OpenAPI ───────────────────────────────────────
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(c =>
{
    c.SwaggerDoc("v1", new OpenApiInfo { Title = "HRMS API", Version = "v1" });
    c.AddSecurityDefinition("Bearer", new OpenApiSecurityScheme
    {
        Name         = "Authorization",
        Type         = SecuritySchemeType.Http,
        Scheme       = "bearer",
        BearerFormat = "JWT",
        In           = ParameterLocation.Header,
        Description  = "Enter your JWT token (without 'Bearer' prefix)"
    });
    c.AddSecurityRequirement(new OpenApiSecurityRequirement
    {
        {
            new OpenApiSecurityScheme
            {
                Reference = new OpenApiReference { Type = ReferenceType.SecurityScheme, Id = "Bearer" }
            },
            Array.Empty<string>()
        }
    });
});

// ── Build ─────────────────────────────────────────────────
var app = builder.Build();

// ── Database schema + default data on startup ─────────
// Several companies (VPS): master database, first Super Admin, then every company database
//   gets its pending EF Core migrations. Any failure stops the app, so it never runs against a
//   schema it doesn't match; the auto-deploy log then shows the failure.
// One company (PostgreSQL): migrations on DefaultConnection.
// SQL Server (local dev): migrations are PostgreSQL-specific — EnsureCreated when DB_AUTO_CREATE=true.
{
    var logger = app.Services.GetRequiredService<ILogger<Program>>();
    if (tenancy.Enabled)
    {
        await PlatformStartup.InitializeAsync(app.Services, app.Configuration, logger);
    }
    else
    {
        using var scope = app.Services.CreateScope();
        var context = scope.ServiceProvider.GetRequiredService<HrmsDbContext>();
        if (context.Database.IsNpgsql())
        {
            await TenantDatabase.MigrateAndSeedAsync(context, logger, "single", seedDefaultAdmin: true);
        }
        else
        {
            if (Environment.GetEnvironmentVariable("DB_AUTO_CREATE") == "true")
            {
                var created = await context.Database.EnsureCreatedAsync();
                logger.LogInformation(created ? "✅ Database schema created" : "ℹ️ Schema already present — skipped");
            }
            try
            {
                await DataSeeder.SeedAsync(context, logger, seedDefaultAdmin: true);
            }
            catch (Exception ex)
            {
                logger.LogError(ex, "❌ Database setup error - continuing anyway");
            }
        }
    }
}

// ── Middleware Pipeline ───────────────────────────────────
app.UseGlobalExceptionHandler();   // Custom exception middleware

// Swagger — local dev only, disabled in production
if (!app.Environment.IsProduction())
{
    app.UseSwagger();
    app.UseSwaggerUI(c =>
    {
        c.SwaggerEndpoint("/swagger/v1/swagger.json", "HRMS API v1");
        c.RoutePrefix = "swagger";
    });

    // Redirect root / to /swagger/index.html in dev
    app.MapGet("/", () => Results.Redirect("/swagger/index.html"));
}

// app.UseHttpsRedirection(); // Disabled — use HTTP for local dev to avoid cert issues

// Enable static file serving for uploaded files
app.UseStaticFiles();

// CORS MUST come before Authentication/Authorization so preflight OPTIONS
// requests are handled before the JWT middleware can reject them.
app.UseCors("AllowAngular");

// Pick the company (and its database) from the host name — before login checks.
app.UseMiddleware<TenantResolutionMiddleware>();
app.UseRateLimiter();

app.UseAuthentication();
app.UseAuthorization();
app.MapControllers();
app.MapHub<HrmsApi.Hubs.ChatHub>("/api/hubs/chat");

app.Run();

// Make Program class accessible for integration testing
public partial class Program { }
