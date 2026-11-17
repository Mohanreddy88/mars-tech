using System.ComponentModel.DataAnnotations;
using System.Security.Claims;
using System.Text.Json;
using HrmsApi.Data;
using HrmsApi.Models;
using HrmsApi.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace HrmsApi.Controllers;

/// <summary>The employer's own details (name, logo, statutory numbers) for this database.</summary>
[Authorize(Roles = "Admin")]
[ApiController]
[Route("api/company-settings")]
public class CompanySettingsController : ControllerBase
{
    private const int MaxLogoBytes = 1024 * 1024; // 1 MB

    private readonly HrmsDbContext _db;
    private readonly ICompanySettingsService _settings;
    private readonly IAuditService _audit;

    public CompanySettingsController(HrmsDbContext db, ICompanySettingsService settings, IAuditService audit)
    {
        _db       = db;
        _settings = settings;
        _audit    = audit;
    }

    // GET api/company-settings/public — branding for the login page and sidebar (no login needed)
    [AllowAnonymous]
    [HttpGet("public")]
    public async Task<IActionResult> GetPublic()
    {
        var s = await _settings.GetAsync();
        return Ok(new
        {
            displayName = s.NameForDisplay,
            legalName   = s.IsConfigured ? s.LegalName : null,
            s.BrandColor,
            logoUrl     = LogoUrl(s),
            s.IsConfigured
        });
    }

    // GET api/company-settings/logo — the uploaded logo image (no login needed: shown on the login page)
    [AllowAnonymous]
    [HttpGet("logo")]
    public async Task<IActionResult> GetLogo()
    {
        var s = await _settings.GetAsync();
        if (s.LogoData == null || s.LogoContentType == null) return NotFound();
        Response.Headers.CacheControl = "public, max-age=86400"; // URL carries ?v=<updated> so changes show at once
        return File(s.LogoData, s.LogoContentType);
    }

    // GET api/company-settings — all fields, for the Company Settings page
    [HttpGet]
    public async Task<IActionResult> Get() => Ok(ToDto(await _settings.GetAsync()));

    // PUT api/company-settings
    [HttpPut]
    public async Task<IActionResult> Update([FromBody] UpdateCompanySettingsRequest req)
    {
        var s   = await _settings.GetAsync();
        var old = JsonSerializer.Serialize(ToDto(s));

        s.LegalName         = req.LegalName.Trim();
        s.DisplayName       = req.DisplayName?.Trim() ?? "";
        s.RegistrationNo    = Clean(req.RegistrationNo);
        s.EmployerTaxNo     = Clean(req.EmployerTaxNo);
        s.TaxBranch         = Clean(req.TaxBranch);
        s.Address           = Clean(req.Address);
        s.Phone             = Clean(req.Phone);
        s.Website           = Clean(req.Website);
        s.HrOfficerName     = Clean(req.HrOfficerName);
        s.HrOfficerPosition = Clean(req.HrOfficerPosition);
        s.BrandColor        = req.BrandColor.ToUpperInvariant();
        s.UpdatedAt         = DateTime.UtcNow;
        await _db.SaveChangesAsync();

        await Audit("Update", "Updated company settings", old, JsonSerializer.Serialize(ToDto(s)));
        return Ok(ToDto(s));
    }

    // POST api/company-settings/logo — PNG or JPEG, max 1 MB
    [HttpPost("logo")]
    [RequestSizeLimit(MaxLogoBytes + 64 * 1024)]
    public async Task<IActionResult> UploadLogo(IFormFile? file)
    {
        if (file == null || file.Length == 0)
            return BadRequest(new { message = "Choose a PNG or JPEG image to upload." });
        if (file.Length > MaxLogoBytes)
            return BadRequest(new { message = "The logo must be 1 MB or smaller." });

        using var ms = new MemoryStream();
        await file.CopyToAsync(ms);
        var bytes = ms.ToArray();

        // Trust the file's content, not its name or declared type.
        var type = bytes.Length > 8 && bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47 ? "image/png"
                 : bytes.Length > 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF ? "image/jpeg"
                 : null;
        if (type == null)
            return BadRequest(new { message = "The logo must be a PNG or JPEG image." });

        var s = await _settings.GetAsync();
        s.LogoData        = bytes;
        s.LogoContentType = type;
        s.UpdatedAt       = DateTime.UtcNow;
        await _db.SaveChangesAsync();

        await Audit("Update", $"Uploaded company logo ({bytes.Length / 1024} KB)");
        return Ok(ToDto(s));
    }

    // DELETE api/company-settings/logo
    [HttpDelete("logo")]
    public async Task<IActionResult> DeleteLogo()
    {
        var s = await _settings.GetAsync();
        s.LogoData        = null;
        s.LogoContentType = null;
        s.UpdatedAt       = DateTime.UtcNow;
        await _db.SaveChangesAsync();

        await Audit("Delete", "Removed company logo");
        return Ok(ToDto(s));
    }

    private static string? LogoUrl(CompanySettings s) =>
        s.LogoData == null ? null : $"/api/company-settings/logo?v={s.UpdatedAt.Ticks}";

    private static string? Clean(string? v) => string.IsNullOrWhiteSpace(v) ? null : v.Trim();

    private static object ToDto(CompanySettings s) => new
    {
        s.LegalName, s.DisplayName, s.RegistrationNo, s.EmployerTaxNo, s.TaxBranch,
        s.Address, s.Phone, s.Website, s.HrOfficerName, s.HrOfficerPosition,
        s.BrandColor, logoUrl = LogoUrl(s), s.IsConfigured, s.UpdatedAt
    };

    private Task Audit(string action, string description, string? oldValues = null, string? newValues = null)
    {
        var userId = int.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out var id) ? id : (int?)null;
        return _audit.LogAsync(action, "CompanySettings", CompanySettings.SingletonId.ToString(), description,
            User.Identity?.Name ?? "unknown", userId, oldValues, newValues,
            HttpContext.Connection.RemoteIpAddress?.ToString());
    }
}

public class UpdateCompanySettingsRequest
{
    [Required(ErrorMessage = "Legal name is required.")]
    [StringLength(200, MinimumLength = 2)]
    public string LegalName { get; set; } = "";

    [StringLength(100)] public string? DisplayName { get; set; }
    [StringLength(50)]  public string? RegistrationNo { get; set; }
    [StringLength(50)]  public string? EmployerTaxNo { get; set; }
    [StringLength(100)] public string? TaxBranch { get; set; }
    [StringLength(500)] public string? Address { get; set; }
    [StringLength(50)]  public string? Phone { get; set; }
    [StringLength(150)] public string? Website { get; set; }
    [StringLength(100)] public string? HrOfficerName { get; set; }
    [StringLength(100)] public string? HrOfficerPosition { get; set; }

    [Required]
    [RegularExpression("^#[0-9A-Fa-f]{6}$", ErrorMessage = "Brand colour must look like #C62828.")]
    public string BrandColor { get; set; } = "#C62828";
}
