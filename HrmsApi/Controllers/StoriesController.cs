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
/// Class stories: a class teacher (or the office) shares photos and videos with every parent of a
/// class — the office may also post to the whole school. Flow: create (draft) → upload files one by
/// one → publish (parents get a notification). Parents view and download; stories are kept until
/// deleted. Files live on disk (<see cref="IMediaStore"/>); each media item in a response carries a
/// signed link (valid 12 h) so image tags and video players can load it without the login token.
/// </summary>
[ApiController]
[Route("api/school/stories")]
[Authorize]
[RequiresSchoolFeatures]
public class StoriesController : ControllerBase
{
    private const string MediaKind = "story";
    private static readonly TimeSpan LinkLifetime = TimeSpan.FromHours(12);

    private readonly HrmsDbContext _db;
    private readonly IMediaStore _media;
    private readonly IPushService _push;
    private readonly IChatNotifier _live;
    private readonly IAuditService _audit;

    public StoriesController(HrmsDbContext db, IMediaStore media, IPushService push, IChatNotifier live, IAuditService audit)
    {
        _db = db; _media = media; _push = push; _live = live; _audit = audit;
    }

    /// <summary>GET /api/school/stories?classId=&amp;skip=&amp;take= — newest first, the ones this user may see.</summary>
    [HttpGet]
    public async Task<IActionResult> GetAll([FromQuery] int? classId, [FromQuery] int skip = 0, [FromQuery] int take = 20)
    {
        var me = await SchoolViewer.LoadAsync(_db, User);
        if (me == null || (!me.IsStaff && !me.IsParent)) return Forbid();
        var q = Visible(me);
        if (classId != null) q = q.Where(s => s.ClassId == classId);
        var rows = await q.OrderByDescending(s => s.PublishedAt ?? s.CreatedAt).ThenByDescending(s => s.Id)
            .Skip(Math.Max(0, skip)).Take(Math.Clamp(take, 1, 50))
            .Include(s => s.Class).Include(s => s.Media).AsSplitQuery().ToListAsync();
        return Ok(rows.Select(s => Dto(s, me)));
    }

    [HttpGet("{id:int}")]
    public async Task<IActionResult> Get(int id)
    {
        var me = await SchoolViewer.LoadAsync(_db, User);
        if (me == null) return Forbid();
        var s = await Visible(me).Include(x => x.Class).Include(x => x.Media).FirstOrDefaultAsync(x => x.Id == id)
                ?? throw new KeyNotFoundException("Story not found.");
        return Ok(Dto(s, me));
    }

    /// <summary>GET /api/school/stories/classes — classes this user may post to (admins: all + whole school).</summary>
    [HttpGet("classes")]
    public async Task<IActionResult> PostableClasses()
    {
        var me = await SchoolViewer.LoadAsync(_db, User);
        if (me == null || !me.IsStaff) return Ok(new { wholeSchool = false, classes = Array.Empty<object>() });
        var q = _db.SchoolClasses.AsNoTracking().Where(c => c.IsActive);
        if (!me.IsAdmin) q = q.Where(c => me.TeacherClassIds.Contains(c.Id));
        var classes = await q.OrderBy(c => c.SortOrder).ThenBy(c => c.Name).Select(c => new { c.Id, c.Name }).ToListAsync();
        return Ok(new { wholeSchool = me.IsAdmin, classes });
    }

    /// <summary>POST /api/school/stories — a draft for a class (teachers: their own classes; office: any, or the whole school).</summary>
    [HttpPost]
    public async Task<IActionResult> Create([FromBody] StoryRequest req)
    {
        var me = await SchoolViewer.LoadAsync(_db, User);
        if (me == null || !me.IsStaff) return Forbid();
        var error = await CheckAudienceAsync(me, req.ClassId) ?? CheckCaption(req.Caption);
        if (error != null) return BadRequest(new { message = error });

        var s = new Story
        {
            ClassId = req.ClassId, Caption = Clean(req.Caption),
            CreatedByUserId = me.UserId, CreatedByName = me.Name, CreatedAt = DateTime.UtcNow
        };
        _db.Stories.Add(s);
        await _db.SaveChangesAsync();
        return Ok(new { s.Id });
    }

    /// <summary>PUT /api/school/stories/{id} — change the caption or class (author or office).</summary>
    [HttpPut("{id:int}")]
    public async Task<IActionResult> Update(int id, [FromBody] StoryRequest req)
    {
        var (me, s, denied) = await EditableAsync(id);
        if (denied != null) return denied;
        // A published story keeps its audience (the parents were already told)
        if (s!.PublishedAt == null && req.ClassId != s.ClassId)
        {
            var error = await CheckAudienceAsync(me!, req.ClassId);
            if (error != null) return BadRequest(new { message = error });
            s.ClassId = req.ClassId;
        }
        var captionError = CheckCaption(req.Caption);
        if (captionError != null) return BadRequest(new { message = captionError });
        s.Caption = Clean(req.Caption);
        await _db.SaveChangesAsync();
        return Ok(new { s.Id });
    }

    /// <summary>POST /api/school/stories/{id}/media (multipart "file") — one photo (JPG/PNG, 10 MB) or video (MP4/MOV/WebM, 100 MB).</summary>
    [HttpPost("{id:int}/media")]
    [RequestSizeLimit(Story.MaxVideoBytes + 1024 * 1024)]
    [RequestFormLimits(MultipartBodyLengthLimit = Story.MaxVideoBytes + 1024 * 1024)]
    public async Task<IActionResult> AddMedia(int id, IFormFile file, CancellationToken ct)
    {
        var (_, s, denied) = await EditableAsync(id);
        if (denied != null) return denied;
        if (file == null || file.Length == 0) return BadRequest(new { message = "Choose a photo or video." });
        var count = await _db.StoryMedia.CountAsync(m => m.StoryId == id, ct);
        if (count >= Story.MaxMedia) return BadRequest(new { message = $"A story can have at most {Story.MaxMedia} photos and videos." });
        if (file.Length > Story.MaxVideoBytes) return BadRequest(new { message = "Videos must be 100 MB or smaller. Trim the video, or share a shorter one." });

        // Type from the file's first bytes, never from its name
        var head = new byte[16];
        await using (var peek = file.OpenReadStream()) { _ = await peek.ReadAtLeastAsync(head, head.Length, false, ct); }
        var (kind, type, ext) = Detect(head);
        if (kind == null) return BadRequest(new { message = "Add photos (JPG, PNG) or videos (MP4, MOV, WebM)." });
        if (kind == StoryMedia.Photo && file.Length > Story.MaxPhotoBytes) return BadRequest(new { message = "Photos must be 10 MB or smaller." });

        string path; long size;
        try
        {
            await using var stream = file.OpenReadStream();
            (path, size) = await _media.SaveAsync($"{_media.CompanyFolder}/stories/{id}", ext!, stream,
                kind == StoryMedia.Photo ? Story.MaxPhotoBytes : Story.MaxVideoBytes, ct);
        }
        catch (InvalidOperationException)
        {
            return BadRequest(new { message = "The file is too large." });
        }

        var name = Path.GetFileName(file.FileName ?? "file");
        if (string.IsNullOrWhiteSpace(name)) name = kind == StoryMedia.Photo ? "photo" + ext : "video" + ext;
        if (name.Length > 200) name = name[^200..];
        var m = new StoryMedia
        {
            StoryId = id, Kind = kind, FileName = name, ContentType = type!, SizeBytes = size,
            StoragePath = path, SortOrder = count, CreatedAt = DateTime.UtcNow
        };
        _db.StoryMedia.Add(m);
        await _db.SaveChangesAsync(ct);
        return Ok(MediaDto(m));
    }

    [HttpDelete("media/{mediaId:int}")]
    public async Task<IActionResult> DeleteMedia(int mediaId)
    {
        var m = await _db.StoryMedia.FirstOrDefaultAsync(x => x.Id == mediaId) ?? throw new KeyNotFoundException("File not found.");
        var (_, _, denied) = await EditableAsync(m.StoryId);
        if (denied != null) return denied;
        _db.StoryMedia.Remove(m);
        await _db.SaveChangesAsync();
        _media.Delete(m.StoragePath);
        return NoContent();
    }

    /// <summary>POST /api/school/stories/{id}/publish — parents of the class (or school) see it and get a notification.</summary>
    [HttpPost("{id:int}/publish")]
    public async Task<IActionResult> Publish(int id)
    {
        var (me, s, denied) = await EditableAsync(id);
        if (denied != null) return denied;
        if (s!.PublishedAt != null) return Ok(new { s.Id, sentTo = 0 });
        var photos = await _db.StoryMedia.CountAsync(m => m.StoryId == id && m.Kind == StoryMedia.Photo);
        var videos = await _db.StoryMedia.CountAsync(m => m.StoryId == id && m.Kind == StoryMedia.Video);
        if (photos + videos == 0) return BadRequest(new { message = "Add at least one photo or video first." });

        s.PublishedAt = DateTime.UtcNow;
        await _db.SaveChangesAsync();

        var className = s.ClassId == null ? null : await _db.SchoolClasses.Where(c => c.Id == s.ClassId).Select(c => c.Name).FirstOrDefaultAsync();
        var parents = await _db.Parents
            .Where(p => p.IsActive && p.UserId != null && p.User!.IsActive
                && p.Children.Any(c => c.Student.IsActive && (s.ClassId == null || c.Student.ClassId == s.ClassId)))
            .Select(p => p.UserId!.Value).ToListAsync();
        var what = string.Join(" and ", new[] { photos > 0 ? $"{photos} photo{(photos == 1 ? "" : "s")}" : null,
                                                videos > 0 ? $"{videos} video{(videos == 1 ? "" : "s")}" : null }.Where(x => x != null));
        await SchoolAlerts.SendAsync(_db, _push, _live, parents,
            $"New story{(className != null ? " · " + className : "")}",
            $"{me!.Name} shared {what}{(string.IsNullOrEmpty(s.Caption) ? "" : ": " + s.Caption)}",
            "school_story", "/parent/stories", "story", new { s.Id, className });

        await _audit.LogAsync("Created", "Story", s.Id.ToString(),
            $"Published story ({what}) to {className ?? "the whole school"} ({parents.Count} parent logins)",
            User.Identity?.Name ?? "unknown", me.UserId, null, null, HttpContext.Connection.RemoteIpAddress?.ToString());
        return Ok(new { s.Id, sentTo = parents.Count });
    }

    /// <summary>DELETE /api/school/stories/{id} — the story and its files (author or office).</summary>
    [HttpDelete("{id:int}")]
    public async Task<IActionResult> Delete(int id)
    {
        var (me, s, denied) = await EditableAsync(id);
        if (denied != null) return denied;
        _db.Stories.Remove(s!);
        await _db.SaveChangesAsync();
        _media.DeleteFolder($"{_media.CompanyFolder}/stories/{id}");
        await _audit.LogAsync("Deleted", "Story", id.ToString(), "Deleted a class story",
            User.Identity?.Name ?? "unknown", me!.UserId, null, null, HttpContext.Connection.RemoteIpAddress?.ToString());
        return NoContent();
    }

    /// <summary>
    /// GET /api/school/stories/media/{mediaId}?exp=&amp;sig=[&amp;download=1] — the file, with range
    /// support (video seeking). A valid signed link from a story response, or a login that may see it.
    /// </summary>
    [HttpGet("media/{mediaId:int}")]
    [AllowAnonymous]
    public async Task<IActionResult> GetMedia(int mediaId, [FromQuery] long exp, [FromQuery] string? sig, [FromQuery] bool download = false)
    {
        var m = await _db.StoryMedia.AsNoTracking().Include(x => x.Story).FirstOrDefaultAsync(x => x.Id == mediaId)
                ?? throw new KeyNotFoundException("File not found.");
        if (!_media.Verify(MediaKind, mediaId, exp, sig))
        {
            var me = User.Identity?.IsAuthenticated == true ? await SchoolViewer.LoadAsync(_db, User) : null;
            if (me == null) return Unauthorized();
            if (!await Visible(me).AnyAsync(s => s.Id == m.StoryId)) return Forbid();
        }
        var full = _media.FullPath(m.StoragePath) ?? throw new KeyNotFoundException("The file is missing.");

        Response.Headers[HeaderNames.CacheControl] = "private, max-age=43200";
        Response.Headers["X-Content-Type-Options"] = "nosniff";
        var cd = new ContentDispositionHeaderValue(download ? "attachment" : "inline");
        cd.SetHttpFileName(m.FileName);
        Response.Headers[HeaderNames.ContentDisposition] = cd.ToString();
        return PhysicalFile(full, m.ContentType, enableRangeProcessing: true);
    }

    // ── helpers ──

    /// <summary>
    /// Published stories for the whole school or the user's classes (parents: their children's
    /// classes); drafts only to their author and the office.
    /// </summary>
    private IQueryable<Story> Visible(SchoolViewer me)
    {
        var q = _db.Stories.AsNoTracking();
        if (me.IsAdmin) return q;
        if (me.IsParent)
        {
            var classIds = _db.Students.Where(s => me.ChildIds.Contains(s.Id) && s.ClassId != null).Select(s => s.ClassId!.Value);
            return q.Where(s => s.PublishedAt != null && (s.ClassId == null || classIds.Contains(s.ClassId.Value)));
        }
        if (me.IsTeacher)
            return q.Where(s => (s.PublishedAt != null || s.CreatedByUserId == me.UserId)
                                && (s.ClassId == null || me.TeacherClassIds.Contains(s.ClassId.Value)));
        return q.Where(_ => false);
    }

    private async Task<(SchoolViewer? me, Story? story, IActionResult? denied)> EditableAsync(int id)
    {
        var me = await SchoolViewer.LoadAsync(_db, User);
        var s = await _db.Stories.FirstOrDefaultAsync(x => x.Id == id) ?? throw new KeyNotFoundException("Story not found.");
        if (me == null || !(me.IsAdmin || (me.IsTeacher && s.CreatedByUserId == me.UserId))) return (me, s, Forbid());
        return (me, s, null);
    }

    private async Task<string?> CheckAudienceAsync(SchoolViewer me, int? classId)
    {
        if (classId == null) return me.IsAdmin ? null : "Choose one of your classes.";
        if (!await _db.SchoolClasses.AnyAsync(c => c.Id == classId)) return "Choose a class.";
        return me.IsAdmin || me.TeacherClassIds.Contains(classId.Value) ? null : "Teachers can post to their own classes only.";
    }

    private static string? CheckCaption(string? caption) =>
        (caption?.Trim().Length ?? 0) > 2000 ? "Keep the caption under 2000 characters." : null;

    private static string? Clean(string? caption) => string.IsNullOrWhiteSpace(caption) ? null : caption.Trim();

    /// <summary>(kind, content type, extension) from the first bytes; nulls when not a supported photo / video.</summary>
    private static (string? kind, string? type, string? ext) Detect(byte[] b)
    {
        if (b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) return (StoryMedia.Photo, "image/jpeg", ".jpg");
        if (b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) return (StoryMedia.Photo, "image/png", ".png");
        if (b[0] == 0x1A && b[1] == 0x45 && b[2] == 0xDF && b[3] == 0xA3) return (StoryMedia.Video, "video/webm", ".webm");
        if (b[4] == (byte)'f' && b[5] == (byte)'t' && b[6] == (byte)'y' && b[7] == (byte)'p')
        {
            var brand = System.Text.Encoding.ASCII.GetString(b, 8, 4);
            if (brand is "heic" or "heix" or "mif1" or "msf1" or "avif") return (null, null, null);   // HEIC/AVIF photos: not shown by most browsers
            return brand == "qt  " ? (StoryMedia.Video, "video/quicktime", ".mov") : (StoryMedia.Video, "video/mp4", ".mp4");
        }
        return (null, null, null);
    }

    private object MediaDto(StoryMedia m)
    {
        var url = $"school/stories/media/{m.Id}?{_media.Sign(MediaKind, m.Id, LinkLifetime)}";
        return new { m.Id, m.Kind, m.FileName, m.ContentType, m.SizeBytes, url, downloadUrl = url + "&download=1" };
    }

    private object Dto(Story s, SchoolViewer me) => new
    {
        s.Id, s.ClassId, className = s.Class?.Name, s.Caption, s.CreatedByName, s.CreatedAt, s.PublishedAt,
        canEdit = me.IsAdmin || (me.IsTeacher && s.CreatedByUserId == me.UserId),
        media = s.Media.OrderBy(m => m.SortOrder).ThenBy(m => m.Id).Select(MediaDto).ToList()
    };
}

public class StoryRequest
{
    /// <summary>Null = the whole school (office only).</summary>
    public int? ClassId { get; set; }
    public string? Caption { get; set; }
}
