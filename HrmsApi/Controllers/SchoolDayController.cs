using System.ComponentModel.DataAnnotations;
using System.Globalization;
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
/// School phase 3 — the child's day.
///   Staff (admins, class teachers for their classes): attendance list, check-in / check-out /
///   absent, parents' notes (mark seen), daily reports with photos, publish to parents.
///   Parents (their own children): the day view (attendance, published report, notes) and
///   absence / pickup notes.
/// Access is decided by <see cref="SchoolViewer"/> from the database on every request.
/// </summary>
[ApiController]
[Route("api/school")]
[Authorize]
[RequiresSchoolFeatures]
public class SchoolDayController : ControllerBase
{
    private readonly HrmsDbContext _db;
    private readonly IChatNotifier _live;
    private readonly IPushService _push;
    private readonly IAuditService _audit;

    public SchoolDayController(HrmsDbContext db, IChatNotifier live, IPushService push, IAuditService audit)
    {
        _db = db; _live = live; _push = push; _audit = audit;
    }

    // ════════════════════════════ Attendance (staff) ════════════════════════════

    /// <summary>
    /// GET /api/school/attendance?classId=&amp;date= — the class list for a day: each child's
    /// attendance, parents' notes, daily report state. Admins without a class: every child.
    /// </summary>
    [HttpGet("attendance")]
    public async Task<IActionResult> GetAttendance([FromQuery] int? classId, [FromQuery] DateTime? date)
    {
        var me = await SchoolViewer.LoadAsync(_db, User);
        if (me == null || !me.IsStaff) return Forbid();
        var day = (date ?? SchoolClock.Today).Date;
        if (classId != null && !me.IsAdmin && !me.TeacherClassIds.Contains(classId.Value)) return Forbid();

        var students = _db.Students.AsNoTracking().Where(s => s.IsActive);
        if (classId != null) students = students.Where(s => s.ClassId == classId);
        else if (!me.IsAdmin) students = students.Where(s => s.ClassId != null && me.TeacherClassIds.Contains(s.ClassId.Value));

        var kids = await students
            .OrderBy(s => s.Class != null ? s.Class.SortOrder : int.MaxValue).ThenBy(s => s.Class!.Name).ThenBy(s => s.FullName)
            .Select(s => new
            {
                s.Id, s.FullName, s.ClassId, s.SessionType, s.MedicalNotes,
                className = s.Class != null ? s.Class.Name : null,
                parents = s.Parents.Where(p => p.Parent.IsActive)
                    .Select(p => new { p.Parent.FullName, p.Parent.Relationship, p.Parent.Phone }).ToList()
            }).ToListAsync();
        var ids = kids.Select(k => k.Id).ToList();

        var attendance = await _db.StudentAttendance.AsNoTracking()
            .Where(a => a.Date == day && ids.Contains(a.StudentId)).ToListAsync();
        var notes = await NotesFor(ids, day, day).ToListAsync();
        var reports = await _db.DailyReports.AsNoTracking()
            .Where(r => r.Date == day && ids.Contains(r.StudentId))
            .Select(r => new { r.StudentId, r.PublishedAt, photos = r.Photos.Count, r.Mood }).ToListAsync();

        var rows = kids.Select(k =>
        {
            var a = attendance.FirstOrDefault(x => x.StudentId == k.Id);
            var r = reports.FirstOrDefault(x => x.StudentId == k.Id);
            return new
            {
                studentId = k.Id, k.FullName, k.ClassId, k.className, k.SessionType, k.MedicalNotes, k.parents,
                attendance = a == null ? null : AttendanceDto(a),
                notes = notes.Where(n => n.StudentId == k.Id).Select(NoteDto).ToList(),
                report = r == null ? null : new { published = r.PublishedAt != null, r.photos, r.Mood }
            };
        }).ToList();

        return Ok(new
        {
            date = day.ToString("yyyy-MM-dd"),
            today = SchoolClock.Today.ToString("yyyy-MM-dd"),
            rows,
            summary = new
            {
                total      = rows.Count,
                present    = attendance.Count(a => a.Status == StudentAttendance.Present),
                checkedOut = attendance.Count(a => a.CheckOutAt != null),
                absent     = attendance.Count(a => a.Status == StudentAttendance.Absent),
                notMarked  = rows.Count - attendance.Count,
                reportsPublished = reports.Count(r => r.PublishedAt != null)
            }
        });
    }

    /// <summary>POST /api/school/attendance/{studentId}/check-in — arrived (time defaults to now).</summary>
    [HttpPost("attendance/{studentId:int}/check-in")]
    public async Task<IActionResult> CheckIn(int studentId, [FromBody] CheckInRequest req)
    {
        var (me, child, error) = await StaffChildAsync(studentId);
        if (error != null) return error;
        var (day, at, problem) = DayAndTime(req.Date, req.Time);
        if (problem != null) return BadRequest(new { message = problem });

        var a = await RecordAsync(studentId, day);
        a.Status        = StudentAttendance.Present;
        a.AbsenceReason = null;
        a.CheckInAt     = at;
        a.CheckInBy     = me!.Name;
        if (a.CheckOutAt != null && a.CheckOutAt < at) { a.CheckOutAt = null; a.CheckOutBy = null; a.PickedUpBy = null; }
        a.UpdatedAt = DateTime.UtcNow;
        await _db.SaveChangesAsync();

        if (day == SchoolClock.Today)
            await TellParentsAsync(child!.Id, $"{child.FullName} arrived at school",
                $"Checked in at {SchoolClock.LocalTime(at)} by {me.Name}.", "school_attendance", day);
        return Ok(AttendanceDto(a));
    }

    /// <summary>POST /api/school/attendance/{studentId}/check-out — went home, and who collected them.</summary>
    [HttpPost("attendance/{studentId:int}/check-out")]
    public async Task<IActionResult> CheckOut(int studentId, [FromBody] CheckOutRequest req)
    {
        var (me, child, error) = await StaffChildAsync(studentId);
        if (error != null) return error;
        var (day, at, problem) = DayAndTime(req.Date, req.Time);
        if (problem != null) return BadRequest(new { message = problem });
        var by = req.PickedUpBy?.Trim();
        if (string.IsNullOrEmpty(by)) return BadRequest(new { message = "Who picked the child up?", field = "pickedUpBy" });

        var a = await _db.StudentAttendance.FirstOrDefaultAsync(x => x.StudentId == studentId && x.Date == day);
        if (a == null || a.Status != StudentAttendance.Present || a.CheckInAt == null)
            return BadRequest(new { message = $"{child!.FullName} hasn't been checked in on this day." });
        if (at < a.CheckInAt) return BadRequest(new { message = "The pickup time is before the arrival time." });

        a.CheckOutAt = at;
        a.CheckOutBy = me!.Name;
        a.PickedUpBy = by.Length > 150 ? by[..150] : by;
        a.UpdatedAt  = DateTime.UtcNow;
        await _db.SaveChangesAsync();

        if (day == SchoolClock.Today)
            await TellParentsAsync(child!.Id, $"{child.FullName} has gone home",
                $"Picked up by {a.PickedUpBy} at {SchoolClock.LocalTime(at)}.", "school_attendance", day);
        return Ok(AttendanceDto(a));
    }

    /// <summary>POST /api/school/attendance/{studentId}/absent — not at school today.</summary>
    [HttpPost("attendance/{studentId:int}/absent")]
    public async Task<IActionResult> MarkAbsent(int studentId, [FromBody] AbsentRequest req)
    {
        var (me, child, error) = await StaffChildAsync(studentId);
        if (error != null) return error;
        var (day, _, problem) = DayAndTime(req.Date, null);
        if (problem != null) return BadRequest(new { message = problem });

        var a = await RecordAsync(studentId, day);
        a.Status        = StudentAttendance.Absent;
        a.AbsenceReason = string.IsNullOrWhiteSpace(req.Reason) ? null : req.Reason.Trim();
        a.CheckInAt = null; a.CheckInBy = null; a.CheckOutAt = null; a.CheckOutBy = null; a.PickedUpBy = null;
        a.UpdatedAt = DateTime.UtcNow;
        await _db.SaveChangesAsync();
        return Ok(AttendanceDto(a));
    }

    /// <summary>DELETE /api/school/attendance/{studentId}?date= — undo a mistake (back to "not marked").</summary>
    [HttpDelete("attendance/{studentId:int}")]
    public async Task<IActionResult> ClearAttendance(int studentId, [FromQuery] DateTime? date)
    {
        var (_, _, error) = await StaffChildAsync(studentId);
        if (error != null) return error;
        var day = (date ?? SchoolClock.Today).Date;
        var a = await _db.StudentAttendance.FirstOrDefaultAsync(x => x.StudentId == studentId && x.Date == day);
        if (a != null) { _db.StudentAttendance.Remove(a); await _db.SaveChangesAsync(); }
        return NoContent();
    }

    // ════════════════════════════ Parents' notes ════════════════════════════

    /// <summary>
    /// GET /api/school/notes?studentId=&amp;from=&amp;to= — absence and pickup notes. Parents: their
    /// children's. Staff: the children they see. Defaults to the last 30 days and everything ahead.
    /// </summary>
    [HttpGet("notes")]
    public async Task<IActionResult> GetNotes([FromQuery] int? studentId, [FromQuery] DateTime? from, [FromQuery] DateTime? to)
    {
        var me = await SchoolViewer.LoadAsync(_db, User);
        if (me == null || (!me.IsStaff && !me.IsParent)) return Forbid();
        var ids = await VisibleStudentIds(me).ToListAsync();
        if (studentId != null) ids = ids.Where(i => i == studentId).ToList();
        var f = (from ?? SchoolClock.Today.AddDays(-30)).Date;
        var t = (to ?? SchoolClock.Today.AddYears(1)).Date;
        var list = await NotesFor(ids, f, t).OrderByDescending(n => n.FromDate).ThenByDescending(n => n.CreatedAt).Take(300).ToListAsync();
        return Ok(list.Select(NoteDto));
    }

    /// <summary>POST /api/school/notes — a parent reports an absence or a different pickup.</summary>
    [HttpPost("notes")]
    public async Task<IActionResult> CreateNote([FromBody] ParentNoteRequest req)
    {
        var me = await SchoolViewer.LoadAsync(_db, User);
        if (me == null || !me.IsParent || !me.ChildIds.Contains(req.StudentId)) return Forbid();
        var child = await _db.Students.AsNoTracking().Where(s => s.Id == req.StudentId)
            .Select(s => new { s.Id, s.FullName, s.ClassId }).FirstAsync();

        if (!ParentNote.Kinds.Contains(req.Kind)) return BadRequest(new { message = "Choose absence or pickup." });
        var from = req.FromDate.Date;
        var to = (req.Kind == ParentNote.Absence ? req.ToDate ?? req.FromDate : req.FromDate).Date;
        if (from < SchoolClock.Today) return BadRequest(new { message = "The date can't be in the past.", field = "fromDate" });
        if (to < from) return BadRequest(new { message = "The last day must be on or after the first day.", field = "toDate" });
        if ((to - from).TotalDays > 60) return BadRequest(new { message = "An absence can be at most 60 days. Send another note for longer.", field = "toDate" });

        var note = new ParentNote
        {
            StudentId = child.Id, Kind = req.Kind, FromDate = from, ToDate = to,
            Message = Clean(req.Message, 1000), CreatedByUserId = me.UserId, CreatedByName = me.Name
        };
        if (req.Kind == ParentNote.Pickup)
        {
            note.PickupName = Clean(req.PickupName, 150);
            if (note.PickupName == null) return BadRequest(new { message = "Who will pick the child up?", field = "pickupName" });
            var (phone, phoneError) = PhoneNumbers.Normalize(req.PickupPhone);
            if (phoneError != null) return BadRequest(new { message = phoneError, field = "pickupPhone" });
            note.PickupPhone = phone;
            var time = req.PickupTime?.Trim();
            if (!string.IsNullOrEmpty(time) && !TimeOnly.TryParseExact(time, "HH:mm", CultureInfo.InvariantCulture, DateTimeStyles.None, out _))
                return BadRequest(new { message = "Enter the time like 15:30.", field = "pickupTime" });
            note.PickupTime = string.IsNullOrEmpty(time) ? null : time;

            // Someone else can only collect a child who is at school that day
            if (await _db.ParentNotes.AnyAsync(n => n.StudentId == child.Id && n.Kind == ParentNote.Absence
                                                    && n.CancelledAt == null && n.FromDate <= from && n.ToDate >= from))
                return BadRequest(new { message = $"{child.FullName} is reported absent on {from:ddd d MMM}. Cancel the absence first to arrange a pickup.", field = "fromDate" });
            if (await _db.StudentAttendance.AnyAsync(a => a.StudentId == child.Id && a.Date == from && a.Status == StudentAttendance.Absent))
                return BadRequest(new { message = $"{child.FullName} is marked absent on {from:ddd d MMM}, so no pickup is needed.", field = "fromDate" });
        }
        else
        {
            // An absence replaces any different-pickup notes for the same days
            var pickups = await _db.ParentNotes.Where(n => n.StudentId == child.Id && n.Kind == ParentNote.Pickup
                                                           && n.CancelledAt == null && n.FromDate >= from && n.FromDate <= to).ToListAsync();
            foreach (var p in pickups) p.CancelledAt = DateTime.UtcNow;
        }

        _db.ParentNotes.Add(note);
        await _db.SaveChangesAsync();

        var staff = await SchoolParticipants.StaffUserIdsAsync(_db, Conversation.Teacher, child.ClassId);
        var when = from == to ? from.ToString("ddd d MMM") : $"{from:d MMM} – {to:d MMM}";
        var (title, text) = req.Kind == ParentNote.Absence
            ? ($"{child.FullName} will be absent", $"{when}. From {me.Name}" + (note.Message != null ? $": {note.Message}" : "."))
            : ($"Different pickup for {child.FullName}", $"{when}: {note.PickupName}" + (note.PickupTime != null ? $" at {note.PickupTime}" : "") + $". From {me.Name}.");
        await SchoolAlerts.SendAsync(_db, _push, _live, staff, title, text, "school_note",
            $"/school/attendance?date={from:yyyy-MM-dd}", "note", new { note.Id, studentId = child.Id });

        return Ok(NoteDto(note));
    }

    /// <summary>POST /api/school/notes/{id}/cancel — the parent withdraws a note that hasn't passed.</summary>
    [HttpPost("notes/{id:int}/cancel")]
    public async Task<IActionResult> CancelNote(int id)
    {
        var me = await SchoolViewer.LoadAsync(_db, User);
        var note = await _db.ParentNotes.FindAsync(id) ?? throw new KeyNotFoundException("Note not found.");
        if (me == null || !me.IsParent || !me.ChildIds.Contains(note.StudentId)) return Forbid();
        if (note.ToDate < SchoolClock.Today) return BadRequest(new { message = "This note is in the past." });
        note.CancelledAt ??= DateTime.UtcNow;
        await _db.SaveChangesAsync();
        return Ok(NoteDto(note));
    }

    /// <summary>POST /api/school/notes/{id}/seen — the teacher or office has read it (the parent sees "Seen by …").</summary>
    [HttpPost("notes/{id:int}/seen")]
    public async Task<IActionResult> MarkNoteSeen(int id)
    {
        var me = await SchoolViewer.LoadAsync(_db, User);
        var note = await _db.ParentNotes.Include(n => n.Student).FirstOrDefaultAsync(n => n.Id == id)
                   ?? throw new KeyNotFoundException("Note not found.");
        if (me == null || !me.IsStaff || !me.CanSeeStudent(note.StudentId, note.Student.ClassId)) return Forbid();
        if (note.SeenAt == null)
        {
            note.SeenAt = DateTime.UtcNow;
            note.SeenByName = me.Name;
            await _db.SaveChangesAsync();
            var parents = await SchoolParticipants.ParentUserIdsAsync(_db, note.StudentId);
            await _live.SendAsync(parents, "note", new { note.Id, note.StudentId });
        }
        return Ok(NoteDto(note));
    }

    // ════════════════════════════ Daily report ════════════════════════════

    /// <summary>
    /// GET /api/school/children/{studentId}/day?date= — one child's day: attendance, daily report
    /// (parents: once published), notes. For the parent portal and the teacher's report editor.
    /// </summary>
    [HttpGet("children/{studentId:int}/day")]
    public async Task<IActionResult> GetDay(int studentId, [FromQuery] DateTime? date)
    {
        var me = await SchoolViewer.LoadAsync(_db, User);
        var child = await _db.Students.AsNoTracking().Where(s => s.Id == studentId)
            .Select(s => new { s.Id, s.FullName, s.ClassId, className = s.Class != null ? s.Class.Name : null,
                               teacher = s.Class != null && s.Class.ClassTeacher != null ? s.Class.ClassTeacher.Name : null })
            .FirstOrDefaultAsync() ?? throw new KeyNotFoundException("Child not found.");
        if (me == null || !me.CanSeeStudent(child.Id, child.ClassId)) return Forbid();
        var day = (date ?? SchoolClock.Today).Date;

        var a = await _db.StudentAttendance.AsNoTracking().FirstOrDefaultAsync(x => x.StudentId == studentId && x.Date == day);
        var r = await _db.DailyReports.AsNoTracking().Include(x => x.Photos)
            .FirstOrDefaultAsync(x => x.StudentId == studentId && x.Date == day);
        if (r != null && me.IsParent && r.PublishedAt == null) r = null;
        var notes = await NotesFor(new List<int> { studentId }, day, day).ToListAsync();

        return Ok(new
        {
            child, date = day.ToString("yyyy-MM-dd"), today = SchoolClock.Today.ToString("yyyy-MM-dd"),
            attendance = a == null ? null : AttendanceDto(a),
            report = r == null ? null : ReportDto(r),
            notes = notes.Select(NoteDto)
        });
    }

    /// <summary>GET /api/school/children/{studentId}/days?from=&amp;to= — a short history (at most 62 days) for the parent's calendar.</summary>
    [HttpGet("children/{studentId:int}/days")]
    public async Task<IActionResult> GetDays(int studentId, [FromQuery] DateTime? from, [FromQuery] DateTime? to)
    {
        var me = await SchoolViewer.LoadAsync(_db, User);
        var classId = await _db.Students.Where(s => s.Id == studentId).Select(s => s.ClassId).FirstOrDefaultAsync();
        if (me == null || !me.CanSeeStudent(studentId, classId)) return Forbid();
        var t = (to ?? SchoolClock.Today).Date;
        var f = (from ?? t.AddDays(-30)).Date;
        if ((t - f).TotalDays > 62) f = t.AddDays(-62);

        var att = await _db.StudentAttendance.AsNoTracking()
            .Where(a => a.StudentId == studentId && a.Date >= f && a.Date <= t)
            .Select(a => new { a.Date, a.Status }).ToListAsync();
        var reps = await _db.DailyReports.AsNoTracking()
            .Where(r => r.StudentId == studentId && r.Date >= f && r.Date <= t && (r.PublishedAt != null || !me.IsParent))
            .Select(r => new { r.Date, published = r.PublishedAt != null }).ToListAsync();
        var days = att.Select(a => a.Date).Union(reps.Select(r => r.Date)).OrderByDescending(d => d)
            .Select(d => new
            {
                date = d.ToString("yyyy-MM-dd"),
                status = att.FirstOrDefault(a => a.Date == d)?.Status,
                report = reps.Any(r => r.Date == d && r.published)
            });
        return Ok(days);
    }

    /// <summary>PUT /api/school/reports/{studentId}?date= — save the report (staff). A published report stays published.</summary>
    [HttpPut("reports/{studentId:int}")]
    public async Task<IActionResult> SaveReport(int studentId, [FromQuery] DateTime? date, [FromBody] DailyReportRequest req)
    {
        var (me, _, error) = await StaffChildAsync(studentId);
        if (error != null) return error;
        var (day, _, problem) = DayAndTime(date, null);
        if (problem != null) return BadRequest(new { message = problem });

        string? Pick(string? v, string[] allowed, string what)
        {
            if (string.IsNullOrWhiteSpace(v)) return null;
            if (!allowed.Contains(v)) throw new ArgumentException($"Choose a valid {what}.");
            return v;
        }
        string? Time(string? v, string what)
        {
            if (string.IsNullOrWhiteSpace(v)) return null;
            if (!TimeOnly.TryParseExact(v.Trim(), "HH:mm", CultureInfo.InvariantCulture, DateTimeStyles.None, out _))
                throw new ArgumentException($"Enter the {what} like 12:30.");
            return v.Trim();
        }

        // Check everything before touching the stored report
        string? breakfast, lunch, snack, mood, napFrom, napTo;
        try
        {
            breakfast = Pick(req.Breakfast, DailyReport.MealAmounts, "breakfast amount");
            lunch     = Pick(req.Lunch, DailyReport.MealAmounts, "lunch amount");
            snack     = Pick(req.Snack, DailyReport.MealAmounts, "snack amount");
            mood      = Pick(req.Mood, DailyReport.Moods, "mood");
            napFrom   = Time(req.NapFrom, "nap start");
            napTo     = Time(req.NapTo, "nap end");
        }
        catch (ArgumentException ex) { return BadRequest(new { message = ex.Message }); }
        if (napFrom != null && napTo != null && string.CompareOrdinal(napTo, napFrom) <= 0)
            return BadRequest(new { message = "The nap must end after it starts." });

        var r = await _db.DailyReports.FirstOrDefaultAsync(x => x.StudentId == studentId && x.Date == day);
        if (r == null) { r = new DailyReport { StudentId = studentId, Date = day }; _db.DailyReports.Add(r); }
        r.Breakfast = breakfast; r.Lunch = lunch; r.Snack = snack; r.Mood = mood; r.NapFrom = napFrom; r.NapTo = napTo;
        r.Toilet        = Clean(req.Toilet, 200);
        r.Activities    = Clean(req.Activities, 1000);
        r.TeacherNote   = Clean(req.TeacherNote, 1000);
        r.UpdatedByName = me!.Name;
        r.UpdatedAt     = DateTime.UtcNow;
        await _db.SaveChangesAsync();

        if (req.Publish && r.PublishedAt == null) await PublishAsync(new List<DailyReport> { r }, me);
        await _db.Entry(r).Collection(x => x.Photos).LoadAsync();
        return Ok(ReportDto(r));
    }

    /// <summary>POST /api/school/reports/{studentId}/photos?date= — add a photo (JPG/PNG, 5 MB, at most 6 per day).</summary>
    [HttpPost("reports/{studentId:int}/photos")]
    [RequestSizeLimit(DailyReport.MaxPhotoBytes + 1024 * 1024)]
    public async Task<IActionResult> AddPhoto(int studentId, [FromQuery] DateTime? date, IFormFile file)
    {
        var (me, _, error) = await StaffChildAsync(studentId);
        if (error != null) return error;
        var (day, _, problem) = DayAndTime(date, null);
        if (problem != null) return BadRequest(new { message = problem });
        if (file == null || file.Length == 0) return BadRequest(new { message = "Choose a photo." });

        var (upload, uploadError) = await ChatFiles.ReadAsync(file);
        if (uploadError != null) return BadRequest(new { message = uploadError });
        if (upload!.Value.type == "application/pdf") return BadRequest(new { message = "Only photos (JPG or PNG) can be added to the daily report." });

        var r = await _db.DailyReports.Include(x => x.Photos).FirstOrDefaultAsync(x => x.StudentId == studentId && x.Date == day);
        if (r == null)
        {
            r = new DailyReport { StudentId = studentId, Date = day, UpdatedByName = me!.Name };
            _db.DailyReports.Add(r);
        }
        if (r.Photos.Count >= DailyReport.MaxPhotos) return BadRequest(new { message = $"At most {DailyReport.MaxPhotos} photos per day." });
        var photo = new DailyReportPhoto
        {
            FileName = upload.Value.name, ContentType = upload.Value.type!, SizeBytes = upload.Value.size ?? 0, Data = upload.Value.data
        };
        r.Photos.Add(photo);
        r.UpdatedAt = DateTime.UtcNow;
        await _db.SaveChangesAsync();
        return Ok(new { photo.Id, count = r.Photos.Count });
    }

    /// <summary>DELETE /api/school/reports/photos/{photoId} — staff.</summary>
    [HttpDelete("reports/photos/{photoId:int}")]
    public async Task<IActionResult> DeletePhoto(int photoId)
    {
        var p = await _db.DailyReportPhotos.Include(x => x.Report).FirstOrDefaultAsync(x => x.Id == photoId)
                ?? throw new KeyNotFoundException("Photo not found.");
        var (_, _, error) = await StaffChildAsync(p.Report.StudentId);
        if (error != null) return error;
        _db.DailyReportPhotos.Remove(p);
        await _db.SaveChangesAsync();
        return NoContent();
    }

    /// <summary>GET /api/school/reports/photos/{photoId} — staff who see the child; parents once the report is published.</summary>
    [HttpGet("reports/photos/{photoId:int}")]
    public async Task<IActionResult> GetPhoto(int photoId)
    {
        var me = await SchoolViewer.LoadAsync(_db, User);
        var p = await _db.DailyReportPhotos.AsNoTracking()
            .Where(x => x.Id == photoId)
            .Select(x => new { x.FileName, x.ContentType, x.Data, x.Report.StudentId, x.Report.PublishedAt, x.Report.Student.ClassId })
            .FirstOrDefaultAsync() ?? throw new KeyNotFoundException("Photo not found.");
        if (me == null || !me.CanSeeStudent(p.StudentId, p.ClassId) || (me.IsParent && p.PublishedAt == null)) return Forbid();
        return ChatFiles.Inline(Response, this, p.FileName, p.ContentType, p.Data);
    }

    /// <summary>POST /api/school/reports/publish — send these children's reports for the day to their parents.</summary>
    [HttpPost("reports/publish")]
    public async Task<IActionResult> Publish([FromBody] PublishReportsRequest req)
    {
        var me = await SchoolViewer.LoadAsync(_db, User);
        if (me == null || !me.IsStaff) return Forbid();
        var day = (req.Date ?? SchoolClock.Today).Date;
        var ids = req.StudentIds?.Distinct().ToList() ?? new();
        var reports = await _db.DailyReports.Include(r => r.Student)
            .Where(r => r.Date == day && ids.Contains(r.StudentId) && r.PublishedAt == null).ToListAsync();
        reports = reports.Where(r => me.CanSeeStudent(r.StudentId, r.Student.ClassId)).ToList();
        await PublishAsync(reports, me);
        return Ok(new { published = reports.Count });
    }

    // ════════════════════════════ helpers ════════════════════════════

    private async Task PublishAsync(List<DailyReport> reports, SchoolViewer me)
    {
        if (reports.Count == 0) return;
        foreach (var r in reports) r.PublishedAt = DateTime.UtcNow;
        await _db.SaveChangesAsync();
        foreach (var r in reports)
        {
            var name = r.Student?.FullName ?? await _db.Students.Where(s => s.Id == r.StudentId).Select(s => s.FullName).FirstAsync();
            await TellParentsAsync(r.StudentId, $"{name}'s day at school",
                $"The daily report for {r.Date:ddd d MMM} is ready.", "school_daily_report", r.Date);
        }
        await _audit.LogAsync("Updated", "DailyReport", string.Join(",", reports.Select(r => r.Id)),
            $"Published {reports.Count} daily report(s) for {reports[0].Date:yyyy-MM-dd}", User.Identity?.Name ?? "unknown", me.UserId,
            null, null, HttpContext.Connection.RemoteIpAddress?.ToString());
    }

    private async Task TellParentsAsync(int studentId, string title, string message, string type, DateTime day)
    {
        var parents = await SchoolParticipants.ParentUserIdsAsync(_db, studentId);
        await SchoolAlerts.SendAsync(_db, _push, _live, parents, title, message, type,
            $"/parent/child/{studentId}?date={day:yyyy-MM-dd}", "day", new { studentId, date = day.ToString("yyyy-MM-dd") });
    }

    /// <summary>The signed-in staff member and the child, or the error to return.</summary>
    private async Task<(SchoolViewer? me, Student? child, IActionResult? error)> StaffChildAsync(int studentId)
    {
        var me = await SchoolViewer.LoadAsync(_db, User);
        var child = await _db.Students.AsNoTracking().FirstOrDefaultAsync(s => s.Id == studentId)
                    ?? throw new KeyNotFoundException("Child not found.");
        if (me == null || !me.IsStaff || !me.CanSeeStudent(child.Id, child.ClassId)) return (null, null, Forbid());
        if (!child.IsActive) return (null, null, BadRequest(new { message = $"{child.FullName} is inactive." }));
        return (me, child, null);
    }

    /// <summary>The school day (today or earlier, at most 60 days back) and the moment in UTC for an "HH:mm" time.</summary>
    private static (DateTime day, DateTime at, string? problem) DayAndTime(DateTime? date, string? time)
    {
        var today = SchoolClock.Today;
        var day = (date ?? today).Date;
        if (day > today) return (day, default, "You can't record a day in the future.");
        if (day < today.AddDays(-60)) return (day, default, "That day is too long ago to change.");

        DateTime at;
        if (string.IsNullOrWhiteSpace(time))
            at = day == today ? DateTime.UtcNow : DateTime.SpecifyKind(day.AddHours(12) - SchoolClock.Offset, DateTimeKind.Utc);
        else if (TimeOnly.TryParseExact(time.Trim(), "HH:mm", CultureInfo.InvariantCulture, DateTimeStyles.None, out var t))
            at = DateTime.SpecifyKind(day.Add(t.ToTimeSpan()) - SchoolClock.Offset, DateTimeKind.Utc);
        else return (day, default, "Enter the time like 08:05.");
        if (at > DateTime.UtcNow.AddMinutes(5)) return (day, default, "That time hasn't happened yet.");
        return (day, at, null);
    }

    private async Task<StudentAttendance> RecordAsync(int studentId, DateTime day)
    {
        var a = await _db.StudentAttendance.FirstOrDefaultAsync(x => x.StudentId == studentId && x.Date == day);
        if (a == null) { a = new StudentAttendance { StudentId = studentId, Date = day }; _db.StudentAttendance.Add(a); }
        return a;
    }

    private IQueryable<int> VisibleStudentIds(SchoolViewer me)
    {
        var q = _db.Students.AsNoTracking();
        if (me.IsAdmin) return q.Select(s => s.Id);
        if (me.IsParent) return q.Where(s => me.ChildIds.Contains(s.Id)).Select(s => s.Id);
        return q.Where(s => s.ClassId != null && me.TeacherClassIds.Contains(s.ClassId.Value)).Select(s => s.Id);
    }

    /// <summary>Notes (not withdrawn) that touch the period.</summary>
    private IQueryable<ParentNote> NotesFor(List<int> studentIds, DateTime from, DateTime to) =>
        _db.ParentNotes.AsNoTracking()
            .Where(n => studentIds.Contains(n.StudentId) && n.CancelledAt == null && n.FromDate <= to && n.ToDate >= from);

    private static object AttendanceDto(StudentAttendance a) => new
    {
        a.Status,
        checkIn    = a.CheckInAt == null ? null : SchoolClock.LocalTime(a.CheckInAt.Value),
        a.CheckInBy,
        checkOut   = a.CheckOutAt == null ? null : SchoolClock.LocalTime(a.CheckOutAt.Value),
        a.CheckOutBy, a.PickedUpBy, a.AbsenceReason
    };

    private static object NoteDto(ParentNote n) => new
    {
        n.Id, n.StudentId, n.Kind,
        fromDate = n.FromDate.ToString("yyyy-MM-dd"), toDate = n.ToDate.ToString("yyyy-MM-dd"),
        n.PickupName, n.PickupPhone, n.PickupTime, n.Message, n.CreatedByName, n.CreatedAt,
        n.SeenAt, n.SeenByName, cancelled = n.CancelledAt != null
    };

    private static object ReportDto(DailyReport r) => new
    {
        r.Id, date = r.Date.ToString("yyyy-MM-dd"), r.Breakfast, r.Lunch, r.Snack, r.NapFrom, r.NapTo, r.Toilet, r.Mood,
        r.Activities, r.TeacherNote, r.PublishedAt, r.UpdatedByName, r.UpdatedAt,
        photos = r.Photos.OrderBy(p => p.Id).Select(p => new { p.Id, p.FileName })
    };

    private static string? Clean(string? v, int max)
    {
        if (string.IsNullOrWhiteSpace(v)) return null;
        v = v.Trim();
        return v.Length > max ? v[..max] : v;
    }
}

public class CheckInRequest
{
    public DateTime? Date { get; set; }
    /// <summary>"08:05"; empty = now.</summary>
    public string? Time { get; set; }
}

public class CheckOutRequest : CheckInRequest
{
    [StringLength(150)] public string? PickedUpBy { get; set; }
}

public class AbsentRequest
{
    public DateTime? Date { get; set; }
    [StringLength(300)] public string? Reason { get; set; }
}

public class ParentNoteRequest
{
    public int StudentId { get; set; }
    public string Kind { get; set; } = ParentNote.Absence;
    public DateTime FromDate { get; set; }
    public DateTime? ToDate { get; set; }
    [StringLength(150)]  public string? PickupName { get; set; }
    [StringLength(30)]   public string? PickupPhone { get; set; }
    [StringLength(5)]    public string? PickupTime { get; set; }
    [StringLength(1000)] public string? Message { get; set; }
}

public class DailyReportRequest
{
    public string? Breakfast { get; set; }
    public string? Lunch { get; set; }
    public string? Snack { get; set; }
    public string? NapFrom { get; set; }
    public string? NapTo { get; set; }
    [StringLength(200)]  public string? Toilet { get; set; }
    public string? Mood { get; set; }
    [StringLength(1000)] public string? Activities { get; set; }
    [StringLength(1000)] public string? TeacherNote { get; set; }
    /// <summary>Also send it to the parents now.</summary>
    public bool Publish { get; set; }
}

public class PublishReportsRequest
{
    public DateTime? Date { get; set; }
    public List<int>? StudentIds { get; set; }
}
