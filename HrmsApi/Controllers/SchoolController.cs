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
/// School features: the on/off switch, "who am I" for the web app, classes and children.
/// Parents: <see cref="ParentsController"/>. Announcements and messages have their own controllers.
/// </summary>
[ApiController]
[Route("api/school")]
[Authorize]
public class SchoolController : ControllerBase
{
    private readonly HrmsDbContext _db;
    private readonly ICompanySettingsService _settings;
    private readonly IAuditService _audit;

    public SchoolController(HrmsDbContext db, ICompanySettingsService settings, IAuditService audit)
    {
        _db = db; _settings = settings; _audit = audit;
    }

    // ── Switch and "me" ─────────────────────────────────────────────

    /// <summary>
    /// GET /api/school/me — whether school features are on, and the user's place in them
    /// (admin, class teacher of which classes, parent of which children). The web app builds its menu from this.
    /// </summary>
    [HttpGet("me")]
    public async Task<IActionResult> Me()
    {
        var enabled = (await _settings.GetAsync()).SchoolFeaturesEnabled;
        var me = await SchoolViewer.LoadAsync(_db, User);
        if (me == null) return Unauthorized();

        object? children = null;
        if (enabled && me.IsParent)
            children = await StudentQuery().Where(s => me.ChildIds.Contains(s.Id))
                .OrderBy(s => s.FullName).Select(StudentSummary).ToListAsync();

        var classes = !enabled || !me.IsTeacher ? new List<object>() :
            (await _db.SchoolClasses.Where(c => me.TeacherClassIds.Contains(c.Id))
                .OrderBy(c => c.SortOrder).ThenBy(c => c.Name)
                .Select(c => new { c.Id, c.Name }).ToListAsync()).Cast<object>().ToList();

        return Ok(new
        {
            enabled,
            userId    = me.UserId,
            name      = me.Name,
            isAdmin   = me.IsAdmin,
            isTeacher = enabled && me.IsTeacher,
            isParent  = me.IsParent,
            classes,
            children
        });
    }

    /// <summary>PUT /api/school/settings — switch the school features on or off (Company Settings).</summary>
    [HttpPut("settings")]
    [Authorize(Roles = UserAccess.Admin)]
    public async Task<IActionResult> UpdateSettings([FromBody] SchoolSettingsRequest req)
    {
        var settings = await _settings.GetAsync();
        if (settings.SchoolFeaturesEnabled != req.Enabled)
        {
            settings.SchoolFeaturesEnabled = req.Enabled;
            settings.UpdatedAt = DateTime.UtcNow;
            await _db.SaveChangesAsync();
            await Audit("Updated", "CompanySettings", "1", $"School features turned {(req.Enabled ? "on" : "off")}");
        }
        return Ok(new { enabled = settings.SchoolFeaturesEnabled });
    }

    // ── Classes ─────────────────────────────────────────────────────

    /// <summary>GET /api/school/classes — admins: all classes; class teachers: their own.</summary>
    [HttpGet("classes")]
    [RequiresSchoolFeatures]
    public async Task<IActionResult> GetClasses()
    {
        var me = await SchoolViewer.LoadAsync(_db, User);
        if (me == null || !me.IsStaff) return Forbid();

        var q = _db.SchoolClasses.AsQueryable();
        if (!me.IsAdmin) q = q.Where(c => me.TeacherClassIds.Contains(c.Id));
        return Ok(await q.OrderBy(c => c.SortOrder).ThenBy(c => c.Name)
            .Select(c => new
            {
                c.Id, c.Name, c.Description, c.SortOrder, c.IsActive, c.ClassTeacherId,
                classTeacherName = c.ClassTeacher != null ? c.ClassTeacher.Name : null,
                studentCount     = c.Students.Count(s => s.IsActive)
            }).ToListAsync());
    }

    [HttpPost("classes")]
    [Authorize(Roles = UserAccess.Admin)]
    [RequiresSchoolFeatures]
    public async Task<IActionResult> CreateClass([FromBody] SchoolClassRequest req)
    {
        var error = await ValidateClassAsync(req, null);
        if (error != null) return BadRequest(error);

        var c = new SchoolClass();
        ApplyClass(c, req);
        _db.SchoolClasses.Add(c);
        await _db.SaveChangesAsync();
        await Audit("Created", "SchoolClass", c.Id.ToString(), $"Created class {c.Name}");
        return Ok(new { c.Id });
    }

    [HttpPut("classes/{id:int}")]
    [Authorize(Roles = UserAccess.Admin)]
    [RequiresSchoolFeatures]
    public async Task<IActionResult> UpdateClass(int id, [FromBody] SchoolClassRequest req)
    {
        var c = await _db.SchoolClasses.FindAsync(id) ?? throw new KeyNotFoundException("Class not found.");
        var error = await ValidateClassAsync(req, id);
        if (error != null) return BadRequest(error);

        ApplyClass(c, req);
        await _db.SaveChangesAsync();
        await Audit("Updated", "SchoolClass", c.Id.ToString(), $"Updated class {c.Name}");
        return Ok(new { c.Id });
    }

    /// <summary>DELETE /api/school/classes/{id} — only an empty class (move or remove its children first).</summary>
    [HttpDelete("classes/{id:int}")]
    [Authorize(Roles = UserAccess.Admin)]
    [RequiresSchoolFeatures]
    public async Task<IActionResult> DeleteClass(int id)
    {
        var c = await _db.SchoolClasses.FindAsync(id) ?? throw new KeyNotFoundException("Class not found.");
        var children = await _db.Students.CountAsync(s => s.ClassId == id);
        if (children > 0)
            return BadRequest(new { message = $"{c.Name} still has {children} child{(children == 1 ? "" : "ren")}. Move them to another class first, or mark the class inactive." });

        _db.SchoolClasses.Remove(c);
        await _db.SaveChangesAsync();
        await Audit("Deleted", "SchoolClass", id.ToString(), $"Deleted class {c.Name}");
        return NoContent();
    }

    private async Task<object?> ValidateClassAsync(SchoolClassRequest req, int? id)
    {
        var name = (req.Name ?? "").Trim();
        if (name.Length == 0) return new { message = "Enter the class name.", field = "name" };
        if (await _db.SchoolClasses.AnyAsync(c => c.Id != id && c.Name.ToLower() == name.ToLower()))
            return new { message = $"There is already a class called {name}.", field = "name" };
        if (req.ClassTeacherId != null && !await _db.Employees.AnyAsync(e => e.Id == req.ClassTeacherId && e.IsActive))
            return new { message = "Choose an active employee as class teacher.", field = "classTeacherId" };
        return null;
    }

    private static void ApplyClass(SchoolClass c, SchoolClassRequest req)
    {
        c.Name           = req.Name!.Trim();
        c.Description    = string.IsNullOrWhiteSpace(req.Description) ? null : req.Description.Trim();
        c.ClassTeacherId = req.ClassTeacherId;
        c.SortOrder      = req.SortOrder;
        c.IsActive       = req.IsActive;
    }

    // ── Children ────────────────────────────────────────────────────

    /// <summary>
    /// GET /api/school/students?classId=&amp;includeInactive= — admins: every child; class teachers:
    /// children of their classes (with parents' contact details).
    /// </summary>
    [HttpGet("students")]
    [RequiresSchoolFeatures]
    public async Task<IActionResult> GetStudents([FromQuery] int? classId, [FromQuery] bool includeInactive = false)
    {
        var me = await SchoolViewer.LoadAsync(_db, User);
        if (me == null || !me.IsStaff) return Forbid();

        var q = StudentQuery();
        if (!me.IsAdmin) q = q.Where(s => s.ClassId != null && me.TeacherClassIds.Contains(s.ClassId.Value));
        if (classId != null) q = q.Where(s => s.ClassId == classId);
        if (!includeInactive) q = q.Where(s => s.IsActive);

        return Ok(await q.OrderBy(s => s.Class != null ? s.Class.SortOrder : int.MaxValue)
            .ThenBy(s => s.Class != null ? s.Class.Name : "").ThenBy(s => s.FullName)
            .Select(StudentDetail).ToListAsync());
    }

    /// <summary>GET /api/school/students/{id} — one child (admin, their class teacher or their parent).</summary>
    [HttpGet("students/{id:int}")]
    [RequiresSchoolFeatures]
    public async Task<IActionResult> GetStudent(int id)
    {
        var me = await SchoolViewer.LoadAsync(_db, User);
        var s = await StudentQuery().Where(x => x.Id == id).Select(StudentDetail).FirstOrDefaultAsync();
        if (s == null) throw new KeyNotFoundException("Child not found.");
        if (me == null || !me.CanSeeStudent(s.Id, s.ClassId)) return Forbid();
        return Ok(s);
    }

    [HttpPost("students")]
    [Authorize(Roles = UserAccess.Admin)]
    [RequiresSchoolFeatures]
    public async Task<IActionResult> CreateStudent([FromBody] StudentRequest req)
    {
        var error = await ValidateStudentAsync(req, null);
        if (error != null) return BadRequest(error);

        var s = new Student();
        ApplyStudent(s, req);
        _db.Students.Add(s);
        await _db.SaveChangesAsync();
        await SetParentsAsync(s.Id, req.ParentIds);
        await Audit("Created", "Student", s.Id.ToString(), $"Added child {s.FullName}");
        return Ok(new { s.Id });
    }

    [HttpPut("students/{id:int}")]
    [Authorize(Roles = UserAccess.Admin)]
    [RequiresSchoolFeatures]
    public async Task<IActionResult> UpdateStudent(int id, [FromBody] StudentRequest req)
    {
        var s = await _db.Students.FindAsync(id) ?? throw new KeyNotFoundException("Child not found.");
        // Name and date of birth unchanged: the "already on the list" question was answered when the child was added
        if (string.Equals(s.FullName, req.FullName?.Trim(), StringComparison.OrdinalIgnoreCase) && s.DateOfBirth == req.DateOfBirth?.Date)
            req.AllowDuplicate = true;
        var error = await ValidateStudentAsync(req, id);
        if (error != null) return BadRequest(error);

        ApplyStudent(s, req);
        await _db.SaveChangesAsync();
        await SetParentsAsync(s.Id, req.ParentIds);
        await Audit("Updated", "Student", s.Id.ToString(), $"Updated child {s.FullName}");
        return Ok(new { s.Id });
    }

    /// <summary>
    /// DELETE /api/school/students/{id} — removes the child, their parent links and message threads.
    /// To keep the history, mark the child inactive instead.
    /// </summary>
    [HttpDelete("students/{id:int}")]
    [Authorize(Roles = UserAccess.Admin)]
    [RequiresSchoolFeatures]
    public async Task<IActionResult> DeleteStudent(int id)
    {
        var s = await _db.Students.FindAsync(id) ?? throw new KeyNotFoundException("Child not found.");
        if (await _db.Conversations.AnyAsync(c => c.StudentId == id && c.Messages.Any()))
            return BadRequest(new { message = $"{s.FullName} has message history. Mark the child inactive instead, so the messages are kept." });
        if (await _db.FeeInvoices.AnyAsync(i => i.StudentId == id))
            return BadRequest(new { message = $"{s.FullName} has fee invoices. Mark the child inactive instead, so the fee records are kept." });

        _db.Students.Remove(s);
        await _db.SaveChangesAsync();
        await Audit("Deleted", "Student", id.ToString(), $"Deleted child {s.FullName}");
        return NoContent();
    }

    private async Task<object?> ValidateStudentAsync(StudentRequest req, int? id)
    {
        if (string.IsNullOrWhiteSpace(req.FullName)) return new { message = "Enter the child's name.", field = "fullName" };
        if (req.ClassId != null && !await _db.SchoolClasses.AnyAsync(c => c.Id == req.ClassId))
            return new { message = "Choose a class.", field = "classId" };
        if (!Student.SessionTypes.Contains(req.SessionType))
            return new { message = "Choose the session (half day, full day or daycare).", field = "sessionType" };
        if (req.DateOfBirth != null && req.DateOfBirth > DateTime.Today)
            return new { message = "Date of birth can't be in the future.", field = "dateOfBirth" };
        var adm = req.AdmissionNo?.Trim();
        if (!string.IsNullOrEmpty(adm) && await _db.Students.AnyAsync(s => s.Id != id && s.AdmissionNo == adm))
            return new { message = $"Admission no. {adm} is already used.", field = "admissionNo" };

        var (phone, phoneError) = PhoneNumbers.Normalize(req.EmergencyContactPhone);
        if (phoneError != null) return new { message = "Emergency contact phone: " + phoneError, field = "emergencyContactPhone" };
        req.EmergencyContactPhone = phone;

        var parentIds = req.ParentIds?.Distinct().ToList();
        if (parentIds is { Count: > 0 })
        {
            var chosen = await _db.Parents.AsNoTracking().Where(p => parentIds.Contains(p.Id))
                .Select(p => new { p.FullName, p.Relationship }).ToListAsync();
            if (chosen.Count != parentIds.Count)
                return new { message = "One of the chosen parents no longer exists. Reload the page.", field = "parentIds" };
            // One mother and one father per child (any number of guardians)
            var twice = chosen.Where(p => p.Relationship != Parent.Guardian).GroupBy(p => p.Relationship)
                .FirstOrDefault(g => g.Count() > 1);
            if (twice != null)
                return new
                {
                    message = $"A child can have only one {twice.Key.ToLower()}: {string.Join(" and ", twice.Select(p => p.FullName))} are both {twice.Key.ToLower()}s. Untick one, or change one to Guardian under School → Parents.",
                    field = "parentIds"
                };
        }

        // Probably the same child entered twice: same name and date of birth (or no date to tell them apart)
        if (!req.AllowDuplicate)
        {
            var name = req.FullName!.Trim().ToLower();
            var dob = req.DateOfBirth?.Date;
            var same = await _db.Students.AsNoTracking()
                .Where(s => s.Id != (id ?? 0) && s.FullName.ToLower() == name
                            && (dob == null || s.DateOfBirth == null || s.DateOfBirth == dob))
                .Select(s => new { s.FullName, s.DateOfBirth, className = s.Class != null ? s.Class.Name : null })
                .FirstOrDefaultAsync();
            if (same != null)
                return new
                {
                    message = $"{same.FullName}" +
                              (same.DateOfBirth != null ? $" (born {same.DateOfBirth:d MMM yyyy})" : "") +
                              (same.className != null ? $" in {same.className}" : "") +
                              " is already on the list. Is this a different child?",
                    field = "fullName",
                    duplicate = true
                };
        }
        return null;
    }

    /// <summary>Links the child to exactly these parents; null leaves the links as they are.</summary>
    private async Task SetParentsAsync(int studentId, List<int>? parentIds)
    {
        if (parentIds == null) return;
        var wanted = parentIds.ToHashSet();
        var links = await _db.StudentParents.Where(sp => sp.StudentId == studentId).ToListAsync();
        _db.StudentParents.RemoveRange(links.Where(l => !wanted.Contains(l.ParentId)));
        foreach (var pid in wanted.Where(w => links.All(l => l.ParentId != w)))
            _db.StudentParents.Add(new StudentParent { StudentId = studentId, ParentId = pid });
        await _db.SaveChangesAsync();
    }

    private static void ApplyStudent(Student s, StudentRequest req)
    {
        static string? Clean(string? v) => string.IsNullOrWhiteSpace(v) ? null : v.Trim();
        s.FullName              = req.FullName!.Trim();
        s.AdmissionNo           = Clean(req.AdmissionNo);
        s.DateOfBirth           = req.DateOfBirth?.Date;
        s.Gender                = Clean(req.Gender);
        s.ClassId               = req.ClassId;
        s.SessionType           = req.SessionType;
        s.JoinedOn              = req.JoinedOn?.Date;
        s.MedicalNotes          = Clean(req.MedicalNotes);
        s.EmergencyContactName  = Clean(req.EmergencyContactName);
        s.EmergencyContactPhone = Clean(req.EmergencyContactPhone);
        s.Notes                 = Clean(req.Notes);
        s.IsActive              = req.IsActive;
    }

    private IQueryable<Student> StudentQuery() => _db.Students.AsNoTracking();

    private static readonly System.Linq.Expressions.Expression<Func<Student, StudentDto>> StudentDetail = s => new StudentDto
    {
        Id = s.Id, FullName = s.FullName, AdmissionNo = s.AdmissionNo, DateOfBirth = s.DateOfBirth, Gender = s.Gender,
        ClassId = s.ClassId, ClassName = s.Class != null ? s.Class.Name : null,
        ClassTeacherName = s.Class != null && s.Class.ClassTeacher != null ? s.Class.ClassTeacher.Name : null,
        SessionType = s.SessionType, JoinedOn = s.JoinedOn, MedicalNotes = s.MedicalNotes,
        EmergencyContactName = s.EmergencyContactName, EmergencyContactPhone = s.EmergencyContactPhone,
        Notes = s.Notes, IsActive = s.IsActive,
        Parents = s.Parents.Select(sp => new StudentParentDto
        {
            Id = sp.Parent.Id, FullName = sp.Parent.FullName, Relationship = sp.Parent.Relationship,
            Phone = sp.Parent.Phone, Email = sp.Parent.Email, HasLogin = sp.Parent.UserId != null,
            IsActive = sp.Parent.IsActive
        }).ToList()
    };

    /// <summary>What a parent sees about their own child.</summary>
    private static readonly System.Linq.Expressions.Expression<Func<Student, object>> StudentSummary = s => new
    {
        s.Id, s.FullName, s.DateOfBirth, s.SessionType, s.ClassId,
        className        = s.Class != null ? s.Class.Name : null,
        classTeacherName = s.Class != null && s.Class.ClassTeacher != null ? s.Class.ClassTeacher.Name : null
    };

    private Task Audit(string action, string entity, string id, string description) =>
        _audit.LogAsync(action, entity, id, description, User.Identity?.Name ?? "unknown",
            int.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out var uid) ? uid : null,
            null, null, HttpContext.Connection.RemoteIpAddress?.ToString());
}

public class SchoolSettingsRequest
{
    public bool Enabled { get; set; }
}

public class SchoolClassRequest
{
    [StringLength(50)]  public string? Name { get; set; }
    [StringLength(200)] public string? Description { get; set; }
    public int? ClassTeacherId { get; set; }
    public int  SortOrder { get; set; }
    public bool IsActive { get; set; } = true;
}

public class StudentRequest
{
    [StringLength(150)] public string? FullName { get; set; }
    [StringLength(30)]  public string? AdmissionNo { get; set; }
    public DateTime? DateOfBirth { get; set; }
    [StringLength(10)]  public string? Gender { get; set; }
    public int? ClassId { get; set; }
    public string SessionType { get; set; } = Student.FullDay;
    public DateTime? JoinedOn { get; set; }
    [StringLength(1000)] public string? MedicalNotes { get; set; }
    [StringLength(150)]  public string? EmergencyContactName { get; set; }
    [StringLength(30)]   public string? EmergencyContactPhone { get; set; }
    [StringLength(1000)] public string? Notes { get; set; }
    public bool IsActive { get; set; } = true;
    /// <summary>Parents to link (they can also be linked from School → Parents); null = leave unchanged.</summary>
    public List<int>? ParentIds { get; set; }
    /// <summary>Save even though a child with the same name and date of birth exists (the office confirmed).</summary>
    public bool AllowDuplicate { get; set; }
}

public class StudentDto
{
    public int Id { get; set; }
    public string FullName { get; set; } = "";
    public string? AdmissionNo { get; set; }
    public DateTime? DateOfBirth { get; set; }
    public string? Gender { get; set; }
    public int? ClassId { get; set; }
    public string? ClassName { get; set; }
    public string? ClassTeacherName { get; set; }
    public string SessionType { get; set; } = "";
    public DateTime? JoinedOn { get; set; }
    public string? MedicalNotes { get; set; }
    public string? EmergencyContactName { get; set; }
    public string? EmergencyContactPhone { get; set; }
    public string? Notes { get; set; }
    public bool IsActive { get; set; }
    public List<StudentParentDto> Parents { get; set; } = new();
}

public class StudentParentDto
{
    public int Id { get; set; }
    public string FullName { get; set; } = "";
    public string Relationship { get; set; } = "";
    public string? Phone { get; set; }
    public string? Email { get; set; }
    public bool HasLogin { get; set; }
    public bool IsActive { get; set; }
}
