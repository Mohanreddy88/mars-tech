using System.Security.Claims;
using HrmsApi.Data;
using Microsoft.EntityFrameworkCore;

namespace HrmsApi.Services;

/// <summary>
/// Who the signed-in user is, for access checks in controllers.
/// A login belongs to the employee record with the same email address.
/// </summary>
public static class UserAccess
{
    /// <summary>Roles that manage the company (the web app's admin pages).</summary>
    public const string Admin = "Admin";

    /// <summary>Roles that may approve leave and attendance.</summary>
    public const string Approvers = "Admin,Manager";

    public static bool IsApprover(this ClaimsPrincipal user) =>
        user.IsInRole("Admin") || user.IsInRole("Manager");

    /// <summary>The signed-in user's employee id, or null when the login has no employee record.</summary>
    public static async Task<int?> CurrentEmployeeIdAsync(this HrmsDbContext db, ClaimsPrincipal user)
    {
        if (!int.TryParse(user.FindFirstValue(ClaimTypes.NameIdentifier), out var userId)) return null;
        var email = await db.Users.Where(u => u.Id == userId).Select(u => u.Email).FirstOrDefaultAsync();
        if (string.IsNullOrWhiteSpace(email)) return null;
        var lower = email.ToLower();
        return await db.Employees
            .Where(e => e.Email.ToLower() == lower)
            .Select(e => (int?)e.Id)
            .FirstOrDefaultAsync();
    }

    /// <summary>True for approvers, or when <paramref name="employeeId"/> is the user's own record.</summary>
    public static async Task<bool> CanAccessEmployeeAsync(this HrmsDbContext db, ClaimsPrincipal user, int employeeId) =>
        user.IsApprover() || await db.CurrentEmployeeIdAsync(user) == employeeId;
}
