using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;

namespace HrmsApi.Platform;

/// <summary>
/// Startup in multi-company mode: master database, first Super Admin, then every company database
/// is migrated. If any migration fails the app stops (the deploy is then reported as FAILED).
/// </summary>
public static class PlatformStartup
{
    public static async Task InitializeAsync(IServiceProvider services, IConfiguration config, ILogger logger)
    {
        var opts   = services.GetRequiredService<IOptions<TenancyOptions>>().Value;
        var baseCs = config.GetConnectionString("DefaultConnection")!;

        // 1. Master database
        if (await TenantDatabase.CreateIfMissingAsync(baseCs, opts.MasterDatabase))
            logger.LogInformation("🆕 Created master database {Db}", opts.MasterDatabase);

        using var scope = services.CreateScope();
        var platform = scope.ServiceProvider.GetRequiredService<PlatformDbContext>();
        await platform.Database.MigrateAsync();

        // 2. First run: the existing database becomes the root company (served at the bare domain).
        if (!await platform.Tenants.AnyAsync())
        {
            var legacyDb = new Npgsql.NpgsqlConnectionStringBuilder(baseCs).Database!;
            await TenantDatabase.CreateIfMissingAsync(baseCs, legacyDb);
            platform.Tenants.Add(new Tenant
            {
                Slug = opts.RootTenant, Name = "Demo", DatabaseName = legacyDb, Status = TenantStatus.Active
            });
            platform.AuditLog.Add(new PlatformAuditEntry
            {
                Actor = "System", Action = "Registered existing database", TenantSlug = opts.RootTenant, Details = legacyDb
            });
            await platform.SaveChangesAsync();
            logger.LogInformation("🏢 Registered existing database {Db} as company '{Slug}'", legacyDb, opts.RootTenant);
        }

        // 3. First Super Admin, password from SUPERADMIN_PASSWORD
        if (!await platform.Users.AnyAsync())
        {
            var password = config["Platform:SuperAdminPassword"];
            if (string.IsNullOrWhiteSpace(password))
            {
                logger.LogWarning("⚠️ No Super Admin yet — set SUPERADMIN_PASSWORD in the server .env and restart to create 'superadmin'.");
            }
            else
            {
                platform.Users.Add(new PlatformUser
                {
                    Username = "superadmin", PasswordHash = BCrypt.Net.BCrypt.HashPassword(password)
                });
                await platform.SaveChangesAsync();
                logger.LogInformation("✅ Super Admin 'superadmin' created");
            }
        }

        // 4. Every company database: migrations + default data
        var tenants = await platform.Tenants.AsNoTracking()
            .Where(t => t.Status != TenantStatus.Provisioning).OrderBy(t => t.Id).ToListAsync();
        foreach (var t in tenants)
        {
            await using var company = TenantDatabase.OpenCompany(TenantContext.ForDatabase(baseCs, t.DatabaseName));
            await TenantDatabase.MigrateAndSeedAsync(company, logger, t.Slug, seedDefaultAdmin: false);
        }
        logger.LogInformation("🎉 {Count} company database(s) ready", tenants.Count);
    }
}
