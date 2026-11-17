using HrmsApi.Data;
using HrmsApi.Models;
using Microsoft.EntityFrameworkCore;

namespace HrmsApi.Services;

public interface ICompanySettingsService
{
    /// <summary>The company settings row, created on first use. Cached for the request.</summary>
    Task<CompanySettings> GetAsync();
}

public class CompanySettingsService : ICompanySettingsService
{
    private readonly HrmsDbContext _db;
    private readonly IConfiguration _config;
    private CompanySettings? _cached;

    public CompanySettingsService(HrmsDbContext db, IConfiguration config)
    {
        _db     = db;
        _config = config;
    }

    public async Task<CompanySettings> GetAsync()
    {
        if (_cached != null) return _cached;

        _cached = await _db.CompanySettings.FirstOrDefaultAsync(c => c.Id == CompanySettings.SingletonId);
        if (_cached != null) return _cached;

        // First use on this database: start from the optional "Company" config section
        // (env vars Company__LegalName, Company__DisplayName, …, used when onboarding a
        // client), otherwise empty so an admin fills it in on the Company Settings page.
        var c = _config.GetSection("Company");
        var settings = new CompanySettings
        {
            LegalName         = c["LegalName"] ?? "",
            DisplayName       = c["DisplayName"] ?? "",
            RegistrationNo    = c["RegistrationNo"],
            EmployerTaxNo     = c["EmployerTaxNo"],
            TaxBranch         = c["TaxBranch"],
            Address           = c["Address"],
            Phone             = c["Phone"],
            Website           = c["Website"],
            HrOfficerName     = c["HrOfficerName"] ?? "HR DEPARTMENT",
            HrOfficerPosition = c["HrOfficerPosition"] ?? "HR",
        };
        if (System.Text.RegularExpressions.Regex.IsMatch(c["BrandColor"] ?? "", "^#[0-9A-Fa-f]{6}$"))
            settings.BrandColor = c["BrandColor"]!;

        _db.CompanySettings.Add(settings);
        try
        {
            await _db.SaveChangesAsync();
        }
        catch (DbUpdateException)
        {
            // Another request created the row at the same moment — use that one.
            _db.Entry(settings).State = EntityState.Detached;
            settings = await _db.CompanySettings.FirstAsync(x => x.Id == CompanySettings.SingletonId);
        }
        return _cached = settings;
    }
}
