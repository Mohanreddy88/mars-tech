using HrmsApi.Models;
using HrmsApi.Platform;
using Microsoft.IdentityModel.Tokens;
using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;

namespace HrmsApi.Services;

public class TokenService
{
    /// <summary>Claim naming the company a token was issued for; checked on every request.</summary>
    public const string TenantClaim = "tenant";

    private readonly IConfiguration _config;
    private readonly ITenantContext _tenant;

    public TokenService(IConfiguration config, ITenantContext tenant)
    {
        _config = config;
        _tenant = tenant;
    }

    public (string token, DateTime expiresAt) GenerateToken(User user) =>
        GenerateToken(user.Id, user.Username, user.Role);

    public (string token, DateTime expiresAt) GenerateToken(int userId, string username, string role)
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
