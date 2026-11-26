using System.Security.Cryptography;
using System.Text;
using HrmsApi.Platform;

namespace HrmsApi.Services;

/// <summary>
/// Large school files (class story photos and videos) on disk, outside the public uploads folder:
/// &lt;Media:Root&gt;/&lt;company&gt;/stories/&lt;storyId&gt;/&lt;guid&gt;.&lt;ext&gt;. In Docker the root is the
/// <c>media</c> volume (/app/api/media), included in the nightly backup. Files are only served
/// through the API, which checks access, or with a short-lived signed link (for video players
/// that can't send the login token).
/// </summary>
public interface IMediaStore
{
    /// <summary>Saves the upload; returns the path under the root (stored on the record) and the size.</summary>
    Task<(string relativePath, long size)> SaveAsync(string folder, string extension, Stream content, long maxBytes, CancellationToken ct = default);
    /// <summary>Full path of a stored file, or null when it is missing.</summary>
    string? FullPath(string relativePath);
    void Delete(string relativePath);
    void DeleteFolder(string relativeFolder);
    /// <summary>Folder for this company (its code, or "default" without multi-company).</summary>
    string CompanyFolder { get; }
    /// <summary>"exp=…&amp;sig=…" valid for <paramref name="lifetime"/> for this item in this company.</summary>
    string Sign(string kind, int id, TimeSpan lifetime);
    bool Verify(string kind, int id, long exp, string? sig);
}

public sealed class MediaStore : IMediaStore
{
    private readonly string _root;
    private readonly byte[] _signKey;
    private readonly ITenantContext _tenant;

    public MediaStore(IConfiguration config, IWebHostEnvironment env, ITenantContext tenant)
    {
        _tenant = tenant;
        var configured = config["Media:Root"];
        _root = Path.GetFullPath(string.IsNullOrWhiteSpace(configured) ? Path.Combine(env.ContentRootPath, "media") : configured);
        var jwtKey = config["Jwt:Key"] ?? Environment.GetEnvironmentVariable("JWT_SECRET_KEY") ?? "";
        _signKey = SHA256.HashData(Encoding.UTF8.GetBytes("media-links:" + jwtKey));
    }

    public string CompanyFolder => _tenant.MultiTenant && _tenant.Tenant != null ? _tenant.Tenant.Slug : "default";

    public async Task<(string relativePath, long size)> SaveAsync(string folder, string extension, Stream content, long maxBytes, CancellationToken ct = default)
    {
        var rel = Path.Combine(folder, $"{Guid.NewGuid():N}{extension}").Replace('\\', '/');
        var full = Resolve(rel);
        Directory.CreateDirectory(Path.GetDirectoryName(full)!);
        long total = 0;
        try
        {
            await using var file = new FileStream(full, FileMode.CreateNew, FileAccess.Write, FileShare.None, 81920, useAsync: true);
            var buffer = new byte[81920];
            int read;
            while ((read = await content.ReadAsync(buffer, ct)) > 0)
            {
                total += read;
                if (total > maxBytes) throw new InvalidOperationException("too large");
                await file.WriteAsync(buffer.AsMemory(0, read), ct);
            }
        }
        catch
        {
            TryDelete(full);
            throw;
        }
        return (rel, total);
    }

    public string? FullPath(string relativePath)
    {
        var full = Resolve(relativePath);
        return File.Exists(full) ? full : null;
    }

    public void Delete(string relativePath) => TryDelete(Resolve(relativePath));

    public void DeleteFolder(string relativeFolder)
    {
        try
        {
            var full = Resolve(relativeFolder);
            if (Directory.Exists(full)) Directory.Delete(full, recursive: true);
        }
        catch { /* best effort */ }
    }

    public string Sign(string kind, int id, TimeSpan lifetime)
    {
        var exp = DateTimeOffset.UtcNow.Add(lifetime).ToUnixTimeSeconds();
        return $"exp={exp}&sig={Signature(kind, id, exp)}";
    }

    public bool Verify(string kind, int id, long exp, string? sig)
    {
        if (string.IsNullOrEmpty(sig) || exp < DateTimeOffset.UtcNow.ToUnixTimeSeconds()) return false;
        var expected = Encoding.ASCII.GetBytes(Signature(kind, id, exp));
        var given = Encoding.ASCII.GetBytes(sig);
        return CryptographicOperations.FixedTimeEquals(expected, given);
    }

    private string Signature(string kind, int id, long exp)
    {
        var data = Encoding.UTF8.GetBytes($"{CompanyFolder}|{kind}|{id}|{exp}");
        return Convert.ToHexString(HMACSHA256.HashData(_signKey, data)).ToLowerInvariant();
    }

    /// <summary>Full path under the root; refuses anything that would escape it.</summary>
    private string Resolve(string relativePath)
    {
        var full = Path.GetFullPath(Path.Combine(_root, relativePath));
        if (!full.StartsWith(_root, StringComparison.Ordinal)) throw new InvalidOperationException("Invalid media path.");
        return full;
    }

    private static void TryDelete(string full)
    {
        try { if (File.Exists(full)) File.Delete(full); } catch { /* best effort */ }
    }
}
