namespace HrmsApi.Platform;

/// <summary>
/// Multi-company ("tenancy") settings, section "Tenancy" (env Tenancy__Enabled, Tenancy__BaseDomains, …).
/// One app serves every company; each company has its own PostgreSQL database, chosen from the
/// web address: esync.marshrms.com → company "esync" → database "hrms_esync".
/// When disabled (local SQL Server dev), the app uses DefaultConnection as one company, as before.
/// </summary>
public class TenancyOptions
{
    public bool Enabled { get; set; }

    /// <summary>Comma-separated domains companies live under, first one is used in email links.
    /// Production "marshrms.com,marstech.tech"; UAT "uat.marshrms.com,uat.marstech.tech".</summary>
    public string BaseDomains { get; set; } = "localhost";

    /// <summary>Company served at the bare domain (marshrms.com). The pre-tenancy database is registered under this code.</summary>
    public string RootTenant { get; set; } = "demo";

    /// <summary>Database holding the company list and Super Admin accounts.</summary>
    public string MasterDatabase { get; set; } = "hrms_master";

    /// <summary>New company databases are named prefix + code, e.g. "hrms_" + "esync".</summary>
    public string DatabasePrefix { get; set; } = "hrms_";

    /// <summary>Sub-domain of the Super Admin portal: admin.marshrms.com.</summary>
    public const string PlatformLabel = "admin";

    public IReadOnlyList<string> Domains =>
        BaseDomains.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
                   .Select(d => d.ToLowerInvariant())
                   .OrderByDescending(d => d.Length)
                   .ToList();

    public string PrimaryDomain =>
        BaseDomains.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
                   .FirstOrDefault()?.ToLowerInvariant() ?? "localhost";

    /// <summary>Public address of a company, used in emails and shown in the portal.</summary>
    public string UrlFor(string slug)
    {
        var host = slug == RootTenant ? PrimaryDomain : $"{slug}.{PrimaryDomain}";
        return PrimaryDomain == "localhost" ? $"http://{host}:4200" : $"https://{host}";
    }

    /// <summary>Works out what a host name points to.</summary>
    public HostMatch Match(string? host)
    {
        if (string.IsNullOrWhiteSpace(host)) return HostMatch.Unknown;
        host = host.Trim().TrimEnd('.').ToLowerInvariant();
        var colon = host.LastIndexOf(':');
        if (colon > 0 && !host.Contains(']')) host = host[..colon];

        foreach (var domain in Domains)
        {
            if (host == domain) return new HostMatch(HostKind.Root, RootTenant);
            if (!host.EndsWith("." + domain)) continue;

            var label = host[..^(domain.Length + 1)];
            if (label.Contains('.')) continue;                 // e.g. esync.uat.marshrms.com on production
            if (label == PlatformLabel) return new HostMatch(HostKind.Platform, null);
            if (label == "www") return new HostMatch(HostKind.Root, RootTenant);
            return new HostMatch(HostKind.Tenant, label);
        }
        return HostMatch.Unknown;
    }
}

public enum HostKind { Unknown, Root, Platform, Tenant }

public record HostMatch(HostKind Kind, string? Slug)
{
    public static readonly HostMatch Unknown = new(HostKind.Unknown, null);
}
