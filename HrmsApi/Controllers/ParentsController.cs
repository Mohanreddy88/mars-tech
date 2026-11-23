using System.ComponentModel.DataAnnotations;
using System.Security.Claims;
using HrmsApi.Data;
using HrmsApi.Models;
using HrmsApi.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace HrmsApi.Controllers;

/// <summary>
/// School → Parents (admin). A parent is linked to one or more children and may have a login
/// with the "Parent" role: created here, never typed by the admin — the parent gets a
/// "Set my password" email, like employees. The login follows the parent record (email, active).
/// </summary>
[ApiController]
[Route("api/school/parents")]
[Authorize(Roles = UserAccess.Admin)]
[RequiresSchoolFeatures]
public class ParentsController : ControllerBase
{
    private readonly HrmsDbContext _db;
    private readonly IAccountService _accounts;
    private readonly IAuditService _audit;

    public ParentsController(HrmsDbContext db, IAccountService accounts, IAuditService audit)
    {
        _db = db; _accounts = accounts; _audit = audit;
    }

    [HttpGet]
    public async Task<IActionResult> GetAll()
    {
        return Ok(await _db.Parents.AsNoTracking()
            .OrderBy(p => p.FullName)
            .Select(p => new
            {
                p.Id, p.FullName, p.Email, p.Phone, p.Relationship, p.IsActive, p.CreatedAt,
                hasLogin    = p.UserId != null,
                username    = p.User != null ? p.User.Username : null,
                loginActive = p.User != null && p.User.IsActive,
                // Never signed in yet: the set-password link hasn't been used
                loginPending = p.User != null && p.User.MustChangePassword,
                children = p.Children.Select(c => new
                {
                    id = c.StudentId, fullName = c.Student.FullName, isActive = c.Student.IsActive,
                    className = c.Student.Class != null ? c.Student.Class.Name : null,
                    // The child's other parents, so a wrong link stands out ("Rudvik, with Mohan")
                    otherParents = c.Student.Parents.Where(o => o.ParentId != p.Id)
                        .Select(o => new { id = o.ParentId, fullName = o.Parent.FullName, relationship = o.Parent.Relationship })
                        .ToList()
                }).ToList()
            }).ToListAsync());
    }

    [HttpPost]
    public async Task<IActionResult> Create([FromBody] ParentRequest req)
    {
        var error = await ValidateAsync(req, null);
        if (error != null) return BadRequest(error);

        var p = new Parent();
        Apply(p, req);
        _db.Parents.Add(p);
        await _db.SaveChangesAsync();
        await SetChildrenAsync(p, req.StudentIds);

        string? note = null;
        if (req.CreateLogin) note = await CreateLoginAsync(p);

        await Audit("Created", p, $"Added parent {p.FullName}" + (note != null ? $" ({note})" : ""));
        return Ok(new { p.Id, message = note });
    }

    [HttpPut("{id:int}")]
    public async Task<IActionResult> Update(int id, [FromBody] ParentRequest req)
    {
        var p = await _db.Parents.Include(x => x.User).FirstOrDefaultAsync(x => x.Id == id)
                ?? throw new KeyNotFoundException("Parent not found.");
        var error = await ValidateAsync(req, p);
        if (error != null) return BadRequest(error);

        if (!string.IsNullOrEmpty(req.Password) && req.Password.Length < 8)
            return BadRequest(new { message = "The password must be at least 8 characters.", field = "password" });

        Apply(p, req);
        // The login follows the parent: same email, active only while the parent is
        if (p.User != null)
        {
            if (!string.IsNullOrEmpty(p.Email)) p.User.Email = p.Email;
            p.User.IsActive = p.IsActive;
            // A password set by the office (like Master → Users): changed by the parent at next sign-in,
            // and saved logins elsewhere must sign in again
            if (!string.IsNullOrEmpty(req.Password))
            {
                p.User.PasswordHash          = BCrypt.Net.BCrypt.HashPassword(req.Password);
                p.User.MustChangePassword    = true;
                p.User.RefreshTokenHash      = null;
                p.User.RefreshTokenExpiresAt = null;
            }
        }
        await _db.SaveChangesAsync();
        await SetChildrenAsync(p, req.StudentIds);

        string? note = null;
        if (req.CreateLogin && p.UserId == null) note = await CreateLoginAsync(p);

        if (!string.IsNullOrEmpty(req.Password) && p.User != null) note = (note == null ? "" : note + "; ") + "password set by the office";
        await Audit("Updated", p, $"Updated parent {p.FullName}" + (note != null ? $" ({note})" : ""));
        return Ok(new { p.Id, message = note });
    }

    /// <summary>
    /// POST /api/school/parents/{id}/invite — create the login (if there is none) and email the
    /// "Set my password" link; otherwise send a new link.
    /// </summary>
    [HttpPost("{id:int}/invite")]
    public async Task<IActionResult> Invite(int id)
    {
        var p = await _db.Parents.Include(x => x.User).FirstOrDefaultAsync(x => x.Id == id)
                ?? throw new KeyNotFoundException("Parent not found.");
        if (!p.IsActive) return BadRequest(new { message = $"{p.FullName} is inactive. Activate the parent first." });
        if (string.IsNullOrWhiteSpace(p.Email)) return BadRequest(new { message = "Add the parent's email address first." });

        string message;
        if (p.User == null)
        {
            var problem = await LoginEmailProblemAsync(p.Email, null);
            if (problem != null) return BadRequest(new { message = problem });
            message = await CreateLoginAsync(p);
        }
        else
        {
            if (!await _accounts.SendWelcomeAsync(p.User, p.FullName))
                return StatusCode(500, new { message = "The email could not be queued. Please try again." });
            message = $"set-password email sent to {p.Email}";
        }
        await Audit("Updated", p, $"Parent login for {p.FullName}: {message}");
        return Ok(new { message = char.ToUpper(message[0]) + message[1..] + "." });
    }

    /// <summary>DELETE /api/school/parents/{id} — removes the parent and their login. Their past messages stay.</summary>
    [HttpDelete("{id:int}")]
    public async Task<IActionResult> Delete(int id)
    {
        var p = await _db.Parents.Include(x => x.User).FirstOrDefaultAsync(x => x.Id == id)
                ?? throw new KeyNotFoundException("Parent not found.");
        var user = p.User;
        _db.Parents.Remove(p);
        if (user != null) _db.Users.Remove(user);
        await _db.SaveChangesAsync();
        await Audit("Deleted", p, $"Deleted parent {p.FullName}" + (user != null ? $" and login {user.Username}" : ""));
        return NoContent();
    }

    // ── helpers ──

    private async Task<object?> ValidateAsync(ParentRequest req, Parent? existing)
    {
        if (string.IsNullOrWhiteSpace(req.FullName)) return new { message = "Enter the parent's name.", field = "fullName" };
        if (!Parent.Relationships.Contains(req.Relationship))
            return new { message = "Choose mother, father or guardian.", field = "relationship" };

        var email = req.Email?.Trim();
        if (!string.IsNullOrEmpty(email) && (!email.Contains('@') || email.Length > 150))
            return new { message = "Enter a valid email address.", field = "email" };
        if (string.IsNullOrEmpty(email) && (req.CreateLogin || existing?.UserId != null))
            return new { message = "An email address is needed for the parent's login.", field = "email" };

        if (!string.IsNullOrEmpty(email))
        {
            if (await _db.Parents.AnyAsync(p => p.Id != (existing != null ? existing.Id : 0) && p.Email != null && p.Email.ToLower() == email.ToLower()))
                return new { message = $"Another parent already uses {email}.", field = "email" };
            if (req.CreateLogin || existing?.UserId != null)
            {
                var problem = await LoginEmailProblemAsync(email, existing?.UserId);
                if (problem != null) return new { message = problem, field = "email" };
            }
        }

        // Phone: one standard form (+60…), and not shared with another parent
        var (phone, phoneError) = PhoneNumbers.Normalize(req.Phone);
        if (phoneError != null) return new { message = phoneError, field = "phone" };
        req.Phone = phone;
        if (phone != null)
        {
            var others = await _db.Parents.AsNoTracking()
                .Where(p => p.Id != (existing != null ? existing.Id : 0) && p.Phone != null)
                .Select(p => new { p.FullName, p.Phone }).ToListAsync();
            var same = others.FirstOrDefault(o => PhoneNumbers.Key(o.Phone) == phone);
            if (same != null) return new { message = $"This phone number is already used by {same.FullName}.", field = "phone" };
        }

        var ids = req.StudentIds?.Distinct().ToList() ?? new();
        if (ids.Count > 0 && await _db.Students.CountAsync(s => ids.Contains(s.Id)) != ids.Count)
            return new { message = "One of the chosen children no longer exists. Reload the page.", field = "studentIds" };

        // A child has one mother and one father (any number of guardians)
        if (ids.Count > 0 && req.Relationship != Parent.Guardian)
        {
            var clash = await _db.StudentParents.AsNoTracking()
                .Where(sp => ids.Contains(sp.StudentId) && sp.ParentId != (existing != null ? existing.Id : 0)
                             && sp.Parent.Relationship == req.Relationship)
                .Select(sp => new { child = sp.Student.FullName, parent = sp.Parent.FullName })
                .FirstOrDefaultAsync();
            if (clash != null)
                return new
                {
                    message = $"{clash.child} already has a {req.Relationship.ToLower()}: {clash.parent}. " +
                              "Choose Guardian, or untick the child.",
                    field = "studentIds"
                };
        }
        return null;
    }

    /// <summary>Logins are unique by email; a staff member who is also a parent needs a different email here.</summary>
    private async Task<string?> LoginEmailProblemAsync(string email, int? ownUserId)
    {
        var other = await _db.Users.Where(u => u.Id != (ownUserId ?? 0) && u.Email.ToLower() == email.ToLower())
            .Select(u => u.Role).FirstOrDefaultAsync();
        return other == null ? null
            : $"{email} already has a login ({other}). Use a different email address for the parent login.";
    }

    private static void Apply(Parent p, ParentRequest req)
    {
        p.FullName     = req.FullName!.Trim();
        p.Email        = string.IsNullOrWhiteSpace(req.Email) ? null : req.Email.Trim();
        p.Phone        = string.IsNullOrWhiteSpace(req.Phone) ? null : req.Phone.Trim();
        p.Relationship = req.Relationship;
        p.IsActive     = req.IsActive;
    }

    private async Task SetChildrenAsync(Parent p, List<int>? studentIds)
    {
        var wanted = studentIds?.Distinct().ToHashSet() ?? new HashSet<int>();
        var links = await _db.StudentParents.Where(sp => sp.ParentId == p.Id).ToListAsync();
        _db.StudentParents.RemoveRange(links.Where(l => !wanted.Contains(l.StudentId)));
        foreach (var sid in wanted.Where(w => links.All(l => l.StudentId != w)))
            _db.StudentParents.Add(new StudentParent { ParentId = p.Id, StudentId = sid });
        await _db.SaveChangesAsync();
    }

    /// <summary>New "Parent" login with a never-shown password, and the set-password email.</summary>
    private async Task<string> CreateLoginAsync(Parent p)
    {
        var baseName = _accounts.UsernameFor(p.Email!);
        var username = baseName;
        for (var n = 2; await _db.Users.AnyAsync(u => u.Username.ToLower() == username.ToLower()); n++)
            username = $"{baseName}{n}";

        var user = _accounts.NewUser(p.Email!, username, SchoolViewer.ParentRole);
        user.IsActive = p.IsActive;
        _db.Users.Add(user);
        await _db.SaveChangesAsync();
        p.UserId = user.Id;
        await _db.SaveChangesAsync();

        var sent = p.IsActive && await _accounts.SendWelcomeAsync(user, p.FullName);
        return sent ? $"login {username} created, set-password email sent to {p.Email}" : $"login {username} created";
    }

    private Task Audit(string action, Parent p, string description) =>
        _audit.LogAsync(action, "Parent", p.Id.ToString(), description, User.Identity?.Name ?? "unknown",
            int.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out var uid) ? uid : null,
            null, null, HttpContext.Connection.RemoteIpAddress?.ToString());
}

public class ParentRequest
{
    [StringLength(150)] public string? FullName { get; set; }
    [StringLength(150)] public string? Email { get; set; }
    [StringLength(30)]  public string? Phone { get; set; }
    public string Relationship { get; set; } = "Mother";
    public bool IsActive { get; set; } = true;
    public List<int>? StudentIds { get; set; }
    /// <summary>Create a login and email the set-password link (needs an email address).</summary>
    public bool CreateLogin { get; set; }
    /// <summary>Optional new password for an existing login (the parent must change it when signing in).</summary>
    [StringLength(100)] public string? Password { get; set; }
}
