using HrmsApi.Data;
using HrmsApi.Hubs;
using HrmsApi.Models;
using HrmsApi.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace HrmsApi.Controllers;

/// <summary>
/// The parent app's Account page, and the office's approval of pick-up people.
///   Parents: their details (they may change their phone number), each child's details (read
///   only), the child's contacts (parents, guardians and approved pick-up people), and pick-up
///   people they add — which count only once the office approves them.
///   Admins: the pick-up people waiting for approval, approve / reject.
/// Teachers see a child's approved pick-up people on the child's details.
/// </summary>
[ApiController]
[Route("api/school")]
[Authorize]
[RequiresSchoolFeatures]
public class ParentAccountController : ControllerBase
{
    private readonly HrmsDbContext _db;
    private readonly IPushService _push;
    private readonly IChatNotifier _live;

    public ParentAccountController(HrmsDbContext db, IPushService push, IChatNotifier live)
    {
        _db = db; _push = push; _live = live;
    }

    private const string ParentPage = "/parent/account", OfficePage = "/school/pickup-people";

    // ── Parent ──

    /// <summary>GET /api/school/account — the parent's details, children, contacts and pick-up people.</summary>
    [HttpGet("account")]
    public async Task<IActionResult> Account()
    {
        var me = await SchoolViewer.LoadAsync(_db, User);
        if (me?.ParentId == null) return Forbid();
        var parent = await _db.Parents.AsNoTracking().Where(p => p.Id == me.ParentId)
            .Select(p => new { p.Id, p.FullName, p.Email, p.Phone, p.Relationship, username = p.User != null ? p.User.Username : null })
            .FirstAsync();

        var children = await _db.Students.AsNoTracking().Where(s => me.ChildIds.Contains(s.Id)).OrderBy(s => s.FullName)
            .Select(s => new
            {
                s.Id, s.FullName, s.DateOfBirth, s.Gender, s.SessionType, s.JoinedOn, s.AdmissionNo,
                s.MedicalNotes, s.EmergencyContactName, s.EmergencyContactPhone,
                className = s.Class != null ? s.Class.Name : null,
                classTeacher = s.Class != null && s.Class.ClassTeacher != null ? s.Class.ClassTeacher.Name : null,
                // Parents and guardians may always collect the child
                contacts = s.Parents.Where(sp => sp.Parent.IsActive)
                    .OrderBy(sp => sp.Parent.Relationship == "Mother" ? 0 : sp.Parent.Relationship == "Father" ? 1 : 2)
                    .Select(sp => new { sp.Parent.Id, sp.Parent.FullName, sp.Parent.Relationship, sp.Parent.Phone, isMe = sp.ParentId == me.ParentId })
                    .ToList()
            }).ToListAsync();

        var ids = children.Select(c => c.Id).ToList();
        var people = await _db.PickupPeople.AsNoTracking().Where(p => ids.Contains(p.StudentId))
            .OrderBy(p => p.Status == PickupPerson.Approved ? 0 : p.Status == PickupPerson.Pending ? 1 : 2).ThenBy(p => p.FullName)
            .ToListAsync();

        return Ok(new
        {
            parent,
            children = children.Select(c => new
            {
                c.Id, c.FullName, c.DateOfBirth, c.Gender, c.SessionType, c.JoinedOn, c.AdmissionNo, c.MedicalNotes,
                c.EmergencyContactName, c.EmergencyContactPhone, c.className, c.classTeacher, c.contacts,
                pickupPeople = people.Where(p => p.StudentId == c.Id).Select(PersonDto)
            })
        });
    }

    /// <summary>PUT /api/school/account/phone { phone } — the parent changes their own phone number.</summary>
    [HttpPut("account/phone")]
    public async Task<IActionResult> SetPhone([FromBody] PhoneRequest req)
    {
        var me = await SchoolViewer.LoadAsync(_db, User);
        if (me?.ParentId == null) return Forbid();
        var (phone, error) = PhoneNumbers.Normalize(req.Phone);
        if (error != null) return BadRequest(new { message = error, field = "phone" });
        if (phone == null) return BadRequest(new { message = "Enter your phone number.", field = "phone" });

        // Same rule as the office's Parents page: not shared with another parent
        var others = await _db.Parents.AsNoTracking().Where(p => p.Id != me.ParentId && p.Phone != null)
            .Select(p => p.Phone).ToListAsync();
        if (others.Any(o => PhoneNumbers.Key(o) == phone))
            return BadRequest(new { message = "This phone number is already used by another parent. Please contact the school office.", field = "phone" });

        var parent = await _db.Parents.FirstAsync(p => p.Id == me.ParentId);
        parent.Phone = phone;
        await _db.SaveChangesAsync();
        return Ok(new { phone });
    }

    /// <summary>
    /// POST /api/school/account/pickup-people — a parent adds someone who may collect their child(ren).
    /// One record per child, waiting for the office's approval (the office is told).
    /// </summary>
    [HttpPost("account/pickup-people")]
    public async Task<IActionResult> AddPickupPerson([FromBody] PickupPersonRequest req)
    {
        var me = await SchoolViewer.LoadAsync(_db, User);
        if (me?.ParentId == null) return Forbid();
        var childIds = (req.StudentIds ?? new()).Distinct().ToList();
        if (childIds.Count == 0) return BadRequest(new { message = "Choose the child(ren) they may collect.", field = "studentIds" });
        if (childIds.Any(id => !me.ChildIds.Contains(id))) return Forbid();

        var name = Clean(req.FullName, 150);
        if (name == null) return BadRequest(new { message = "Enter their name.", field = "fullName" });
        var relationship = Clean(req.Relationship, 50);
        if (relationship == null) return BadRequest(new { message = "Who are they to the child (e.g. Grandmother, Driver)?", field = "relationship" });
        var (phone, phoneError) = PhoneNumbers.Normalize(req.Phone);
        if (phoneError != null) return BadRequest(new { message = phoneError, field = "phone" });
        if (phone == null) return BadRequest(new { message = "Enter their phone number, so the school can check with them.", field = "phone" });

        var existing = await _db.PickupPeople.AsNoTracking()
            .Where(p => childIds.Contains(p.StudentId) && p.Status != PickupPerson.Rejected).ToListAsync();
        var lower = name.ToLowerInvariant();
        var added = new List<PickupPerson>();
        foreach (var sid in childIds)
        {
            // The same person for the same child once
            if (existing.Any(p => p.StudentId == sid && (p.FullName.ToLower() == lower || PhoneNumbers.Key(p.Phone) == phone))) continue;
            var p = new PickupPerson
            {
                StudentId = sid, FullName = name, Relationship = relationship, Phone = phone, Note = Clean(req.Note, 300),
                AddedByUserId = me.UserId, AddedByName = me.Name
            };
            _db.PickupPeople.Add(p);
            added.Add(p);
        }
        if (added.Count == 0) return BadRequest(new { message = $"{name} is already on the list.", field = "fullName" });
        await _db.SaveChangesAsync();

        var kids = await _db.Students.AsNoTracking().Where(s => childIds.Contains(s.Id)).Select(s => s.FullName).ToListAsync();
        var office = await SchoolParticipants.StaffUserIdsAsync(_db, Conversation.Office, null);
        await SchoolAlerts.SendAsync(_db, _push, _live, office, "Pick-up person to approve",
            $"{me.Name} added {name} ({relationship}) to collect {string.Join(" and ", kids)}.",
            "school_pickup_person", OfficePage, "pickup", new { ids = added.Select(a => a.Id) });

        return Ok(added.Select(PersonDto));
    }

    /// <summary>DELETE /api/school/account/pickup-people/{id} — a parent takes someone off their child's list.</summary>
    [HttpDelete("account/pickup-people/{id:int}")]
    public async Task<IActionResult> RemovePickupPerson(int id)
    {
        var me = await SchoolViewer.LoadAsync(_db, User);
        var p = await _db.PickupPeople.FindAsync(id) ?? throw new KeyNotFoundException("Not found.");
        if (me?.ParentId == null || !me.ChildIds.Contains(p.StudentId)) return Forbid();
        _db.PickupPeople.Remove(p);
        await _db.SaveChangesAsync();
        return NoContent();
    }

    // ── Office ──

    /// <summary>GET /api/school/pickup-people?status=Pending — pick-up people (default: waiting for approval).</summary>
    [HttpGet("pickup-people")]
    [Authorize(Roles = UserAccess.Admin)]
    public async Task<IActionResult> List([FromQuery] string? status)
    {
        var q = _db.PickupPeople.AsNoTracking().AsQueryable();
        if (!string.Equals(status, "all", StringComparison.OrdinalIgnoreCase))
            q = q.Where(p => p.Status == (string.IsNullOrWhiteSpace(status) ? PickupPerson.Pending : status));
        var list = await q.OrderByDescending(p => p.CreatedAt).Take(300)
            .Select(p => new
            {
                p.Id, p.StudentId, p.FullName, p.Relationship, p.Phone, p.Note, p.Status, p.AddedByName, p.CreatedAt,
                p.DecidedAt, p.DecidedByName, p.RejectReason,
                childName = p.Student.FullName,
                className = p.Student.Class != null ? p.Student.Class.Name : null
            }).ToListAsync();
        return Ok(list);
    }

    /// <summary>POST /api/school/pickup-people/{id}/approve — may now collect the child.</summary>
    [HttpPost("pickup-people/{id:int}/approve")]
    [Authorize(Roles = UserAccess.Admin)]
    public Task<IActionResult> Approve(int id) => DecideAsync(id, approve: true, null);

    /// <summary>POST /api/school/pickup-people/{id}/reject { reason } — not allowed (the parent sees why).</summary>
    [HttpPost("pickup-people/{id:int}/reject")]
    [Authorize(Roles = UserAccess.Admin)]
    public Task<IActionResult> Reject(int id, [FromBody] RejectPickupRequest req) => DecideAsync(id, approve: false, Clean(req.Reason, 300));

    private async Task<IActionResult> DecideAsync(int id, bool approve, string? reason)
    {
        var me = await SchoolViewer.LoadAsync(_db, User);
        var p = await _db.PickupPeople.Include(x => x.Student).FirstOrDefaultAsync(x => x.Id == id)
                ?? throw new KeyNotFoundException("Not found.");
        p.Status = approve ? PickupPerson.Approved : PickupPerson.Rejected;
        p.RejectReason = approve ? null : reason;
        p.DecidedAt = DateTime.UtcNow;
        p.DecidedByName = me?.Name ?? User.Identity?.Name;
        await _db.SaveChangesAsync();

        var parents = await SchoolParticipants.ParentUserIdsAsync(_db, p.StudentId);
        await SchoolAlerts.SendAsync(_db, _push, _live, parents,
            approve ? "Pick-up person approved" : "Pick-up person not approved",
            approve
                ? $"{p.FullName} may now collect {p.Student.FullName}."
                : $"{p.FullName} can't collect {p.Student.FullName}{(reason != null ? $": {reason}" : ".")} Please contact the school office.",
            "school_pickup_person", ParentPage, "pickup", new { p.Id });

        return Ok(PersonDto(p));
    }

    private static object PersonDto(PickupPerson p) => new
    {
        p.Id, p.StudentId, p.FullName, p.Relationship, p.Phone, p.Note, p.Status, p.AddedByName, p.CreatedAt,
        p.DecidedAt, p.DecidedByName, p.RejectReason
    };

    private static string? Clean(string? s, int max)
    {
        var t = s?.Trim();
        return string.IsNullOrEmpty(t) ? null : t.Length > max ? t[..max] : t;
    }
}

public class PhoneRequest { public string? Phone { get; set; } }

public class PickupPersonRequest
{
    public List<int>? StudentIds { get; set; }
    public string? FullName { get; set; }
    public string? Relationship { get; set; }
    public string? Phone { get; set; }
    public string? Note { get; set; }
}

public class RejectPickupRequest { public string? Reason { get; set; } }
