using HrmsApi.Models;
using HrmsApi.Platform;
using Microsoft.IdentityModel.Tokens;
using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;

namespace HrmsApi.Services;

public class TokenService
{
    /// <summary>Claim naming the company a token was issued for; checked on every request.</summary>
    public const string TenantClaim = "tenant";

    /// <summary>Claim holding the login session id; must match User.CurrentSessionId (one login at a time).</summary>
    public const string SessionClaim = "sid";

    private readonly IConfiguration _config;
    private readonly ITenantContext _tenant;

    public TokenService(IConfiguration config, ITenantContext tenant)
    {
        _config = config;
        _tenant = tenant;
    }

    /// <summary>
    /// New refresh token for the user's current session (Jwt:RefreshDays, default 30). Only its
    /// SHA-256 is stored on the user, replacing any previous one; the caller saves the change.
    /// </summary>
    public (string token, DateTime expiresAt) IssueRefreshToken(User user)
    {
        var days      = int.TryParse(_config["Jwt:RefreshDays"], out var d) && d > 0 ? d : 30;
        var token     = Base64UrlEncoder.Encode(RandomNumberGenerator.GetBytes(32));
        var expiresAt = DateTime.UtcNow.AddDays(days);
        user.RefreshTokenHash      = HashRefreshToken(token);
        user.RefreshTokenExpiresAt = expiresAt;
        return (token, expiresAt);
    }

    public static string HashRefreshToken(string token) =>
        Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(token)));

    public (string token, DateTime expiresAt) GenerateToken(User user) =>
        GenerateToken(user.Id, user.Username, user.Role, user.CurrentSessionId);

    public (string token, DateTime expiresAt) GenerateToken(int userId, string username, string role, string? sessionId = null)
    {
        var jwtConfig   = _config.GetSection("Jwt");
        var key         = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwtConfig["Key"]!));
        var credentials = new SigningCredentials(key, SecurityAlgorithms.HmacSha256);
        var expiryMins  = int.Parse(jwtConfig["ExpiryMinutes"] ?? "480");
        var expiresAt   = DateTime.UtcNow.AddMinutes(expiryMins);

        var claims = new List<Claim>
        {
            new(ClaimTypes.NameIdentifier, userId.ToString()),
            new(ClaimTypes.Name,           username),
            new(ClaimTypes.Role,           role),
            new(JwtRegisteredClaimNames.Jti, Guid.NewGuid().ToString())
        };
        // A token from one company's site must not work on another's (they share the signing key).
        if (_tenant.MultiTenant)
            claims.Add(new Claim(TenantClaim, _tenant.TokenScope));
        if (!string.IsNullOrEmpty(sessionId))
            claims.Add(new Claim(SessionClaim, sessionId));

        var token = new JwtSecurityToken(
            issuer:             jwtConfig["Issuer"],
            audience:           jwtConfig["Audience"],
            claims:             claims,
            expires:            expiresAt,
            signingCredentials: credentials
        );

        return (new JwtSecurityTokenHandler().WriteToken(token), expiresAt);
    }
}
