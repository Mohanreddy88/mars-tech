using System.Net;

namespace HrmsApi.Services;

/// <summary>Emails about login accounts (welcome / set your password).</summary>
public static class AccountEmails
{
    /// <summary>How long a "Set my password" link in a welcome email works.</summary>
    public static readonly TimeSpan WelcomeLinkLifetime = TimeSpan.FromDays(7);

    /// <summary>Link to the company's own reset-password page.</summary>
    public static string SetPasswordLink(string companyUrl, string token, string email) =>
        $"{companyUrl.TrimEnd('/')}/reset-password?token={token}&email={Uri.EscapeDataString(email)}";

    /// <summary>
    /// Welcome email with the company's address, the username and a "Set my password" button.
    /// No password is ever sent by email.
    /// </summary>
    public static string Welcome(string companyName, string? personName, string companyUrl,
        string username, string setPasswordLink, string accentColor, string role, bool forParent = false)
    {
        string E(string? s) => WebUtility.HtmlEncode(s ?? "");
        var accent   = System.Text.RegularExpressions.Regex.IsMatch(accentColor ?? "", "^#[0-9A-Fa-f]{6}$") ? accentColor : "#0F766E";
        var greeting = string.IsNullOrWhiteSpace(personName) ? "Hello" : $"Hello {E(personName)}";
        var days     = (int)WelcomeLinkLifetime.TotalDays;
        // Parents (school features) sign in to the parent portal, not HR & Payroll
        var product  = forParent ? "parent portal" : "HR &amp; Payroll";
        var helper   = forParent ? "the school office" : "your HR administrator";

        return $@"<!DOCTYPE html><html><body style=""font-family:Arial,sans-serif;line-height:1.6;color:#1f2937;"">
<div style=""max-width:560px;margin:0 auto;padding:24px;"">
  <h2 style=""margin:0 0 12px;color:{accent};"">Welcome to {E(companyName)} {product}</h2>
  <p>{greeting},</p>
  <p>Your {E(role)} account for <strong>{E(companyName)}</strong> has been created.</p>
  <table style=""border-collapse:collapse;margin:12px 0;"">
    <tr><td style=""padding:4px 16px 4px 0;color:#6b7280;"">Web address</td><td><a href=""{E(companyUrl)}"">{E(companyUrl)}</a></td></tr>
    <tr><td style=""padding:4px 16px 4px 0;color:#6b7280;"">Username</td><td><strong>{E(username)}</strong></td></tr>
  </table>
  <p>Choose your password to get started:</p>
  <p><a href=""{E(setPasswordLink)}"" style=""display:inline-block;background:{accent};color:#fff;padding:12px 28px;border-radius:8px;text-decoration:none;font-weight:600;"">Set my password</a></p>
  <p style=""font-size:13px;color:#6b7280;"">This link works for {days} days. After that, use “Forgot password?” on the login page, or ask {helper} to send a new link.</p>
  <p style=""font-size:13px;color:#6b7280;"">If the button doesn't work, copy this link into your browser:<br/><a href=""{E(setPasswordLink)}"">{E(setPasswordLink)}</a></p>
</div></body></html>";
    }
}
