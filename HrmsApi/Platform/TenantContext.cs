using Microsoft.Extensions.Options;
using Npgsql;

namespace HrmsApi.Platform;

/// <summary>
/// Which company the current request (or background job) works for. Set by
/// <see cref="TenantResolutionMiddleware"/> from the web address; HrmsDbContext connects
/// to <see cref="ConnectionString"/>, so every query goes to that company's own database.
/// </summary>
public interface ITenantContext
{
    bool MultiTenant { get; }
    TenantInfo? Tenant { get; }
    bool IsPlatform { get; }

    /// <summary>Connection string for the company's database. Throws when no company is selected.</summary>
    string ConnectionString { get; }

    /// <summary>Value of the "tenant" claim a login token must carry here ("" when tenancy is off).</summary>
    string TokenScope { get; }

    /// <summary>Base URL for links in emails (password reset, welcome).</summary>
    string FrontendUrl { get; }

    void Use(TenantInfo tenant);
    void UsePlatform();
}

public class TenantContext : ITenantContext
{
    public const string PlatformScope = "_platform";

    private readonly TenancyOptions _options;
    private readonly IConfiguration _config;

    public TenantContext(IOptions<TenancyOptions> options, IConfiguration config)
    {
        _options = options.Value;
        _config  = config;
    }

    public bool MultiTenant => _options.Enabled;
    public TenantInfo? Tenant { get; private set; }
    public bool IsPlatform { get; private set; }

    public string ConnectionString
    {
        get
        {
            var baseCs = _config.GetConnectionString("DefaultConnection")
                         ?? throw new InvalidOperationException("ConnectionStrings:DefaultConnection is not set.");
            if (!MultiTenant) return baseCs;
            if (Tenant == null)
                throw new InvalidOperationException("No company selected for this request — company data is not available here.");
            return ForDatabase(baseCs, Tenant.DatabaseName);
        }
    }

    public string TokenScope => !MultiTenant ? "" : IsPlatform ? PlatformScope : Tenant?.Slug ?? "";

    public string FrontendUrl =>
        MultiTenant && Tenant != null
            ? _options.UrlFor(Tenant.Slug)
            : _config["FrontendUrl"] ?? "http://localhost:4200";

    public void Use(TenantInfo tenant) { Tenant = tenant; IsPlatform = false; }
    public void UsePlatform() { Tenant = null; IsPlatform = true; }

    /// <summary>The same server and credentials, another database.</summary>
    public static string ForDatabase(string baseConnectionString, string database) =>
        new NpgsqlConnectionStringBuilder(baseConnectionString) { Database = database }.ConnectionString;
}
