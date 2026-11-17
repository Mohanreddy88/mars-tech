using Microsoft.Extensions.Options;

namespace HrmsApi.Platform;

/// <summary>
/// Picks the company for each request from the host name, before authentication runs:
///   admin.marshrms.com   → Super Admin portal (only /api/platform/*)
///   esync.marshrms.com   → company "esync"   (never /api/platform/*)
///   marshrms.com         → the root company (Tenancy:RootTenant)
/// Unknown companies get 404, suspended ones 403 (their login page still shows their name and logo).
/// </summary>
public class TenantResolutionMiddleware
{
    private readonly RequestDelegate _next;

    public TenantResolutionMiddleware(RequestDelegate next) => _next = next;

    public async Task InvokeAsync(HttpContext ctx, ITenantContext tenantContext,
        TenantCatalog catalog, IOptions<TenancyOptions> options)
    {
        var opts = options.Value;
        if (!opts.Enabled) { await _next(ctx); return; }

        var path = ctx.Request.Path;

        // Caddy asks this (with an internal host name) before issuing an HTTPS certificate.
        if (path.StartsWithSegments("/api/platform/domain-check")) { await _next(ctx); return; }

        var isPlatformApi = path.StartsWithSegments("/api/platform");
        var match = opts.Match(ctx.Request.Host.Host);

        if (match.Kind == HostKind.Platform)
        {
            if (!isPlatformApi && path.StartsWithSegments("/api"))
            {
                await Reject(ctx, 404, "This address is for the Super Admin portal only.");
                return;
            }
            tenantContext.UsePlatform();
            await _next(ctx);
            return;
        }

        if (isPlatformApi)
        {
            await Reject(ctx, 404, "Not found.");
            return;
        }

        // Unknown host names (server IP, localhost, internal health checks) use the root company.
        var slug = match.Slug ?? opts.RootTenant;
        var tenant = await catalog.FindAsync(slug);
        if (tenant == null)
        {
            await Reject(ctx, 404, "No company is registered at this address.", "TENANT_NOT_FOUND");
            return;
        }

        if (tenant.Status != TenantStatus.Active)
        {
            // The login page may still show the company's name and logo.
            var isBranding = path.StartsWithSegments("/api/company-settings/public")
                          || path.StartsWithSegments("/api/company-settings/logo");
            if (!isBranding)
            {
                if (tenant.Status == TenantStatus.Suspended)
                    await Reject(ctx, 403, "This company account is suspended. Please contact MarsHRMS support.", "TENANT_SUSPENDED");
                else
                    await Reject(ctx, 503, "This company is still being set up. Please try again in a minute.", "TENANT_NOT_READY");
                return;
            }
        }

        tenantContext.Use(tenant);
        ctx.Items[nameof(TenantInfo)] = tenant;
        await _next(ctx);
    }

    private static Task Reject(HttpContext ctx, int status, string message, string? code = null)
    {
        ctx.Response.StatusCode = status;
        return ctx.Response.WriteAsJsonAsync(new { message, code });
    }
}
