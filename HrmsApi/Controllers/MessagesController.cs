using System.Security.Claims;
using HrmsApi.Data;
using HrmsApi.Hubs;
using HrmsApi.Models;
using HrmsApi.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace HrmsApi.Controllers;

/// <summary>
/// Parent ↔ school messages. One thread per child and kind: "Teacher" (the child's class
/// teacher) and "Office" (the admins). Both parents of a child share the thread.
/// Who may read/write: <see cref="SchoolViewer.CanAccessConversation"/> — checked on every call.
/// New messages reach the other side live (<see cref="ChatHub"/>) and as a phone push.
/// </summary>
[ApiController]
[Route("api/school")]
[Authorize]
[RequiresSchoolFeatures]
public class MessagesController : ControllerBase
{
    private const int PageSize = 50;

    private readonly HrmsDbContext _db;
    private readonly IChatNotifier _live;
    private readonly IPushService _push;

    public MessagesController(HrmsDbContext db, IChatNotifier live, IPushService push)
    {
        _db = db; _live = live; _push = push;
    }

    /// <summary>
    /// GET /api/school/conversations — the threads this user sees, latest activity first.
    /// Parents always see both threads (class teacher, office) for each child, even before the
    /// first message. Staff see threads that have messages.
    /// </summary>
    [HttpGet("conversations")]
    public async Task<IActionResult> List()
    {
        var me = await SchoolViewer.LoadAsync(_db, User);
        if (me == null || (!me.IsStaff && !me.IsParent)) return Forbid();

        if (me.IsParent) await EnsureParentThreadsAsync(me);

        var q = Accessible(me);
        if (!me.IsParent) q = q.Where(c => c.LastMessageAt != null);

        var rows = await q
            .Select(c => new
            {
                c.Id, c.Kind, c.StudentId, c.LastMessageAt,
                studentName = c.Student.FullName,
                className   = c.Student.Class != null ? c.Student.Class.Name : null,
                teacherName = c.Student.Class != null && c.Student.Class.ClassTeacher != null ? c.Student.Class.ClassTeacher.Name : null,
                parentNames = c.Student.Parents.Where(p => p.Parent.IsActive).Select(p => p.Parent.FullName).ToList(),
                last = c.Messages.OrderByDescending(m => m.Id)
                    .Select(m => new { m.Body, m.SenderName, m.SenderUserId, hasAttachment = m.Attachment != null })
                    .FirstOrDefault(),
                unread = c.Messages.Count(m => m.SenderUserId != me.UserId
                    && m.Id > (_db.ConversationReads.Where(r => r.ConversationId == c.Id && r.UserId == me.UserId)
                        .Select(r => (int?)r.LastReadMessageId).FirstOrDefault() ?? 0)),
            })
            .ToListAsync();

        return Ok(rows
            .Select(r => new
            {
                r.Id, r.Kind, r.StudentId, r.studentName, r.className, r.LastMessageAt,
                title = r.Kind == Conversation.Office ? "School office"
                      : r.teacherName != null ? $"Class teacher · {r.teacherName}" : "Class teacher",
                r.teacherName, r.parentNames,
                lastMessage = r.last == null ? null : new
                {
                    text = r.last.Body.Length > 0 ? r.last.Body : r.last.hasAttachment ? "📎 Attachment" : "",
                    senderName = r.last.SenderName,
                    mine = r.last.SenderUserId == me.UserId
                },
                r.unread
            })
            .OrderByDescending(r => r.LastMessageAt ?? DateTime.MinValue)
            .ThenBy(r => r.studentName).ThenBy(r => r.Kind));
    }

    /// <summary>GET /api/school/messages/unread-count — for the menu badge.</summary>
    [HttpGet("messages/unread-count")]
    public async Task<IActionResult> UnreadCount()
    {
        var me = await SchoolViewer.LoadAsync(_db, User);
        if (me == null || (!me.IsStaff && !me.IsParent)) return Ok(new { count = 0 });

        // Admins oversee every thread but are asked to answer only the office ones;
        // a class teacher who is also an admin counts their class threads too.
        var q = Accessible(me);
        if (me.IsAdmin && !me.IsParent)
            q = q.Where(c => c.Kind == Conversation.Office
                || (c.Student.ClassId != null && me.TeacherClassIds.Contains(c.Student.ClassId.Value)));

        var count = await q.SelectMany(c => c.Messages
                .Where(m => m.SenderUserId != me.UserId
                    && m.Id > (_db.ConversationReads.Where(r => r.ConversationId == c.Id && r.UserId == me.UserId)
                        .Select(r => (int?)r.LastReadMessageId).FirstOrDefault() ?? 0)))
            .CountAsync();
        return Ok(new { count });
    }

    /// <summary>
    /// POST /api/school/conversations/open { studentId, kind } — the thread for a child, created
    /// on first use. Staff use it to start a conversation with a child's parents.
    /// </summary>
    [HttpPost("conversations/open")]
    public async Task<IActionResult> Open([FromBody] OpenConversationRequest req)
    {
        var me = await SchoolViewer.LoadAsync(_db, User);
        if (me == null) return Forbid();
        if (!Conversation.Kinds.Contains(req.Kind)) return BadRequest(new { message = "Choose class teacher or office." });

        var student = await _db.Students.AsNoTracking().Where(s => s.Id == req.StudentId)
            .Select(s => new { s.Id, s.ClassId, s.IsActive }).FirstOrDefaultAsync()
            ?? throw new KeyNotFoundException("Child not found.");
        if (!me.CanAccessConversation(req.Kind, student.Id, student.ClassId)) return Forbid();

        var conv = await GetOrCreateAsync(student.Id, req.Kind);
        return Ok(new { conv.Id });
    }

    /// <summary>
    /// GET /api/school/conversations/{id}/messages?before= — up to 50 messages (oldest first),
    /// older ones with ?before=&lt;oldest id&gt;. Also returns how far the other side has read.
    /// </summary>
    [HttpGet("conversations/{id:int}/messages")]
    public async Task<IActionResult> Messages(int id, [FromQuery] int? before)
    {
        var (me, conv, classId) = await LoadAsync(id);
        if (me == null) return Forbid();

        var q = _db.ChatMessages.AsNoTracking().Where(m => m.ConversationId == id);
        if (before != null) q = q.Where(m => m.Id < before);
        var page = await q.OrderByDescending(m => m.Id).Take(PageSize + 1).Select(MessageDto.Projection).ToListAsync();
        var hasMore = page.Count > PageSize;
        page = page.Take(PageSize).OrderBy(m => m.Id).ToList();

        return Ok(new
        {
            conversation = await HeaderAsync(conv!, classId),
            messages = page,
            hasMore,
            seenUpTo = await SeenUpToAsync(conv!, classId, me)
        });
    }

    /// <summary>
    /// POST /api/school/conversations/{id}/messages (multipart: body, file?) — send. Text up to
    /// 4000 characters and/or one photo or PDF (5 MB).
    /// </summary>
    [HttpPost("conversations/{id:int}/messages")]
    [RequestSizeLimit(ChatMessage.MaxAttachmentBytes + 256 * 1024)]
    public async Task<IActionResult> Send(int id, [FromForm] SendMessageForm form)
    {
        var (me, conv, classId) = await LoadAsync(id, tracking: true);
        if (me == null) return Forbid();

        var body = (form.Body ?? "").Trim();
        if (body.Length > ChatMessage.MaxBodyLength) return BadRequest(new { message = "The message is too long (4000 characters at most)." });
        var hasFile = form.File != null && form.File.Length > 0;
        if (body.Length == 0 && !hasFile) return BadRequest(new { message = "Write a message or attach a file." });

        var msg = new ChatMessage
        {
            ConversationId = id, SenderUserId = me.UserId, SenderName = me.Name,
            SenderRole = SenderRoleIn(me, conv!.Kind), Body = body, SentAt = DateTime.UtcNow
        };
        if (hasFile)
        {
            var (file, error) = await ChatFiles.ReadAsync(form.File!);
            if (error != null) return BadRequest(new { message = error });
            var f = file!.Value;
            msg.Attachment = new ChatAttachment { FileName = f.name, ContentType = f.type!, SizeBytes = f.size ?? 0, Data = f.data };
        }
        _db.ChatMessages.Add(msg);
        conv.LastMessageAt = msg.SentAt;
        await _db.SaveChangesAsync();

        // The sender has read everything up to their own message
        await MarkReadAsync(id, me.UserId, msg.Id);

        var dto = MessageDto.From(msg);
        var parents = await SchoolParticipants.ParentUserIdsAsync(_db, conv.StudentId);
        var staff   = await SchoolParticipants.StaffUserIdsAsync(_db, conv.Kind, classId);
        await _live.SendAsync(parents.Concat(staff), "message", new { conversationId = id, message = dto });

        // Phone push to the other side (the web app shows the unread badge instead)
        var studentName = await _db.Students.Where(s => s.Id == conv.StudentId).Select(s => s.FullName).FirstAsync();
        var recipients = me.IsParent
            ? (conv.Kind == Conversation.Office ? await AdminIdsAsync() : staff.Except(await AdminIdsAsync()).ToList())
            : parents;
        await _push.SendToUsersAsync(_db, recipients.Where(u => u != me.UserId).ToList(),
            $"{me.Name} ({studentName})", body.Length > 0 ? Preview(body) : "Sent an attachment", "school_message", $"/school/messages?c={id}");

        return Ok(dto);
    }

    /// <summary>POST /api/school/conversations/{id}/read { lastMessageId } — the user has seen the thread up to this message.</summary>
    [HttpPost("conversations/{id:int}/read")]
    public async Task<IActionResult> Read(int id, [FromBody] ReadRequest req)
    {
        var (me, conv, classId) = await LoadAsync(id);
        if (me == null) return Forbid();

        var maxId = await _db.ChatMessages.Where(m => m.ConversationId == id).MaxAsync(m => (int?)m.Id) ?? 0;
        var upTo = Math.Min(req.LastMessageId, maxId);
        if (upTo <= 0) return NoContent();
        if (await MarkReadAsync(id, me.UserId, upTo))
        {
            // Tell the other side so their messages show "Seen"
            var parents = await SchoolParticipants.ParentUserIdsAsync(_db, conv!.StudentId);
            var staff   = await SchoolParticipants.StaffUserIdsAsync(_db, conv.Kind, classId);
            var others  = me.IsParent ? staff : parents;
            await _live.SendAsync(others.Append(me.UserId), "read",
                new { conversationId = id, userId = me.UserId, lastReadMessageId = upTo, byParent = me.IsParent });
        }
        return NoContent();
    }

    /// <summary>GET /api/school/attachments/{messageId} — the photo or PDF of a message (thread members only).</summary>
    [HttpGet("attachments/{messageId:int}")]
    public async Task<IActionResult> Attachment(int messageId)
    {
        var convId = await _db.ChatMessages.Where(m => m.Id == messageId).Select(m => (int?)m.ConversationId).FirstOrDefaultAsync()
                     ?? throw new KeyNotFoundException("Attachment not found.");
        var (me, _, _) = await LoadAsync(convId);
        if (me == null) return Forbid();
        var att = await _db.ChatAttachments.AsNoTracking().FirstOrDefaultAsync(a => a.MessageId == messageId)
                  ?? throw new KeyNotFoundException("Attachment not found.");
        return ChatFiles.Inline(Response, this, att.FileName, att.ContentType, att.Data);
    }

    // ── helpers ──

    /// <summary>The thread if the user may access it; otherwise me = null (403). Unknown id → 404.</summary>
    private async Task<(SchoolViewer? me, Conversation? conv, int? classId)> LoadAsync(int id, bool tracking = false)
    {
        var q = tracking ? _db.Conversations : _db.Conversations.AsNoTracking();
        var conv = await q.FirstOrDefaultAsync(c => c.Id == id) ?? throw new KeyNotFoundException("Conversation not found.");
        var classId = await _db.Students.Where(s => s.Id == conv.StudentId).Select(s => s.ClassId).FirstOrDefaultAsync();
        var me = await SchoolViewer.LoadAsync(_db, User);
        if (me == null || !me.CanAccessConversation(conv.Kind, conv.StudentId, classId)) return (null, conv, classId);
        return (me, conv, classId);
    }

    /// <summary>Threads this user may open (same rule as <see cref="SchoolViewer.CanAccessConversation"/>).</summary>
    private IQueryable<Conversation> Accessible(SchoolViewer me)
    {
        var q = _db.Conversations.AsNoTracking();
        if (me.IsAdmin) return q;
        if (me.IsParent) return q.Where(c => me.ChildIds.Contains(c.StudentId));
        return q.Where(c => c.Kind == Conversation.Teacher && c.Student.ClassId != null
                            && me.TeacherClassIds.Contains(c.Student.ClassId.Value));
    }

    private async Task EnsureParentThreadsAsync(SchoolViewer me)
    {
        var existing = await _db.Conversations.Where(c => me.ChildIds.Contains(c.StudentId))
            .Select(c => new { c.StudentId, c.Kind }).ToListAsync();
        var missing = me.ChildIds
            .SelectMany(s => Conversation.Kinds.Select(k => (s, k)))
            .Where(x => !existing.Any(e => e.StudentId == x.s && e.Kind == x.k))
            .ToList();
        if (missing.Count == 0) return;
        foreach (var (s, k) in missing)
            _db.Conversations.Add(new Conversation { StudentId = s, Kind = k, CreatedAt = DateTime.UtcNow });
        try { await _db.SaveChangesAsync(); }
        catch (DbUpdateException) { _db.ChangeTracker.Clear(); /* the other parent created them at the same moment */ }
    }

    private async Task<Conversation> GetOrCreateAsync(int studentId, string kind)
    {
        var conv = await _db.Conversations.FirstOrDefaultAsync(c => c.StudentId == studentId && c.Kind == kind);
        if (conv != null) return conv;
        conv = new Conversation { StudentId = studentId, Kind = kind, CreatedAt = DateTime.UtcNow };
        _db.Conversations.Add(conv);
        try { await _db.SaveChangesAsync(); }
        catch (DbUpdateException)
        {
            _db.ChangeTracker.Clear();
            conv = await _db.Conversations.FirstAsync(c => c.StudentId == studentId && c.Kind == kind);
        }
        return conv;
    }

    private async Task<object> HeaderAsync(Conversation conv, int? classId)
    {
        var s = await _db.Students.AsNoTracking().Where(x => x.Id == conv.StudentId)
            .Select(x => new
            {
                x.FullName,
                className   = x.Class != null ? x.Class.Name : null,
                teacherName = x.Class != null && x.Class.ClassTeacher != null ? x.Class.ClassTeacher.Name : null,
                parents     = x.Parents.Where(p => p.Parent.IsActive)
                    .Select(p => new { p.Parent.FullName, p.Parent.Relationship, hasLogin = p.Parent.UserId != null }).ToList()
            }).FirstAsync();
        return new
        {
            conv.Id, conv.Kind, conv.StudentId,
            studentName = s.FullName, s.className, s.teacherName, s.parents,
            title = conv.Kind == Conversation.Office ? "School office"
                  : s.teacherName != null ? $"Class teacher · {s.teacherName}" : "Class teacher"
        };
    }

    /// <summary>The highest message id read by anyone on the other side (parents vs school).</summary>
    private async Task<int> SeenUpToAsync(Conversation conv, int? classId, SchoolViewer me)
    {
        var others = me.IsParent
            ? await SchoolParticipants.StaffUserIdsAsync(_db, conv.Kind, classId)
            : await SchoolParticipants.ParentUserIdsAsync(_db, conv.StudentId);
        if (others.Count == 0) return 0;
        return await _db.ConversationReads
            .Where(r => r.ConversationId == conv.Id && others.Contains(r.UserId))
            .MaxAsync(r => (int?)r.LastReadMessageId) ?? 0;
    }

    /// <summary>Moves the user's read marker forward (never back). True when it moved.</summary>
    private async Task<bool> MarkReadAsync(int conversationId, int userId, int messageId)
    {
        var read = await _db.ConversationReads.FirstOrDefaultAsync(r => r.ConversationId == conversationId && r.UserId == userId);
        if (read != null && read.LastReadMessageId >= messageId) return false;
        if (read == null)
            _db.ConversationReads.Add(new ConversationRead { ConversationId = conversationId, UserId = userId, LastReadMessageId = messageId, ReadAt = DateTime.UtcNow });
        else
        {
            read.LastReadMessageId = messageId;
            read.ReadAt = DateTime.UtcNow;
        }
        try { await _db.SaveChangesAsync(); return true; }
        catch (DbUpdateException) { _db.ChangeTracker.Clear(); return false; }
    }

    /// <summary>An admin writing in a class-teacher thread signs as "Office" unless they are that class's teacher.</summary>
    private static string SenderRoleIn(SchoolViewer me, string kind) =>
        me.IsParent ? "Parent"
        : kind == Conversation.Teacher && me.IsTeacher && !me.IsAdmin ? Conversation.Teacher
        : me.IsAdmin ? Conversation.Office : Conversation.Teacher;

    private Task<List<int>> AdminIdsAsync() =>
        _db.Users.Where(u => u.Role == "Admin" && u.IsActive).Select(u => u.Id).ToListAsync();

    private static string Preview(string s) => s.Length <= 120 ? s : s[..119] + "…";
}

public class MessageDto
{
    public int Id { get; set; }
    public int ConversationId { get; set; }
    public int SenderUserId { get; set; }
    public string SenderName { get; set; } = "";
    public string SenderRole { get; set; } = "";
    public string Body { get; set; } = "";
    public DateTime SentAt { get; set; }
    public AttachmentDto? Attachment { get; set; }

    public class AttachmentDto
    {
        public string Name { get; set; } = "";
        public string ContentType { get; set; } = "";
        public int Size { get; set; }
    }

    public static readonly System.Linq.Expressions.Expression<Func<ChatMessage, MessageDto>> Projection = m => new MessageDto
    {
        Id = m.Id, ConversationId = m.ConversationId, SenderUserId = m.SenderUserId, SenderName = m.SenderName,
        SenderRole = m.SenderRole, Body = m.Body, SentAt = m.SentAt,
        Attachment = m.Attachment == null ? null : new AttachmentDto
        {
            Name = m.Attachment.FileName, ContentType = m.Attachment.ContentType, Size = m.Attachment.SizeBytes
        }
    };

    public static MessageDto From(ChatMessage m) => new()
    {
        Id = m.Id, ConversationId = m.ConversationId, SenderUserId = m.SenderUserId, SenderName = m.SenderName,
        SenderRole = m.SenderRole, Body = m.Body, SentAt = m.SentAt,
        Attachment = m.Attachment == null ? null : new AttachmentDto
        {
            Name = m.Attachment.FileName, ContentType = m.Attachment.ContentType, Size = m.Attachment.SizeBytes
        }
    };
}

public class OpenConversationRequest
{
    public int StudentId { get; set; }
    public string Kind { get; set; } = Conversation.Teacher;
}

public class SendMessageForm
{
    public string? Body { get; set; }
    public IFormFile? File { get; set; }
}

public class ReadRequest
{
    public int LastMessageId { get; set; }
}
