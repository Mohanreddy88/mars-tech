using System.Security.Cryptography;
using HrmsApi.Data;
using HrmsApi.Models;
using HrmsApi.Platform;
using Microsoft.EntityFrameworkCore;

namespace HrmsApi.Services;

/// <summary>
/// Login accounts, shared by Employees and Master → Users so both work the same way.
///
/// A login belongs to an employee when both have the same email (that is how the whole app finds
/// "my employee record"). New logins get a random password nobody sees and a "Set my password"
/// email. <see cref="SyncFromEmployeeAsync"/> keeps a login in step when its employee changes.
/// </summary>
public interface IAccountService
{
    string UsernameFor(string email);

    /// <summary>New login (not saved yet) with a random, never-shown password.</summary>
    User NewUser(string email, string username, string role);

    /// <summary>7-day set-password link by email. Saves the token. False if the email couldn't be queued.</summary>
    Task<bool> SendWelcomeAsync(User user, string? personName);

    /// <summary>
    /// After an employee is saved: email change → login email follows; active flag → login follows.
    /// Returns a note for the admin (or null), e.g. when the last active admin would be locked out.
    /// </summary>
    Task<string?> SyncFromEmployeeAsync(string oldEmail, Employee emp);

    /// <summary>Employee deleted → their login is deactivated (kept for the audit trail).</summary>
    Task<string?> DeactivateForEmployeeAsync(string email);
}

public class AccountService : IAccountService
{
    private readonly HrmsDbContext _db;
    private readonly IEmailQueue _emailQueue;
    private readonly ICompanySettingsService _company;
    private readonly ITenantContext _tenant;
    private readonly ILogger<AccountService> _logger;

    public AccountService(HrmsDbContext db, IEmailQueue emailQueue, ICompanySettingsService company,
        ITenantContext tenant, ILogger<AccountService> logger)
    {
        _db = db; _emailQueue = emailQueue; _company = company; _tenant = tenant; _logger = logger;
    }

    public string UsernameFor(string email) =>
        (email.Contains('@') ? email.Split('@')[0] : email).Trim().ToLower();

    public User NewUser(string email, string username, string role) => new()
    {
        Username           = username,
        Email              = email.Trim(),
        PasswordHash       = BCrypt.Net.BCrypt.HashPassword(Convert.ToHexString(RandomNumberGenerator.GetBytes(32))),
        Role               = role,
        IsActive           = true,
        CreatedAt          = DateTime.UtcNow,
        MustChangePassword = true
    };

    public async Task<bool> SendWelcomeAsync(User user, string? personName)
    {
        try
        {
            var token = Convert.ToHexString(RandomNumberGenerator.GetBytes(32));
            user.PasswordResetToken       = BCrypt.Net.BCrypt.HashPassword(token);
            user.PasswordResetTokenExpiry = DateTime.UtcNow.Add(AccountEmails.WelcomeLinkLifetime);
            await _db.SaveChangesAsync();

            var company = await _company.GetAsync();
            var url     = _tenant.FrontendUrl;   // this company's own address
            var role    = user.Role switch { "Admin" => "administrator", "Employee" => "employee", _ => "user" };
            _emailQueue.Enqueue(new EmailJob
            {
                ToEmail = user.Email,
                Subject = $"Your {company.NameForDisplay} HR & Payroll login",
                Body    = AccountEmails.Welcome(company.NameForDisplay, personName, url, user.Username,
                              AccountEmails.SetPasswordLink(url, token, user.Email), company.BrandColor, role)
            });
            return true;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Could not queue welcome email for {Email}", user.Email);
            return false;
        }
    }

    public async Task<string?> SyncFromEmployeeAsync(string oldEmail, Employee emp)
    {
        var user = await _db.Users.FirstOrDefaultAsync(u => u.Email.ToLower() == oldEmail.ToLower());
        if (user == null) return null;

        var notes = new List<string>();
        if (!string.Equals(user.Email, emp.Email, StringComparison.OrdinalIgnoreCase))
        {
            user.Email = emp.Email;
            notes.Add($"login email updated to {emp.Email}");
        }

        if (user.IsActive != emp.IsActive)
        {
            if (!emp.IsActive && await IsLastActiveAdminAsync(user))
                notes.Add($"login \"{user.Username}\" kept active because it is the last active Admin");
            else
            {
                user.IsActive = emp.IsActive;
                notes.Add(emp.IsActive ? $"login \"{user.Username}\" reactivated" : $"login \"{user.Username}\" deactivated");
            }
        }

        await _db.SaveChangesAsync();
        return notes.Count == 0 ? null : string.Join("; ", notes);
    }

    public async Task<string?> DeactivateForEmployeeAsync(string email)
    {
        var user = await _db.Users.FirstOrDefaultAsync(u => u.Email.ToLower() == email.ToLower());
        if (user == null || !user.IsActive) return null;
        if (await IsLastActiveAdminAsync(user))
            return $"login \"{user.Username}\" kept active because it is the last active Admin";
        user.IsActive = false;
        await _db.SaveChangesAsync();
        return $"login \"{user.Username}\" deactivated";
    }

    private async Task<bool> IsLastActiveAdminAsync(User user) =>
        user.Role == "Admin" && user.IsActive &&
        await _db.Users.CountAsync(u => u.Role == "Admin" && u.IsActive) <= 1;
}
