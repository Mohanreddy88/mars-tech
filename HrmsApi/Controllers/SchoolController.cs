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
        var company = await _settings.GetAsync();
        var enabled = company.SchoolFeaturesEnabled;
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
            children,
            // The school's contact details (Company Settings), for the parent app's "School" page
            school = new
            {
                name    = company.NameForDisplay,
                logoUrl = company.LogoData == null ? null : $"/api/company-settings/logo?v={company.UpdatedAt.Ticks}",
                phone   = company.Phone,
                address = company.Address,
                website = company.Website
            }
        });
    }

    /// <summary>
    /// GET /api/school/today — counters for the staff home screen: of the children this user looks
    /// after (admin: all active children; class teacher: their classes), how many are checked in
    /// and absent today, plus (admins) parents' "I've paid" claims waiting to be confirmed.
    /// </summary>
    [HttpGet("today")]
    [RequiresSchoolFeatures]
    public async Task<IActionResult> Today()
    {
        var me = await SchoolViewer.LoadAsync(_db, User);
        if (me == null || !me.IsStaff) return Forbid();

        var children = _db.Students.AsNoTracking().Where(s => s.IsActive);
        if (!me.IsAdmin)
            children = children.Where(s => s.ClassId != null && me.TeacherClassIds.Contains(s.ClassId.Value));
        var ids = children.Select(s => s.Id);

        var today = SchoolClock.Today;
        var att = _db.StudentAttendance.AsNoTracking().Where(a => a.Date == today && ids.Contains(a.StudentId));

        return Ok(new
        {
            children  = await children.CountAsync(),
            checkedIn = await att.CountAsync(a => a.Status == StudentAttendance.Present && a.CheckInAt != null),
            absent    = await att.CountAsync(a => a.Status == StudentAttendance.Absent),
            feeClaimsPending = me.IsAdmin
                ? await _db.FeePaymentClaims.CountAsync(c => c.Status == FeePaymentClaim.Pending)
                : (int?)null
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

        var list = await q.OrderBy(s => s.Class != null ? s.Class.SortOrder : int.MaxValue)
            .ThenBy(s => s.Class != null ? s.Class.Name : "").ThenBy(s => s.FullName)
            .Select(StudentDetail).ToListAsync();
        if (me.IsAdmin) await FillSiblingsAsync(list);
        return Ok(list);
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
        if (me.IsAdmin) await FillSiblingsAsync(new List<StudentDto> { s });
        return Ok(s);
    }

    /// <summary>
    /// Siblings = other children who share a mother, father or guardian (admins only: a parent must
    /// not see the names of a half-sibling's other family). Worked out from the parent links.
    /// </summary>
    private async Task FillSiblingsAsync(List<StudentDto> list)
    {
        var parentIds = list.SelectMany(s => s.Parents).Select(p => p.Id).Distinct().ToList();
        if (parentIds.Count == 0) return;
        var links = await _db.StudentParents.AsNoTracking().Where(sp => parentIds.Contains(sp.ParentId))
            .Select(sp => new
            {
                sp.StudentId, sp.ParentId, sp.Parent.Relationship, sp.Student.FullName, sp.Student.IsActive,
                ClassName = sp.Student.Class != null ? sp.Student.Class.Name : null
            }).ToListAsync();

        foreach (var s in list)
        {
            var mine = s.Parents.Select(p => p.Id).ToHashSet();
            s.Siblings = links.Where(l => l.StudentId != s.Id && mine.Contains(l.ParentId))
                .GroupBy(l => l.StudentId)
                .Select(g =>
                {
                    var rels = g.Select(l => l.Relationship).ToHashSet();
                    var f = g.First();
                    return new SiblingDto
                    {
                        Id = f.StudentId, FullName = f.FullName, ClassName = f.ClassName, IsActive = f.IsActive,
                        Via = rels.Contains("Mother") && rels.Contains("Father") ? "Same parents"
                            : rels.Contains("Mother") ? "Same mother"
                            : rels.Contains("Father") ? "Same father" : "Same guardian"
                    };
                })
                .OrderBy(x => x.FullName).ToList();
        }
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
        var chosen = parentIds is { Count: > 0 }
            ? await _db.Parents.AsNoTracking().Where(p => parentIds.Contains(p.Id))
                .Select(p => new { p.FullName, p.Relationship }).ToListAsync()
            : new();

        // Apps that know the rule send NoMother/NoFatherOnRecord: then a mother and a father are
        // required unless the office ticked "no mother / father on record" (single parent).
        if (parentIds != null)
        {
            if (req.NoMotherOnRecord == false && !chosen.Any(p => p.Relationship == "Mother"))
                return new { message = "Choose the child's mother, or tick \"No mother on record\".", field = "motherId" };
            if (req.NoFatherOnRecord == false && !chosen.Any(p => p.Relationship == "Father"))
                return new { message = "Choose the child's father, or tick \"No father on record\".", field = "fatherId" };
        }

        if (parentIds is { Count: > 0 })
        {
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
        await SchoolParentFlags.SyncAsync(_db, new[] { studentId });
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
        // Single parent confirmed by the office (only from apps that send it)
        if (req.NoMotherOnRecord != null) s.NoMotherOnRecord = req.NoMotherOnRecord.Value;
        if (req.NoFatherOnRecord != null) s.NoFatherOnRecord = req.NoFatherOnRecord.Value;
    }

    private IQueryable<Student> StudentQuery() => _db.Students.AsNoTracking();

    private static readonly System.Linq.Expressions.Expression<Func<Student, StudentDto>> StudentDetail = s => new StudentDto
    {
        Id = s.Id, FullName = s.FullName, AdmissionNo = s.AdmissionNo, DateOfBirth = s.DateOfBirth, Gender = s.Gender,
        ClassId = s.ClassId, ClassName = s.Class != null ? s.Class.Name : null,
        ClassTeacherName = s.Class != null && s.Class.ClassTeacher != null ? s.Class.ClassTeacher.Name : null,
        SessionType = s.SessionType, JoinedOn = s.JoinedOn, MedicalNotes = s.MedicalNotes,
        EmergencyContactName = s.EmergencyContactName, EmergencyContactPhone = s.EmergencyContactPhone,
        Notes = s.Notes, IsActive = s.IsActive, NoMotherOnRecord = s.NoMotherOnRecord, NoFatherOnRecord = s.NoFatherOnRecord,
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
    /// <summary>
    /// Single parent: no mother / father to record. Apps that send these (true or false) must also send
    /// ParentIds, and then a mother and a father are required unless the matching flag is true.
    /// Null = old client: no check, flag unchanged.
    /// </summary>
    public bool? NoMotherOnRecord { get; set; }
    public bool? NoFatherOnRecord { get; set; }
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
    public bool NoMotherOnRecord { get; set; }
    public bool NoFatherOnRecord { get; set; }
    public List<StudentParentDto> Parents { get; set; } = new();
    /// <summary>Children sharing a parent (admins only; empty for others).</summary>
    public List<SiblingDto> Siblings { get; set; } = new();
}

public class SiblingDto
{
    public int Id { get; set; }
    public string FullName { get; set; } = "";
    public string? ClassName { get; set; }
    public bool IsActive { get; set; }
    /// <summary>"Same parents", "Same mother", "Same father" or "Same guardian".</summary>
    public string Via { get; set; } = "";
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
