using Microsoft.EntityFrameworkCore;

namespace HrmsApi.Platform;

/// <summary>A company as seen by a request: which database to use and whether it may log in.</summary>
public record TenantInfo(string Slug, string Name, string DatabaseName, string Status);

/// <summary>
/// Cached list of companies from the master database, so a request doesn't query it every time.
/// Refreshed every 30 seconds, and at once after the portal changes a company.
/// </summary>
public class TenantCatalog
{
    private static readonly TimeSpan MaxAge = TimeSpan.FromSeconds(30);

    private readonly IServiceScopeFactory _scopes;
    private readonly SemaphoreSlim _lock = new(1, 1);
    private Dictionary<string, TenantInfo> _bySlug = new();
    private DateTime _loadedAt = DateTime.MinValue;

    public TenantCatalog(IServiceScopeFactory scopes) => _scopes = scopes;

    public async Task<TenantInfo?> FindAsync(string slug)
    {
        await EnsureFreshAsync();
        return _bySlug.TryGetValue(slug.ToLowerInvariant(), out var t) ? t : null;
    }

    public async Task<IReadOnlyCollection<TenantInfo>> AllAsync()
    {
        await EnsureFreshAsync();
        return _bySlug.Values;
    }

    public void Invalidate() => _loadedAt = DateTime.MinValue;

    private async Task EnsureFreshAsync()
    {
        if (DateTime.UtcNow - _loadedAt < MaxAge) return;
        await _lock.WaitAsync();
        try
        {
            if (DateTime.UtcNow - _loadedAt < MaxAge) return;
            using var scope = _scopes.CreateScope();
            var db = scope.ServiceProvider.GetRequiredService<PlatformDbContext>();
            _bySlug = await db.Tenants.AsNoTracking()
                .ToDictionaryAsync(t => t.Slug, t => new TenantInfo(t.Slug, t.Name, t.DatabaseName, t.Status));
            _loadedAt = DateTime.UtcNow;
        }
        finally
        {
            _lock.Release();
        }
    }
}
