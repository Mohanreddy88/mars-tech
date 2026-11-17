using System.ComponentModel.DataAnnotations;
using Microsoft.EntityFrameworkCore;

namespace HrmsApi.Platform;

/// <summary>
/// The master database (Tenancy:MasterDatabase): which companies exist, where their data lives,
/// and the Super Admin accounts. It holds no payroll data — that stays in each company's own database.
/// Migrations: HrmsApi/Migrations/Platform (dotnet ef … --context PlatformDbContext).
/// </summary>
public class PlatformDbContext : DbContext
{
    public PlatformDbContext(DbContextOptions<PlatformDbContext> options) : base(options) { }

    public DbSet<Tenant>             Tenants     => Set<Tenant>();
    public DbSet<PlatformUser>       Users       => Set<PlatformUser>();
    public DbSet<PlatformAuditEntry> AuditLog    => Set<PlatformAuditEntry>();

    protected override void OnModelCreating(ModelBuilder b)
    {
        b.Entity<Tenant>(e =>
        {
            e.ToTable("Tenants");
            e.HasIndex(x => x.Slug).IsUnique();
            e.HasIndex(x => x.DatabaseName).IsUnique();
        });
        b.Entity<PlatformUser>(e =>
        {
            e.ToTable("PlatformUsers");
            e.HasIndex(x => x.Username).IsUnique();
        });
        b.Entity<PlatformAuditEntry>(e =>
        {
            e.ToTable("PlatformAuditLog");
            e.HasIndex(x => x.At);
        });
    }
}

public static class TenantStatus
{
    public const string Active       = "active";
    public const string Suspended    = "suspended";
    public const string Provisioning = "provisioning";
}

/// <summary>A client company: its web address code and its own database.</summary>
public class Tenant
{
    public int Id { get; set; }

    /// <summary>Web address code: "esync" → esync.marshrms.com</summary>
    [MaxLength(30)] public string Slug { get; set; } = "";

    /// <summary>Short name shown in the portal, e.g. "Esync"</summary>
    [MaxLength(100)] public string Name { get; set; } = "";

    [MaxLength(63)] public string DatabaseName { get; set; } = "";

    [MaxLength(20)] public string Status { get; set; } = TenantStatus.Active;

    [MaxLength(200)] public string? ContactEmail { get; set; }

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime? SuspendedAt { get; set; }
}

/// <summary>A Super Admin account (admin.marshrms.com). Separate from every company's own users.</summary>
public class PlatformUser
{
    public int Id { get; set; }
    [MaxLength(50)]  public string Username { get; set; } = "";
    [MaxLength(200)] public string? Email { get; set; }
    public string PasswordHash { get; set; } = "";
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime? LastLoginAt { get; set; }
}

/// <summary>What Super Admins did: created, edited, suspended a company, …</summary>
public class PlatformAuditEntry
{
    public long Id { get; set; }
    public DateTime At { get; set; } = DateTime.UtcNow;
    [MaxLength(50)]  public string Actor { get; set; } = "";
    [MaxLength(100)] public string Action { get; set; } = "";
    [MaxLength(30)]  public string? TenantSlug { get; set; }
    [MaxLength(1000)] public string? Details { get; set; }
    [MaxLength(64)]  public string? IpAddress { get; set; }
}
