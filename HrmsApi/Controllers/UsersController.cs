using HrmsApi.Data;
using HrmsApi.Models;
using HrmsApi.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace HrmsApi.Controllers;

/// <summary>
/// Master → Users. A login belongs to an employee when both have the same email.
///   Employee logins: created from an employee (here by picking one, or automatically in Employees);
///                    their email follows the employee record.
///   Admin / User logins: HR and office staff, created here.
/// New logins never get a typed password: the person receives a "Set my password" email.
/// </summary>
[ApiController]
[Route("api/[controller]")]
[Authorize(Roles = "Admin")]
public class UsersController : ControllerBase
{
    private static readonly string[] Roles = { "Admin", "Employee", "User" };

    private readonly HrmsDbContext _db;
    private readonly IAccountService _accounts;
    private readonly IAuditService _audit;

    public UsersController(HrmsDbContext db, IAccountService accounts, IAuditService audit)
    {
        _db = db; _accounts = accounts; _audit = audit;
    }

    /// <summary>GET /api/users — every login with the employee it belongs to (matched by email).</summary>
    [HttpGet]
    public async Task<IActionResult> GetAll()
    {
        var users = await _db.Users.OrderBy(u => u.Username).ToListAsync();
        var employees = await _db.Employees
            .Select(e => new { e.Id, e.Name, e.EmployeeCode, e.Email, e.IsActive })
            .ToListAsync();
        var byEmail = employees.GroupBy(e => e.Email.ToLower()).ToDictionary(g => g.Key, g => g.First());

        return Ok(users.Select(u =>
        {
            byEmail.TryGetValue(u.Email.ToLower(), out var e);
            // Problems the admin should look at
            string? warning = null;
            if (u.Role == "Employee" && e == null && u.IsActive) warning = "No employee record with this email";
            else if (e != null && !e.IsActive && u.IsActive) warning = "Employee is inactive but the login is active";
            return new
            {
                u.Id, u.Username, u.Email, u.Role, u.IsActive, u.CreatedAt,
                employee = e == null ? null : new { e.Id, e.Name, e.EmployeeCode, e.IsActive },
                warning
            };
        }));
    }

    /// <summary>GET /api/users/available-employees — active employees that don't have a login yet.</summary>
    [HttpGet("available-employees")]
    public async Task<IActionResult> AvailableEmployees()
    {
        var userEmails = await _db.Users.Select(u => u.Email.ToLower()).ToListAsync();
        var list = await _db.Employees
            .Where(e => e.IsActive)
            .OrderBy(e => e.Name)
            .Select(e => new { e.Id, e.Name, e.EmployeeCode, e.Email })
            .ToListAsync();
        return Ok(list.Where(e => !string.IsNullOrWhiteSpace(e.Email) && !userEmails.Contains(e.Email.ToLower())));
    }

    /// <summary>
    /// POST /api/users — new login, with a "Set my password" email.
    ///   Employee role: pick the employee (employeeId); username and email come from the employee.
    ///   Admin / User:  username + email.
    /// </summary>
    [HttpPost]
    public async Task<IActionResult> Create([FromBody] UserCreateRequest req)
    {
        if (!Roles.Contains(req.Role)) return BadRequest(new { message = "Choose a role." });

        string email, username, personName;
        if (req.Role == "Employee")
        {
            if (req.EmployeeId == null) return BadRequest(new { message = "Choose the employee.", field = "employeeId" });
            var emp = await _db.Employees.FindAsync(req.EmployeeId.Value);
            if (emp == null) return BadRequest(new { message = "Employee not found.", field = "employeeId" });
            if (!emp.IsActive) return BadRequest(new { message = $"{emp.Name} is inactive.", field = "employeeId" });
            email      = emp.Email.Trim();
            username   = string.IsNullOrWhiteSpace(req.Username) ? _accounts.UsernameFor(email) : req.Username.Trim();
            personName = emp.Name;
        }
        else
        {
            email      = (req.Email ?? "").Trim();
            username   = (req.Username ?? "").Trim();
            personName = username;
            if (username.Length < 3) return BadRequest(new { message = "Username must be at least 3 characters.", field = "username" });
            if (!email.Contains('@')) return BadRequest(new { message = "Enter a valid email address.", field = "email" });
        }

        if (await _db.Users.AnyAsync(u => u.Email.ToLower() == email.ToLower()))
            return BadRequest(new { message = $"{email} already has a login.", field = "email" });
        if (await _db.Users.AnyAsync(u => u.Username.ToLower() == username.ToLower()))
            return BadRequest(new { message = $"Username \"{username}\" is already taken.", field = "username" });

        var user = _accounts.NewUser(email, username, req.Role);
        _db.Users.Add(user);
        await _db.SaveChangesAsync();
        var sent = await _accounts.SendWelcomeAsync(user, personName);

        await Audit("Created", user, $"Created {user.Role} login {user.Username} ({user.Email})" + (sent ? ", set-password email sent" : ""));
        return Ok(new { user.Id, user.Username, user.Email, user.Role, user.IsActive, welcomeEmailSent = sent });
    }

    /// <summary>
    /// PUT /api/users/{id} — username, role, active, optional new password.
    /// The email of an employee's login is managed on the employee record.
    /// </summary>
    [HttpPut("{id:int}")]
    public async Task<IActionResult> Update(int id, [FromBody] UserUpdateRequest req)
    {
        var user = await _db.Users.FindAsync(id) ?? throw new KeyNotFoundException($"User {id} not found.");
        if (!Roles.Contains(req.Role)) return BadRequest(new { message = "Choose a role." });

        var username = (req.Username ?? "").Trim();
        var email    = (req.Email ?? "").Trim();
        if (username.Length < 3) return BadRequest(new { message = "Username must be at least 3 characters.", field = "username" });
        if (!email.Contains('@')) return BadRequest(new { message = "Enter a valid email address.", field = "email" });

        var linked = await _db.Employees.FirstOrDefaultAsync(e => e.Email.ToLower() == user.Email.ToLower());
        if (linked != null && !string.Equals(user.Email, email, StringComparison.OrdinalIgnoreCase))
            return BadRequest(new { message = $"This login belongs to {linked.Name}. Change the email on the employee record (Employees → Edit); the login follows.", field = "email" });

        if (await _db.Users.AnyAsync(u => u.Id != id && u.Username.ToLower() == username.ToLower()))
            return BadRequest(new { message = $"Username \"{username}\" is already taken.", field = "username" });
        if (await _db.Users.AnyAsync(u => u.Id != id && u.Email.ToLower() == email.ToLower()))
            return BadRequest(new { message = $"{email} already has a login.", field = "email" });

        if (req.Role == "Employee" && linked == null &&
            !await _db.Employees.AnyAsync(e => e.Email.ToLower() == email.ToLower()))
            return BadRequest(new { message = $"No employee has the email {email}. Employee logins need an employee record.", field = "role" });

        // Never lock everyone out
        var losingAdmin = user.Role == "Admin" && user.IsActive && (req.Role != "Admin" || !req.IsActive);
        if (losingAdmin && await _db.Users.CountAsync(u => u.Role == "Admin" && u.IsActive) <= 1)
            return BadRequest(new { message = "This is the last active Admin. Make another user Admin first." });

        user.Username = username;
        user.Email    = email;
        user.Role     = req.Role;
        user.IsActive = req.IsActive;
        if (!string.IsNullOrWhiteSpace(req.Password))
        {
            if (req.Password.Length < 8) return BadRequest(new { message = "Password must be at least 8 characters.", field = "password" });
            user.PasswordHash       = BCrypt.Net.BCrypt.HashPassword(req.Password);
            user.MustChangePassword = true;   // a password set by someone else is changed at next login
            user.RefreshTokenHash      = null;  // and saved logins (phones) must sign in again
            user.RefreshTokenExpiresAt = null;
        }
        await _db.SaveChangesAsync();

        await Audit("Updated", user, $"Updated login {user.Username} ({user.Role}, {(user.IsActive ? "active" : "inactive")})");
        return Ok(new { user.Id, user.Username, user.Email, user.Role, user.IsActive });
    }

    /// <summary>POST /api/users/{id}/send-welcome — new "Set my password" email (link expired or lost).</summary>
    [HttpPost("{id:int}/send-welcome")]
    public async Task<IActionResult> SendWelcome(int id)
    {
        var user = await _db.Users.FindAsync(id) ?? throw new KeyNotFoundException($"User {id} not found.");
        if (!user.IsActive) return BadRequest(new { message = "Activate this login first." });
        var emp = await _db.Employees.FirstOrDefaultAsync(e => e.Email.ToLower() == user.Email.ToLower());
        if (!await _accounts.SendWelcomeAsync(user, emp?.Name ?? user.Username))
            return StatusCode(500, new { message = "The email could not be queued. Please try again." });
        await Audit("Updated", user, $"Sent set-password email to {user.Email}");
        return Ok(new { message = $"Set-password email sent to {user.Email}." });
    }

    /// <summary>DELETE /api/users/{id} — removes a login. Blocks deleting the last Admin.</summary>
    [HttpDelete("{id:int}")]
    public async Task<IActionResult> Delete(int id)
    {
        var user = await _db.Users.FindAsync(id) ?? throw new KeyNotFoundException($"User {id} not found.");
        if (user.Role == "Admin" && user.IsActive && await _db.Users.CountAsync(u => u.Role == "Admin" && u.IsActive) <= 1)
            throw new InvalidOperationException("Cannot delete the last active Admin user.");

        _db.Users.Remove(user);
        await _db.SaveChangesAsync();
        await Audit("Deleted", user, $"Deleted login {user.Username} ({user.Email})");
        return NoContent();
    }

    private Task Audit(string action, User user, string description) =>
        _audit.LogAsync(action, "User", user.Id.ToString(), description,
            User.Identity?.Name ?? "unknown",
            int.TryParse(User.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value, out var uid) ? uid : null,
            null, null, HttpContext.Connection.RemoteIpAddress?.ToString());
}

/// <summary>New login: Employee role → EmployeeId; Admin / User → Username + Email.</summary>
public class UserCreateRequest
{
    public string  Role       { get; set; } = "Admin";
    public int?    EmployeeId { get; set; }
    public string? Username   { get; set; }
    public string? Email      { get; set; }
}
