namespace HrmsApi.Models;

/// <summary>
/// System user account — used for login and role-based access.
/// </summary>
public class User
{
    public int       Id                       { get; set; }
    public string    Username                 { get; set; } = string.Empty;
    public string    Email                    { get; set; } = string.Empty;
    public string    PasswordHash             { get; set; } = string.Empty;
    public string    Role                     { get; set; } = "Admin";
    public bool      IsActive                 { get; set; } = true;
    public DateTime  CreatedAt                { get; set; } = DateTime.UtcNow;

    // ── Password reset ────────────────────────────────────
    public string?   PasswordResetToken       { get; set; }
    public DateTime? PasswordResetTokenExpiry { get; set; }

    // ── Force password change on first login ──────────────
    public bool MustChangePassword { get; set; } = false;

    // ── One login at a time ───────────────────────────────
    /// <summary>
    /// Id of the user's current login session; each login replaces it and puts it in the token
    /// ("sid" claim). A token whose sid no longer matches was replaced by a newer login elsewhere.
    /// </summary>
    public string? CurrentSessionId { get; set; }

    // ── Refresh token (mobile app stays signed in) ─────────
    /// <summary>SHA-256 (hex) of the current refresh token; the token itself is never stored.
    /// Belongs to the current session: a new login replaces it, so an older device can no longer refresh.</summary>
    public string?   RefreshTokenHash      { get; set; }
    public DateTime? RefreshTokenExpiresAt { get; set; }
}

/// <summary>
/// A phone that receives push notifications for a login (Firebase Cloud Messaging token).
/// </summary>
public class DeviceToken
{
    public int      Id         { get; set; }
    public int      UserId     { get; set; }
    public string   Token      { get; set; } = string.Empty;
    /// <summary>"android" or "ios".</summary>
    public string   Platform   { get; set; } = "android";
    public DateTime CreatedAt  { get; set; } = DateTime.UtcNow;
    public DateTime LastSeenAt { get; set; } = DateTime.UtcNow;

    public User User { get; set; } = null!;
}
