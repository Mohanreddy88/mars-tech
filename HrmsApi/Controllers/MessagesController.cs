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
/// Parent ↔ school messages. Conversations are about one child and go either to the class
/// teacher ("Teacher") or the office ("Office", the admins); each has a subject, and parents or
/// staff start a new one per topic. Both parents of a child share the child's conversations.
/// Staff close a conversation when it's done; a new message reopens it.
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
    /// GET /api/school/conversations — the conversations this user sees (those with at least
    /// one message), latest activity first, open and closed.
    /// </summary>
    [HttpGet("conversations")]
    public async Task<IActionResult> List()
    {
        var me = await SchoolViewer.LoadAsync(_db, User);
        if (me == null || (!me.IsStaff && !me.IsParent)) return Forbid();

        var rows = await Accessible(me)
            .Where(c => c.LastMessageAt != null)
            .Select(c => new
            {
                c.Id, c.Kind, c.StudentId, c.LastMessageAt, c.Subject, c.Status, c.CreatedByUserId,
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
                r.Subject, r.Status, startedByMe = r.CreatedByUserId == me.UserId,
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
    /// POST /api/school/conversations/open { studentId, kind } — the child's latest open
    /// conversation of that kind, or a new "General" one. Used by the "message" buttons next to
    /// a child; a conversation with its own subject is started with POST /conversations.
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

        var conv = await _db.Conversations
            .Where(c => c.StudentId == student.Id && c.Kind == req.Kind && c.Status == Conversation.Open)
            .OrderByDescending(c => c.LastMessageAt ?? c.CreatedAt)
            .FirstOrDefaultAsync();
        if (conv == null)
        {
            conv = new Conversation { StudentId = student.Id, Kind = req.Kind, CreatedByUserId = me.UserId, CreatedAt = DateTime.UtcNow };
            _db.Conversations.Add(conv);
            await _db.SaveChangesAsync();
        }
        return Ok(new { conv.Id });
    }

    /// <summary>
    /// POST /api/school/conversations (multipart: studentId, kind, subject, body, file?) — starts
    /// a new conversation about a child with its first message. Parents: their own children.
    /// Staff: children they may message (class teacher: "Teacher" ones of their classes).
    /// </summary>
    [HttpPost("conversations")]
    [RequestSizeLimit(ChatMessage.MaxAttachmentBytes + 256 * 1024)]
    public async Task<IActionResult> Start([FromForm] StartConversationForm form)
    {
        var me = await SchoolViewer.LoadAsync(_db, User);
        if (me == null || (!me.IsStaff && !me.IsParent)) return Forbid();
        if (!Conversation.Kinds.Contains(form.Kind)) return BadRequest(new { message = "Choose class teacher or office." });

        var subject = (form.Subject ?? "").Trim();
        if (subject.Length == 0) return BadRequest(new { message = "Enter a subject." });
        if (subject.Length > Conversation.MaxSubjectLength)
            return BadRequest(new { message = $"The subject is too long ({Conversation.MaxSubjectLength} characters at most)." });

        var student = await _db.Students.AsNoTracking().Where(s => s.Id == form.StudentId)
            .Select(s => new { s.Id, s.ClassId, s.IsActive }).FirstOrDefaultAsync()
            ?? throw new KeyNotFoundException("Child not found.");
        if (!me.CanAccessConversation(form.Kind, student.Id, student.ClassId)) return Forbid();

        var body = (form.Body ?? "").Trim();
        var (attachment, error) = await ReadMessageAsync(body, form.File);
        if (error != null) return BadRequest(new { message = error });

        var conv = new Conversation
        {
            StudentId = student.Id, Kind = form.Kind, Subject = subject,
            CreatedByUserId = me.UserId, CreatedAt = DateTime.UtcNow
        };
        _db.Conversations.Add(conv);
        await _db.SaveChangesAsync();

        var dto = await PostAsync(me, conv, student.ClassId, body, attachment, isNew: true);
        return Ok(new { conv.Id, message = dto });
    }

    /// <summary>POST /api/school/conversations/{id}/close — staff mark the conversation as done.</summary>
    [HttpPost("conversations/{id:int}/close")]
    public Task<IActionResult> Close(int id) => SetStatusAsync(id, Conversation.Closed);

    /// <summary>POST /api/school/conversations/{id}/reopen — anyone in the conversation (a new message also reopens it).</summary>
    [HttpPost("conversations/{id:int}/reopen")]
    public Task<IActionResult> Reopen(int id) => SetStatusAsync(id, Conversation.Open);

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
        var (attachment, error) = await ReadMessageAsync(body, form.File);
        if (error != null) return BadRequest(new { message = error });

        var dto = await PostAsync(me, conv!, classId, body, attachment, isNew: false);
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

    /// <summary>Checks the text and reads the optional photo/PDF. Error = the reason to show.</summary>
    private static async Task<(ChatAttachment? attachment, string? error)> ReadMessageAsync(string body, IFormFile? file)
    {
        if (body.Length > ChatMessage.MaxBodyLength) return (null, "The message is too long (4000 characters at most).");
        var hasFile = file != null && file.Length > 0;
        if (body.Length == 0 && !hasFile) return (null, "Write a message or attach a file.");
        if (!hasFile) return (null, null);

        var (read, error) = await ChatFiles.ReadAsync(file!);
        if (error != null) return (null, error);
        var f = read!.Value;
        return (new ChatAttachment { FileName = f.name, ContentType = f.type!, SizeBytes = f.size ?? 0, Data = f.data }, null);
    }

    /// <summary>
    /// Saves a message (reopening a closed conversation), then tells everyone in it: live to
    /// open screens, and a phone push to the other side. <paramref name="conv"/> must be tracked.
    /// </summary>
    private async Task<MessageDto> PostAsync(
        SchoolViewer me, Conversation conv, int? classId, string body, ChatAttachment? attachment, bool isNew)
    {
        var msg = new ChatMessage
        {
            ConversationId = conv.Id, SenderUserId = me.UserId, SenderName = me.Name,
            SenderRole = SenderRoleIn(me, conv.Kind), Body = body, SentAt = DateTime.UtcNow,
            Attachment = attachment
        };
        var reopened = conv.Status == Conversation.Closed;
        if (reopened)
        {
            conv.Status = Conversation.Open;
            conv.ClosedAt = null;
            conv.ClosedByName = null;
        }
        _db.ChatMessages.Add(msg);
        conv.LastMessageAt = msg.SentAt;
        await _db.SaveChangesAsync();

        // The sender has read everything up to their own message
        await MarkReadAsync(conv.Id, me.UserId, msg.Id);

        var dto = MessageDto.From(msg);
        var parents = await SchoolParticipants.ParentUserIdsAsync(_db, conv.StudentId);
        var staff   = await SchoolParticipants.StaffUserIdsAsync(_db, conv.Kind, classId);
        var everyone = parents.Concat(staff).ToList();
        if (reopened)
            await _live.SendAsync(everyone, "conversation", new { conversationId = conv.Id, status = conv.Status, closedByName = (string?)null });
        await _live.SendAsync(everyone, "message", new { conversationId = conv.Id, message = dto });

        // Phone push to the other side (the web app shows the unread badge instead)
        var studentName = await _db.Students.Where(s => s.Id == conv.StudentId).Select(s => s.FullName).FirstAsync();
        var admins = await AdminIdsAsync();
        var recipients = me.IsParent
            ? (conv.Kind == Conversation.Office ? admins : staff.Except(admins).ToList())
            : parents;
        var title = isNew ? $"{me.Name} ({studentName}): {conv.Subject}" : $"{me.Name} ({studentName})";
        await _push.SendToUsersAsync(_db, recipients.Where(u => u != me.UserId).ToList(),
            title, body.Length > 0 ? Preview(body) : "Sent an attachment", "school_message", $"/school/messages?c={conv.Id}");

        return dto;
    }

    /// <summary>Close (staff only) or reopen (anyone in it) a conversation, and tell everyone in it.</summary>
    private async Task<IActionResult> SetStatusAsync(int id, string status)
    {
        var (me, conv, classId) = await LoadAsync(id, tracking: true);
        if (me == null) return Forbid();
        if (status == Conversation.Closed && !me.IsStaff)
            return BadRequest(new { message = "Only the school can close a conversation." });
        if (conv!.Status == status) return Ok(new { conv.Status, conv.ClosedByName });

        conv.Status = status;
        conv.ClosedAt = status == Conversation.Closed ? DateTime.UtcNow : null;
        conv.ClosedByName = status == Conversation.Closed ? me.Name : null;
        await _db.SaveChangesAsync();

        var parents = await SchoolParticipants.ParentUserIdsAsync(_db, conv.StudentId);
        var staff   = await SchoolParticipants.StaffUserIdsAsync(_db, conv.Kind, classId);
        await _live.SendAsync(parents.Concat(staff), "conversation",
            new { conversationId = id, status = conv.Status, closedByName = conv.ClosedByName });
        return Ok(new { conv.Status, conv.ClosedByName });
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
            conv.Id, conv.Kind, conv.StudentId, conv.Subject, conv.Status, conv.ClosedAt, conv.ClosedByName,
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

public class StartConversationForm
{
    public int StudentId { get; set; }
    public string Kind { get; set; } = Conversation.Teacher;
    public string? Subject { get; set; }
    public string? Body { get; set; }
    public IFormFile? File { get; set; }
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
