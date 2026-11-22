using System.ComponentModel.DataAnnotations;
using System.Security.Claims;
using HrmsApi.Data;
using HrmsApi.Hubs;
using HrmsApi.Models;
using HrmsApi.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Net.Http.Headers;

namespace HrmsApi.Controllers;

/// <summary>
/// School announcements: the office (admins) posts to every parent or one class; a class
/// teacher posts to their own classes. Parents see the ones for the whole school and for
/// their children's classes, get an in-app notification, and their reading is counted.
/// </summary>
[ApiController]
[Route("api/school/announcements")]
[Authorize]
[RequiresSchoolFeatures]
public class AnnouncementsController : ControllerBase
{
    private readonly HrmsDbContext _db;
    private readonly IChatNotifier _live;
    private readonly IPushService _push;
    private readonly IAuditService _audit;

    public AnnouncementsController(HrmsDbContext db, IChatNotifier live, IPushService push, IAuditService audit)
    {
        _db = db; _live = live; _push = push; _audit = audit;
    }

    /// <summary>GET /api/school/announcements — newest first, the ones this user may see.</summary>
    [HttpGet]
    public async Task<IActionResult> GetAll([FromQuery] int take = 100)
    {
        var me = await SchoolViewer.LoadAsync(_db, User);
        if (me == null || (!me.IsStaff && !me.IsParent)) return Forbid();

        var q = Visible(me);
        var list = await q.OrderByDescending(a => a.CreatedAt).Take(Math.Clamp(take, 1, 500))
            .Select(a => new
            {
                a.Id, a.Title, a.Body, a.ClassId, a.CreatedByUserId, a.CreatedByName, a.CreatedAt,
                className  = a.Class != null ? a.Class.Name : null,
                attachment = a.AttachmentName == null ? null : new { name = a.AttachmentName, contentType = a.AttachmentContentType, size = a.AttachmentSize },
                isRead     = _db.AnnouncementReads.Any(r => r.AnnouncementId == a.Id && r.UserId == me.UserId),
                readCount  = _db.AnnouncementReads.Count(r => r.AnnouncementId == a.Id)
            }).ToListAsync();

        // Staff see how many parents it reached: "read by 12 of 30"
        Dictionary<int, int>? audience = null;
        if (me.IsStaff)
        {
            audience = new();
            var allParents = await AudienceUserIds(null).CountAsync();
            foreach (var classId in list.Where(a => a.ClassId != null).Select(a => a.ClassId!.Value).Distinct())
                audience[classId] = await AudienceUserIds(classId).CountAsync();
            audience[0] = allParents;
        }

        return Ok(list.Select(a => new
        {
            a.Id, a.Title, a.Body, a.ClassId, a.className, a.CreatedByName, a.CreatedAt, a.attachment,
            a.isRead,
            canDelete     = me.IsAdmin || a.CreatedByUserId == me.UserId,
            readCount     = me.IsStaff ? a.readCount : (int?)null,
            audienceCount = audience == null ? (int?)null : audience[a.ClassId ?? 0]
        }));
    }

    /// <summary>GET /api/school/announcements/unread-count — parents: announcements not opened yet.</summary>
    [HttpGet("unread-count")]
    public async Task<IActionResult> UnreadCount()
    {
        var me = await SchoolViewer.LoadAsync(_db, User);
        if (me == null || !me.IsParent) return Ok(new { count = 0 });
        var count = await Visible(me).CountAsync(a => !_db.AnnouncementReads.Any(r => r.AnnouncementId == a.Id && r.UserId == me.UserId));
        return Ok(new { count });
    }

    /// <summary>
    /// POST /api/school/announcements (multipart: title, body, classId?, file?) — publish now.
    /// Admins: any audience. Class teachers: one of their classes.
    /// </summary>
    [HttpPost]
    [RequestSizeLimit(ChatMessage.MaxAttachmentBytes + 256 * 1024)]
    public async Task<IActionResult> Create([FromForm] AnnouncementForm form)
    {
        var me = await SchoolViewer.LoadAsync(_db, User);
        if (me == null || !me.IsStaff) return Forbid();

        var title = (form.Title ?? "").Trim();
        var body  = (form.Body ?? "").Trim();
        if (title.Length == 0) return BadRequest(new { message = "Enter a title.", field = "title" });
        if (title.Length > 150) return BadRequest(new { message = "Keep the title under 150 characters.", field = "title" });
        if (body.Length == 0) return BadRequest(new { message = "Write the announcement.", field = "body" });
        if (body.Length > 4000) return BadRequest(new { message = "Keep the announcement under 4000 characters.", field = "body" });

        string? className = null;
        if (form.ClassId != null)
        {
            className = await _db.SchoolClasses.Where(c => c.Id == form.ClassId).Select(c => c.Name).FirstOrDefaultAsync();
            if (className == null) return BadRequest(new { message = "Choose a class.", field = "classId" });
        }
        if (!me.IsAdmin && (form.ClassId == null || !me.TeacherClassIds.Contains(form.ClassId.Value)))
            return BadRequest(new { message = "Teachers can post to their own classes only.", field = "classId" });

        var a = new Announcement
        {
            Title = title, Body = body, ClassId = form.ClassId,
            CreatedByUserId = me.UserId, CreatedByName = me.Name, CreatedAt = DateTime.UtcNow
        };
        if (form.File != null && form.File.Length > 0)
        {
            var (file, error) = await ChatFiles.ReadAsync(form.File);
            if (error != null) return BadRequest(new { message = error, field = "file" });
            (a.AttachmentName, a.AttachmentContentType, a.AttachmentSize, a.AttachmentData) = file!.Value;
        }
        _db.Announcements.Add(a);
        await _db.SaveChangesAsync();

        // In-app notification + phone push to every parent in the audience
        var parents = await AudienceUserIds(a.ClassId).ToListAsync();
        var who = className == null ? "School announcement" : $"{className} announcement";
        foreach (var uid in parents)
            _db.Notifications.Add(new Notification
            {
                UserId = uid, Title = Trim(title, 100), Message = Trim($"{who}: {body}", 500),
                Type = "school_announcement", Link = "/parent/announcements", CreatedAt = DateTime.UtcNow
            });
        await _db.SaveChangesAsync();
        await _push.SendToUsersAsync(_db, parents, title, $"{who} from {me.Name}", "school_announcement", "/parent/announcements");
        await _live.SendAsync(parents, "announcement", new { a.Id, a.Title, className });

        await _audit.LogAsync("Created", "Announcement", a.Id.ToString(),
            $"Posted announcement \"{a.Title}\" to {(className ?? "all parents")} ({parents.Count} parent logins)",
            User.Identity?.Name ?? "unknown", me.UserId, null, null, HttpContext.Connection.RemoteIpAddress?.ToString());
        return Ok(new { a.Id, sentTo = parents.Count });
    }

    /// <summary>POST /api/school/announcements/{id}/read — a parent opened it.</summary>
    [HttpPost("{id:int}/read")]
    public async Task<IActionResult> MarkRead(int id)
    {
        var me = await SchoolViewer.LoadAsync(_db, User);
        if (me == null) return Forbid();
        if (!await Visible(me).AnyAsync(a => a.Id == id)) throw new KeyNotFoundException("Announcement not found.");
        if (!await _db.AnnouncementReads.AnyAsync(r => r.AnnouncementId == id && r.UserId == me.UserId))
        {
            _db.AnnouncementReads.Add(new AnnouncementRead { AnnouncementId = id, UserId = me.UserId, ReadAt = DateTime.UtcNow });
            try { await _db.SaveChangesAsync(); }
            catch (DbUpdateException) { /* opened twice at the same moment */ }
        }
        return NoContent();
    }

    /// <summary>GET /api/school/announcements/{id}/attachment — the photo or PDF (anyone who may see the announcement).</summary>
    [HttpGet("{id:int}/attachment")]
    public async Task<IActionResult> Attachment(int id)
    {
        var me = await SchoolViewer.LoadAsync(_db, User);
        if (me == null) return Forbid();
        var a = await Visible(me).Where(x => x.Id == id)
            .Select(x => new { x.AttachmentName, x.AttachmentContentType, x.AttachmentData })
            .FirstOrDefaultAsync();
        if (a?.AttachmentData == null) throw new KeyNotFoundException("No attachment.");
        return ChatFiles.Inline(Response, this, a.AttachmentName!, a.AttachmentContentType!, a.AttachmentData);
    }

    /// <summary>DELETE /api/school/announcements/{id} — admins, or the teacher who posted it.</summary>
    [HttpDelete("{id:int}")]
    public async Task<IActionResult> Delete(int id)
    {
        var me = await SchoolViewer.LoadAsync(_db, User);
        var a = await _db.Announcements.FindAsync(id) ?? throw new KeyNotFoundException("Announcement not found.");
        if (me == null || !(me.IsAdmin || (me.IsTeacher && a.CreatedByUserId == me.UserId))) return Forbid();
        _db.Announcements.Remove(a);
        await _db.SaveChangesAsync();
        await _audit.LogAsync("Deleted", "Announcement", id.ToString(), $"Deleted announcement \"{a.Title}\"",
            User.Identity?.Name ?? "unknown", me.UserId, null, null, HttpContext.Connection.RemoteIpAddress?.ToString());
        return NoContent();
    }

    // ── helpers ──

    /// <summary>Admins: all. Teachers: whole-school ones and their classes'. Parents: whole-school ones and their children's classes'.</summary>
    private IQueryable<Announcement> Visible(SchoolViewer me)
    {
        var q = _db.Announcements.AsNoTracking();
        if (me.IsAdmin) return q;
        if (me.IsParent)
        {
            var classIds = _db.Students.Where(s => me.ChildIds.Contains(s.Id) && s.ClassId != null).Select(s => s.ClassId!.Value);
            return q.Where(a => a.ClassId == null || classIds.Contains(a.ClassId.Value));
        }
        if (me.IsTeacher) return q.Where(a => a.ClassId == null || me.TeacherClassIds.Contains(a.ClassId.Value));
        return q.Where(_ => false);
    }

    /// <summary>Logins of active parents with an active child in the class (or in the school).</summary>
    private IQueryable<int> AudienceUserIds(int? classId) =>
        _db.Parents
            .Where(p => p.IsActive && p.UserId != null && p.User!.IsActive
                && p.Children.Any(c => c.Student.IsActive && (classId == null || c.Student.ClassId == classId)))
            .Select(p => p.UserId!.Value);

    private static string Trim(string s, int max) => s.Length <= max ? s : s[..(max - 1)] + "…";
}

public class AnnouncementForm
{
    public string? Title { get; set; }
    public string? Body { get; set; }
    public int? ClassId { get; set; }
    public IFormFile? File { get; set; }
}

/// <summary>Photos and PDFs sent with messages and announcements.</summary>
public static class ChatFiles
{
    /// <summary>Reads and checks an upload: PDF, JPG or PNG (by content), at most 5 MB.</summary>
    public static async Task<((string name, string? type, int? size, byte[] data)? file, string? error)> ReadAsync(IFormFile upload)
    {
        if (upload.Length > ChatMessage.MaxAttachmentBytes) return (null, "The file must be 5 MB or smaller.");
        using var ms = new MemoryStream();
        await upload.CopyToAsync(ms);
        var bytes = ms.ToArray();
        var type = LeaveAttachment.DetectType(bytes);
        if (type == null) return (null, "Attach a photo (JPG, PNG) or a PDF.");
        var name = Path.GetFileName(upload.FileName ?? "file");
        if (string.IsNullOrWhiteSpace(name)) name = "file";
        if (name.Length > 200) name = name[^200..];
        return ((name, type, bytes.Length, bytes), null);
    }

    /// <summary>Shown in the browser, never cached by shared caches.</summary>
    public static IActionResult Inline(HttpResponse response, ControllerBase controller, string name, string type, byte[] data)
    {
        response.Headers[HeaderNames.CacheControl] = "private, no-store";
        response.Headers["X-Content-Type-Options"] = "nosniff";
        var cd = new ContentDispositionHeaderValue("inline");
        cd.SetHttpFileName(name);
        response.Headers[HeaderNames.ContentDisposition] = cd.ToString();
        return controller.File(data, type);
    }
}
