using System.ComponentModel.DataAnnotations;
using System.Net;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text.RegularExpressions;
using HrmsApi.Models;
using HrmsApi.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;

namespace HrmsApi.Platform;

/// <summary>
/// Super Admin portal API (admin.marshrms.com): register companies, edit their details,
/// suspend / activate them. Reachable only on the portal host (see TenantResolutionMiddleware).
/// </summary>
[ApiController]
[Route("api/platform")]
[Authorize(Roles = SuperAdminRole)]
public class PlatformController : ControllerBase
{
    public const string SuperAdminRole = "SuperAdmin";

    private static readonly Regex SlugRule = new("^[a-z][a-z0-9-]{0,28}[a-z0-9]$", RegexOptions.Compiled);
    private static readonly HashSet<string> Reserved = new(StringComparer.OrdinalIgnoreCase)
    {
        "admin", "www", "uat", "api", "app", "mail", "smtp", "imap", "pop", "ftp", "webmail", "cpanel",
        "master", "postgres", "support", "help", "status", "static", "cdn", "assets", "dev", "test", "staging"
    };

    private readonly PlatformDbContext _db;
    private readonly TenantCatalog _catalog;
    private readonly TenancyOptions _opts;
    private readonly IConfiguration _config;
    private readonly TokenService _tokens;
    private readonly IEmailQueue _email;
    private readonly ILogger<PlatformController> _logger;

    public PlatformController(PlatformDbContext db, TenantCatalog catalog, IOptions<TenancyOptions> opts,
        IConfiguration config, TokenService tokens, IEmailQueue email, ILogger<PlatformController> logger)
    {
        _db = db; _catalog = catalog; _opts = opts.Value; _config = config;
        _tokens = tokens; _email = email; _logger = logger;
    }

    private string BaseCs => _config.GetConnectionString("DefaultConnection")!;
    private string Actor => User.Identity?.Name ?? "unknown";

    // ── Caddy: may this host name get an HTTPS certificate? ──────────────────

    // GET api/platform/domain-check?domain=esync.marshrms.com → 200 if it is the portal or a registered company
    [AllowAnonymous]
    [HttpGet("domain-check")]
    public async Task<IActionResult> DomainCheck([FromQuery] string? domain)
    {
        var match = _opts.Match(domain);
        return match.Kind switch
        {
            HostKind.Platform or HostKind.Root => Ok(),
            HostKind.Tenant when await _catalog.FindAsync(match.Slug!) != null => Ok(),
            _ => NotFound()
        };
    }

    // ── Login ────────────────────────────────────────────────────────────────

    [AllowAnonymous]
    [EnableRateLimiting("platform-login")]
    [HttpPost("auth/login")]
    public async Task<IActionResult> Login([FromBody] PlatformLoginRequest req)
    {
        var user = await _db.Users.FirstOrDefaultAsync(u => u.Username == req.Username.Trim());
        if (user == null || !BCrypt.Net.BCrypt.Verify(req.Password, user.PasswordHash))
        {
            await Audit("Failed login", null, $"username: {req.Username}", actor: "anonymous");
            return Unauthorized(new { message = "Invalid username or password." });
        }

        user.LastLoginAt = DateTime.UtcNow;
        await _db.SaveChangesAsync();
        await Audit("Logged in", null, null, actor: user.Username);

        var (token, expiresAt) = _tokens.GenerateToken(user.Id, user.Username, SuperAdminRole);
        return Ok(new { token, username = user.Username, role = SuperAdminRole, expiresAt });
    }

    [HttpPost("auth/change-password")]
    public async Task<IActionResult> ChangePassword([FromBody] PlatformChangePasswordRequest req)
    {
        var user = await _db.Users.FirstOrDefaultAsync(u => u.Username == Actor);
        if (user == null || !BCrypt.Net.BCrypt.Verify(req.CurrentPassword, user.PasswordHash))
            return BadRequest(new { message = "Your current password is not correct." });

        user.PasswordHash = BCrypt.Net.BCrypt.HashPassword(req.NewPassword);
        await _db.SaveChangesAsync();
        await Audit("Changed own password", null, null);
        return Ok(new { message = "Password changed." });
    }

    // ── Companies ────────────────────────────────────────────────────────────

    // GET api/platform/tenants — every company with a few figures from its own database
    [HttpGet("tenants")]
    public async Task<IActionResult> List()
    {
        var tenants = await _db.Tenants.AsNoTracking().OrderBy(t => t.CreatedAt).ToListAsync();
        var result = new List<object>();
        foreach (var t in tenants)
            result.Add(await Describe(t));
        return Ok(result);
    }

    // POST api/platform/tenants — create the database, settings and first admin in one go
    [HttpPost("tenants")]
    public async Task<IActionResult> Create([FromBody] CreateTenantRequest req)
    {
        var slug = req.Slug.Trim().ToLowerInvariant();
        var problem = CheckSlug(slug) ?? await CheckSlugFree(slug);
        if (problem != null) return BadRequest(new { message = problem, field = "slug" });

        var database = _opts.DatabasePrefix + slug.Replace('-', '_');
        if (await TenantDatabase.ExistsAsync(BaseCs, database))
            return BadRequest(new { message = $"A database named {database} already exists on the server.", field = "slug" });

        var displayName = string.IsNullOrWhiteSpace(req.DisplayName) ? ShortName(req.LegalName) : req.DisplayName.Trim();
        var tenant = new Tenant
        {
            Slug = slug, Name = displayName, DatabaseName = database,
            Status = TenantStatus.Provisioning, ContactEmail = req.AdminEmail.Trim()
        };
        _db.Tenants.Add(tenant);
        await _db.SaveChangesAsync();

        var tempPassword = NewTemporaryPassword();
        var resetToken   = Convert.ToHexString(RandomNumberGenerator.GetBytes(32));
        var created      = false;
        try
        {
            created = await TenantDatabase.CreateIfMissingAsync(BaseCs, database);
            await using (var company = TenantDatabase.OpenCompany(TenantContext.ForDatabase(BaseCs, database)))
            {
                await TenantDatabase.MigrateAndSeedAsync(company, _logger, slug, seedDefaultAdmin: false);

                company.CompanySettings.Add(new CompanySettings
                {
                    LegalName      = req.LegalName.Trim(),
                    DisplayName    = displayName,
                    RegistrationNo = Clean(req.RegistrationNo),
                    EmployerTaxNo  = Clean(req.EmployerTaxNo),
                    BrandColor     = req.BrandColor.ToUpperInvariant(),
                    HrOfficerName  = "HR DEPARTMENT",
                    HrOfficerPosition = "HR",
                });
                company.Users.Add(new User
                {
                    Username                 = req.AdminUsername.Trim(),
                    Email                    = req.AdminEmail.Trim(),
                    PasswordHash             = BCrypt.Net.BCrypt.HashPassword(tempPassword),
                    Role                     = "Admin",
                    IsActive                 = true,
                    MustChangePassword       = true,
                    PasswordResetToken       = BCrypt.Net.BCrypt.HashPassword(resetToken),
                    PasswordResetTokenExpiry = DateTime.UtcNow.AddDays(7),
                });
                await company.SaveChangesAsync();
            }

            tenant.Status = TenantStatus.Active;
            await _db.SaveChangesAsync();
            _catalog.Invalidate();
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Creating company {Slug} failed — undoing", slug);
            try { if (created) await TenantDatabase.DropAsync(BaseCs, database); }
            catch (Exception dropEx) { _logger.LogError(dropEx, "Could not drop {Db}", database); }
            _db.Tenants.Remove(tenant);
            await _db.SaveChangesAsync();
            _catalog.Invalidate();
            return StatusCode(500, new { message = "The company could not be created. Nothing was kept — please try again." });
        }

        var url = _opts.UrlFor(slug);
        var emailQueued = false;
        if (req.SendWelcomeEmail)
        {
            var link = $"{url}/reset-password?token={resetToken}&email={Uri.EscapeDataString(req.AdminEmail.Trim())}";
            _email.Enqueue(new EmailJob
            {
                TenantSlug = slug,
                ToEmail    = req.AdminEmail.Trim(),
                Subject    = $"Your HR & Payroll system for {displayName} is ready",
                Body       = WelcomeEmail(displayName, req.AdminName, url, req.AdminUsername.Trim(), link)
            });
            emailQueued = true;
        }

        await Audit("Created company", slug, $"{req.LegalName.Trim()} · database {database} · admin {req.AdminUsername.Trim()}");
        return Ok(new
        {
            tenant = await Describe(tenant),
            adminUsername = req.AdminUsername.Trim(),
            temporaryPassword = tempPassword,
            emailQueued
        });
    }

    // PUT api/platform/tenants/{slug} — name and payslip details
    [HttpPut("tenants/{slug}")]
    public async Task<IActionResult> Update(string slug, [FromBody] UpdateTenantRequest req)
    {
        var tenant = await _db.Tenants.FirstOrDefaultAsync(t => t.Slug == slug);
        if (tenant == null) return NotFound(new { message = "Company not found." });

        await using (var company = OpenCompany(tenant))
        {
            var s = await GetSettings(company);
            s.LegalName      = req.LegalName.Trim();
            s.DisplayName    = req.DisplayName.Trim();
            s.RegistrationNo = Clean(req.RegistrationNo);
            s.EmployerTaxNo  = Clean(req.EmployerTaxNo);
            s.BrandColor     = req.BrandColor.ToUpperInvariant();
            s.UpdatedAt      = DateTime.UtcNow;
            await company.SaveChangesAsync();
        }

        tenant.Name = req.DisplayName.Trim();
        tenant.ContactEmail = Clean(req.ContactEmail);
        await _db.SaveChangesAsync();
        _catalog.Invalidate();

        await Audit("Edited company details", slug, null);
        return Ok(await Describe(tenant));
    }

    [HttpPost("tenants/{slug}/suspend")]
    public Task<IActionResult> Suspend(string slug) => SetStatus(slug, TenantStatus.Suspended);

    [HttpPost("tenants/{slug}/activate")]
    public Task<IActionResult> Activate(string slug) => SetStatus(slug, TenantStatus.Active);

    // GET api/platform/tenants/{slug}/logo — for the portal list and Edit panel.
    // No login: <img> tags don't send the token, and logos are public on each company's login page anyway.
    [AllowAnonymous]
    [HttpGet("tenants/{slug}/logo")]
    public async Task<IActionResult> GetLogo(string slug)
    {
        Response.Headers.CacheControl = "public, max-age=86400"; // URL carries ?v=<updated>
        var tenant = await _db.Tenants.AsNoTracking().FirstOrDefaultAsync(t => t.Slug == slug);
        if (tenant == null) return NotFound();
        await using var company = OpenCompany(tenant);
        var s = await company.CompanySettings.AsNoTracking().FirstOrDefaultAsync();
        if (s?.LogoData == null || s.LogoContentType == null) return NotFound();
        return File(s.LogoData, s.LogoContentType);
    }

    [HttpPost("tenants/{slug}/logo")]
    [RequestSizeLimit(CompanySettings.MaxLogoBytes + 64 * 1024)]
    public async Task<IActionResult> UploadLogo(string slug, IFormFile? file)
    {
        var tenant = await _db.Tenants.FirstOrDefaultAsync(t => t.Slug == slug);
        if (tenant == null) return NotFound(new { message = "Company not found." });
        if (file == null || file.Length == 0) return BadRequest(new { message = "Choose a PNG or JPEG image to upload." });
        if (file.Length > CompanySettings.MaxLogoBytes) return BadRequest(new { message = "The logo must be 1 MB or smaller." });

        using var ms = new MemoryStream();
        await file.CopyToAsync(ms);
        var bytes = ms.ToArray();
        var type = CompanySettings.DetectLogoType(bytes);
        if (type == null) return BadRequest(new { message = "The logo must be a PNG or JPEG image." });

        await using (var company = OpenCompany(tenant))
        {
            var s = await GetSettings(company);
            s.LogoData = bytes;
            s.LogoContentType = type;
            s.UpdatedAt = DateTime.UtcNow;
            await company.SaveChangesAsync();
        }
        await Audit("Uploaded logo", slug, $"{bytes.Length / 1024} KB");
        return Ok(await Describe(tenant));
    }

    [HttpDelete("tenants/{slug}/logo")]
    public async Task<IActionResult> DeleteLogo(string slug)
    {
        var tenant = await _db.Tenants.FirstOrDefaultAsync(t => t.Slug == slug);
        if (tenant == null) return NotFound(new { message = "Company not found." });
        await using (var company = OpenCompany(tenant))
        {
            var s = await GetSettings(company);
            s.LogoData = null;
            s.LogoContentType = null;
            s.UpdatedAt = DateTime.UtcNow;
            await company.SaveChangesAsync();
        }
        await Audit("Removed logo", slug, null);
        return Ok(await Describe(tenant));
    }

    // GET api/platform/audit — latest 200 portal actions
    [HttpGet("audit")]
    public async Task<IActionResult> AuditLog() =>
        Ok(await _db.AuditLog.AsNoTracking().OrderByDescending(a => a.At).Take(200)
            .Select(a => new { a.At, a.Actor, a.Action, a.TenantSlug, a.Details }).ToListAsync());

    // GET api/platform/check-slug?slug=esync — live check for the wizard
    [HttpGet("check-slug")]
    public async Task<IActionResult> CheckSlugAvailable([FromQuery] string slug)
    {
        slug = (slug ?? "").Trim().ToLowerInvariant();
        var problem = CheckSlug(slug) ?? await CheckSlugFree(slug);
        return Ok(new { available = problem == null, message = problem, url = problem == null ? _opts.UrlFor(slug) : null });
    }

    // ── helpers ──────────────────────────────────────────────────────────────

    private async Task<IActionResult> SetStatus(string slug, string status)
    {
        var tenant = await _db.Tenants.FirstOrDefaultAsync(t => t.Slug == slug);
        if (tenant == null) return NotFound(new { message = "Company not found." });
        if (tenant.Status == TenantStatus.Provisioning) return BadRequest(new { message = "This company is still being created." });

        tenant.Status = status;
        tenant.SuspendedAt = status == TenantStatus.Suspended ? DateTime.UtcNow : null;
        await _db.SaveChangesAsync();
        _catalog.Invalidate();

        await Audit(status == TenantStatus.Suspended ? "Suspended company" : "Activated company", slug, null);
        return Ok(await Describe(tenant));
    }

    private Data.HrmsDbContext OpenCompany(Tenant t) =>
        TenantDatabase.OpenCompany(TenantContext.ForDatabase(BaseCs, t.DatabaseName));

    private static async Task<CompanySettings> GetSettings(Data.HrmsDbContext company)
    {
        var s = await company.CompanySettings.FirstOrDefaultAsync(c => c.Id == CompanySettings.SingletonId);
        if (s != null) return s;
        s = new CompanySettings();
        company.CompanySettings.Add(s);
        return s;
    }

    /// <summary>Portal row: catalog fields plus name, colour and counts from the company's own database.</summary>
    private async Task<object> Describe(Tenant t)
    {
        string? legalName = null, registrationNo = null, employerTaxNo = null, brandColor = null, logoUrl = null;
        int? employees = null, users = null;
        string? error = null;

        if (t.Status != TenantStatus.Provisioning)
        {
            try
            {
                await using var company = OpenCompany(t);
                var s = await company.CompanySettings.AsNoTracking()
                    .Select(c => new { c.LegalName, c.RegistrationNo, c.EmployerTaxNo, c.BrandColor, HasLogo = c.LogoData != null, c.UpdatedAt })
                    .FirstOrDefaultAsync();
                legalName      = string.IsNullOrWhiteSpace(s?.LegalName) ? null : s!.LegalName;
                registrationNo = s?.RegistrationNo;
                employerTaxNo  = s?.EmployerTaxNo;
                brandColor     = s?.BrandColor;
                logoUrl        = s?.HasLogo == true ? $"/api/platform/tenants/{t.Slug}/logo?v={s.UpdatedAt.Ticks}" : null;
                employees      = await company.Employees.CountAsync(e => e.IsActive);
                users          = await company.Users.CountAsync(u => u.IsActive);
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Could not read company database {Db}", t.DatabaseName);
                error = "Database not reachable";
            }
        }

        return new
        {
            t.Slug, t.Name, t.Status, t.DatabaseName, t.ContactEmail, t.CreatedAt, t.SuspendedAt,
            url = _opts.UrlFor(t.Slug),
            isRoot = t.Slug == _opts.RootTenant,
            legalName, registrationNo, employerTaxNo, brandColor = brandColor ?? "#C62828", logoUrl,
            employees, users, error
        };
    }

    private string? CheckSlug(string slug)
    {
        if (!SlugRule.IsMatch(slug))
            return "Use 2–30 lowercase letters, numbers or hyphens, starting with a letter.";
        if (Reserved.Contains(slug) || slug == _opts.RootTenant)
            return "That address is reserved. Choose another.";
        return null;
    }

    private async Task<string?> CheckSlugFree(string slug) =>
        await _db.Tenants.AnyAsync(t => t.Slug == slug) ? "Another company already uses this address." : null;

    private static string? Clean(string? v) => string.IsNullOrWhiteSpace(v) ? null : v.Trim();

    /// <summary>"Montessori Learning Centre Sdn. Bhd." → "Montessori Learning Centre"</summary>
    private static string ShortName(string legal) =>
        Regex.Replace(legal.Trim(), @"\s+(Sdn\.?\s*Bhd\.?|Berhad|Bhd\.?|Pte\.?\s*Ltd\.?|Ltd\.?|PLT)$", "", RegexOptions.IgnoreCase).Trim();

    /// <summary>12 characters without look-alikes (0/O, 1/l/I), e.g. "Kp7m-Qx4r-Tz9w".</summary>
    private static string NewTemporaryPassword()
    {
        const string chars = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789";
        var groups = Enumerable.Range(0, 3).Select(_ =>
            new string(Enumerable.Range(0, 4).Select(_ => chars[RandomNumberGenerator.GetInt32(chars.Length)]).ToArray()));
        return string.Join('-', groups);
    }

    private static string WelcomeEmail(string company, string? adminName, string url, string username, string link)
    {
        string E(string? s) => WebUtility.HtmlEncode(s ?? "");
        var greeting = string.IsNullOrWhiteSpace(adminName) ? "Hello" : $"Hello {E(adminName)}";
        return $@"<!DOCTYPE html><html><body style=""font-family:Arial,sans-serif;line-height:1.6;color:#1f2937;"">
<div style=""max-width:560px;margin:0 auto;padding:24px;"">
  <h2 style=""margin:0 0 12px;color:#0f766e;"">Your HR &amp; Payroll system is ready</h2>
  <p>{greeting},</p>
  <p>The HR &amp; Payroll system for <strong>{E(company)}</strong> has been set up, and you are its administrator.</p>
  <table style=""border-collapse:collapse;margin:12px 0;"">
    <tr><td style=""padding:4px 16px 4px 0;color:#6b7280;"">Web address</td><td><a href=""{E(url)}"">{E(url)}</a></td></tr>
    <tr><td style=""padding:4px 16px 4px 0;color:#6b7280;"">Username</td><td><strong>{E(username)}</strong></td></tr>
  </table>
  <p>Choose your password to get started:</p>
  <p><a href=""{E(link)}"" style=""display:inline-block;background:#0f766e;color:#fff;padding:12px 28px;border-radius:8px;text-decoration:none;font-weight:600;"">Set my password</a></p>
  <p style=""font-size:13px;color:#6b7280;"">This link works for 7 days. After that, use “Forgot password?” on the login page.</p>
</div></body></html>";
    }

    private async Task Audit(string action, string? slug, string? details, string? actor = null)
    {
        var ip = Request.Headers["X-Forwarded-For"].FirstOrDefault()?.Split(',')[0].Trim()
                 ?? HttpContext.Connection.RemoteIpAddress?.ToString();
        _db.AuditLog.Add(new PlatformAuditEntry
        {
            Actor = actor ?? Actor, Action = action, TenantSlug = slug,
            Details = details?.Length > 1000 ? details[..1000] : details, IpAddress = ip
        });
        await _db.SaveChangesAsync();
    }
}

public record PlatformLoginRequest([Required] string Username, [Required] string Password);

public class PlatformChangePasswordRequest
{
    [Required] public string CurrentPassword { get; set; } = "";

    [Required, StringLength(100, MinimumLength = 10, ErrorMessage = "Use at least 10 characters.")]
    public string NewPassword { get; set; } = "";
}

public class CreateTenantRequest
{
    [Required(ErrorMessage = "Enter the web address code.")] public string Slug { get; set; } = "";

    [Required(ErrorMessage = "Enter the company's legal name.")]
    [StringLength(200, MinimumLength = 2)] public string LegalName { get; set; } = "";

    [StringLength(100)] public string? DisplayName { get; set; }
    [StringLength(50)]  public string? RegistrationNo { get; set; }
    [StringLength(50)]  public string? EmployerTaxNo { get; set; }

    [Required, RegularExpression("^#[0-9A-Fa-f]{6}$", ErrorMessage = "Brand colour must look like #0E7490.")]
    public string BrandColor { get; set; } = "#0E7490";

    [StringLength(100)] public string? AdminName { get; set; }

    [Required(ErrorMessage = "Enter the admin's email."), EmailAddress(ErrorMessage = "Enter a valid email address."), StringLength(200)]
    public string AdminEmail { get; set; } = "";

    [Required, RegularExpression("^[A-Za-z0-9._-]{3,50}$", ErrorMessage = "Username: 3–50 letters, numbers, dots, dashes or underscores.")]
    public string AdminUsername { get; set; } = "admin";

    public bool SendWelcomeEmail { get; set; } = true;
}

public class UpdateTenantRequest
{
    [Required, StringLength(100, MinimumLength = 2)] public string DisplayName { get; set; } = "";
    [Required, StringLength(200, MinimumLength = 2)] public string LegalName { get; set; } = "";
    [StringLength(50)] public string? RegistrationNo { get; set; }
    [StringLength(50)] public string? EmployerTaxNo { get; set; }

    [Required, RegularExpression("^#[0-9A-Fa-f]{6}$", ErrorMessage = "Brand colour must look like #0E7490.")]
    public string BrandColor { get; set; } = "#0E7490";

    [EmailAddress, StringLength(200)] public string? ContactEmail { get; set; }
}
