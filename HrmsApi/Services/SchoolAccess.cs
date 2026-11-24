using System.Security.Claims;
using HrmsApi.Data;
using HrmsApi.Models;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Filters;
using Microsoft.EntityFrameworkCore;

namespace HrmsApi.Services;

/// <summary>
/// Who the signed-in user is for the school features, and what they may see:
///   Admin   — everything (the school office; answers "Office" threads).
///   Parent  — their own children, those children's threads and announcements.
///   Teacher — an employee who is class teacher of at least one active class: those classes'
///             children and their "Teacher" threads.
/// Built from the database on every request, never from anything the client sends.
/// </summary>
public sealed class SchoolViewer
{
    public const string ParentRole = "Parent";

    public int        UserId          { get; init; }
    public string     Name            { get; init; } = "";
    public bool       IsAdmin         { get; init; }
    public int?       ParentId        { get; init; }
    public int?       EmployeeId      { get; init; }
    public List<int>  TeacherClassIds { get; init; } = new();
    /// <summary>Children of this parent (active links only).</summary>
    public List<int>  ChildIds        { get; init; } = new();

    public bool IsParent  => ParentId != null;
    public bool IsTeacher => TeacherClassIds.Count > 0;
    /// <summary>Staff who may see the school's children: admins and class teachers.</summary>
    public bool IsStaff   => IsAdmin || IsTeacher;

    /// <summary>How this user signs messages: "Office" (admin), "Teacher" or "Parent".</summary>
    public string SenderRole => IsParent ? "Parent" : IsAdmin ? Conversation.Office : Conversation.Teacher;

    public static async Task<SchoolViewer?> LoadAsync(HrmsDbContext db, ClaimsPrincipal principal)
    {
        if (!int.TryParse(principal.FindFirstValue(ClaimTypes.NameIdentifier), out var userId)) return null;
        var user = await db.Users.AsNoTracking()
            .Where(u => u.Id == userId && u.IsActive)
            .Select(u => new { u.Id, u.Username, u.Email, u.Role })
            .FirstOrDefaultAsync();
        if (user == null) return null;

        if (user.Role == ParentRole)
        {
            var parent = await db.Parents.AsNoTracking()
                .Where(p => p.UserId == user.Id && p.IsActive)
                .Select(p => new { p.Id, p.FullName })
                .FirstOrDefaultAsync();
            if (parent == null) return new SchoolViewer { UserId = user.Id, Name = user.Username };
            var children = await db.StudentParents
                .Where(sp => sp.ParentId == parent.Id && sp.Student.IsActive)
                .Select(sp => sp.StudentId).ToListAsync();
            return new SchoolViewer { UserId = user.Id, Name = parent.FullName, ParentId = parent.Id, ChildIds = children };
        }

        var isAdmin = user.Role == "Admin";
        var email = (user.Email ?? "").ToLower();
        var employee = string.IsNullOrEmpty(email) ? null : await db.Employees.AsNoTracking()
            .Where(e => e.Email.ToLower() == email && e.IsActive)
            .Select(e => new { e.Id, e.Name })
            .FirstOrDefaultAsync();
        var classIds = employee == null ? new List<int>() : await db.SchoolClasses
            // Lead teacher or one of the other teachers of the class
            .Where(c => c.IsActive && (c.ClassTeacherId == employee.Id || c.Teachers.Any(t => t.EmployeeId == employee.Id)))
            .Select(c => c.Id).ToListAsync();

        return new SchoolViewer
        {
            UserId = user.Id,
            Name = employee?.Name ?? user.Username,
            IsAdmin = isAdmin,
            EmployeeId = employee?.Id,
            TeacherClassIds = classIds
        };
    }

    /// <summary>May this user see this child (details, threads)?</summary>
    public bool CanSeeStudent(int studentId, int? classId) =>
        IsAdmin
        || (IsParent && ChildIds.Contains(studentId))
        || (classId != null && TeacherClassIds.Contains(classId.Value));

    /// <summary>
    /// May this user read (and write in) the thread? Parents: their children's threads.
    /// Teachers: "Teacher" threads of their classes. Admins: all.
    /// </summary>
    public bool CanAccessConversation(string kind, int studentId, int? classId) =>
        IsAdmin
        || (IsParent && ChildIds.Contains(studentId))
        || (kind == Conversation.Teacher && classId != null && TeacherClassIds.Contains(classId.Value));
}

/// <summary>
/// The school endpoints answer 404 unless the company has switched the school features on
/// (Company Settings → School features).
/// </summary>
[AttributeUsage(AttributeTargets.Class | AttributeTargets.Method)]
public sealed class RequiresSchoolFeaturesAttribute : Attribute, IAsyncActionFilter
{
    public async Task OnActionExecutionAsync(ActionExecutingContext context, ActionExecutionDelegate next)
    {
        var settings = await context.HttpContext.RequestServices.GetRequiredService<ICompanySettingsService>().GetAsync();
        if (!settings.SchoolFeaturesEnabled)
        {
            context.Result = new NotFoundObjectResult(new { message = "School features are not turned on for this company." });
            return;
        }
        await next();
    }
}

/// <summary>Who takes part in a thread: for live updates and "Seen" ticks.</summary>
public static class SchoolParticipants
{
    /// <summary>Logins of the child's active parents.</summary>
    public static Task<List<int>> ParentUserIdsAsync(HrmsDbContext db, int studentId) =>
        db.StudentParents
            .Where(sp => sp.StudentId == studentId && sp.Parent.IsActive && sp.Parent.UserId != null)
            .Select(sp => sp.Parent.UserId!.Value)
            .ToListAsync();

    /// <summary>
    /// Staff logins that see the thread: all active admins, plus for "Teacher" threads every teacher
    /// of the class — the lead and the other teachers.
    /// </summary>
    public static async Task<List<int>> StaffUserIdsAsync(HrmsDbContext db, string kind, int? classId)
    {
        var ids = await db.Users.Where(u => u.Role == "Admin" && u.IsActive).Select(u => u.Id).ToListAsync();
        if (kind == Conversation.Teacher && classId != null)
        {
            var lead = await db.SchoolClasses
                .Where(c => c.Id == classId && c.ClassTeacher != null)
                .Select(c => c.ClassTeacher!.Email.ToLower())
                .ToListAsync();
            var others = await db.SchoolClassTeachers
                .Where(t => t.ClassId == classId && t.Employee.IsActive)
                .Select(t => t.Employee.Email.ToLower())
                .ToListAsync();
            var emails = lead.Concat(others).Where(e => !string.IsNullOrEmpty(e)).Distinct().ToList();
            if (emails.Count > 0)
                ids.AddRange(await db.Users
                    .Where(u => u.IsActive && emails.Contains(u.Email.ToLower()))
                    .Select(u => u.Id).ToListAsync());
        }
        return ids.Distinct().ToList();
    }
}
