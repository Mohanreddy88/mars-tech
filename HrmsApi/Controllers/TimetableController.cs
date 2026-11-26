using System.Globalization;
using System.Security.Claims;
using HrmsApi.Data;
using HrmsApi.Models;
using HrmsApi.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace HrmsApi.Controllers;

/// <summary>
/// School → Timetable: each class's weekly periods ("Mon 09:00–10:00 Phonics, Ms Aisha").
/// Class teachers set up their class's week (admins view it). Teachers see "My timetable" (periods they teach, plus their classes' periods
/// with no teacher named) and write a "what we covered" note per period per day. Parents see their
/// child's class timetable with those notes.
/// </summary>
[ApiController]
[Route("api/school/timetable")]
[Authorize]
[RequiresSchoolFeatures]
public class TimetableController : ControllerBase
{
    private readonly HrmsDbContext _db;
    private readonly IAuditService _audit;

    public TimetableController(HrmsDbContext db, IAuditService audit)
    {
        _db = db; _audit = audit;
    }

    /// <summary>GET /api/school/timetable?classId=&amp;date= — a class's whole week (staff of the class, its parents, admins).</summary>
    [HttpGet]
    public async Task<IActionResult> ForClass([FromQuery] int classId, [FromQuery] DateTime? date)
    {
        var me = await SchoolViewer.LoadAsync(_db, User);
        if (me == null) return Forbid();
        var cls = await _db.SchoolClasses.AsNoTracking().Where(c => c.Id == classId).Select(c => new { c.Id, c.Name }).FirstOrDefaultAsync()
                  ?? throw new KeyNotFoundException("Class not found.");
        if (!await CanSeeClassAsync(me, classId)) return Forbid();

        var day = (date ?? SchoolClock.Today).Date;
        return Ok(new { classId = cls.Id, className = cls.Name, date = day.ToString("yyyy-MM-dd"), dayOfWeek = Iso(day),
                        slots = await SlotsAsync(_db.TimetableSlots.Where(s => s.ClassId == classId), day, me) });
    }

    /// <summary>GET /api/school/timetable/child/{studentId}?date= — the child's class timetable (parents, staff).</summary>
    [HttpGet("child/{studentId:int}")]
    public async Task<IActionResult> ForChild(int studentId, [FromQuery] DateTime? date)
    {
        var me = await SchoolViewer.LoadAsync(_db, User);
        var s = await _db.Students.AsNoTracking().Where(x => x.Id == studentId)
            .Select(x => new { x.Id, x.FullName, x.ClassId, className = x.Class != null ? x.Class.Name : null })
            .FirstOrDefaultAsync() ?? throw new KeyNotFoundException("Child not found.");
        if (me == null || !me.CanSeeStudent(s.Id, s.ClassId)) return Forbid();

        var day = (date ?? SchoolClock.Today).Date;
        var slots = s.ClassId == null ? new List<object>() : await SlotsAsync(_db.TimetableSlots.Where(x => x.ClassId == s.ClassId), day, me);
        return Ok(new { studentId = s.Id, s.FullName, classId = s.ClassId, s.className, date = day.ToString("yyyy-MM-dd"), dayOfWeek = Iso(day), slots });
    }

    /// <summary>
    /// GET /api/school/timetable/mine?date= — the signed-in employee's week: periods they teach and
    /// their classes' periods with no teacher named, with the day's notes.
    /// </summary>
    [HttpGet("mine")]
    public async Task<IActionResult> Mine([FromQuery] DateTime? date)
    {
        var me = await SchoolViewer.LoadAsync(_db, User);
        if (me == null || me.IsParent) return Forbid();
        var day = (date ?? SchoolClock.Today).Date;
        var empId = me.EmployeeId;
        var classIds = me.TeacherClassIds;
        var q = _db.TimetableSlots.Where(s => (empId != null && s.TeacherEmployeeId == empId)
                                              || (s.TeacherEmployeeId == null && classIds.Contains(s.ClassId)));
        return Ok(new { date = day.ToString("yyyy-MM-dd"), dayOfWeek = Iso(day), slots = await SlotsAsync(q, day, me) });
    }

    /// <summary>GET /api/school/timetable/teachers — active employees to choose as a period's teacher (admins, class teachers).</summary>
    [HttpGet("teachers")]
    public async Task<IActionResult> Teachers()
    {
        var me = await SchoolViewer.LoadAsync(_db, User);
        if (me == null || !(me.IsAdmin || me.TeacherClassIds.Count > 0)) return Forbid();
        return Ok(await _db.Employees.AsNoTracking().Where(e => e.IsActive).OrderBy(e => e.Name)
            .Select(e => new { e.Id, e.Name }).ToListAsync());
    }

    /// <summary>POST /api/school/timetable/slots — add a period (the class's teachers; admins too).</summary>
    [HttpPost("slots")]
    public async Task<IActionResult> Create([FromBody] TimetableSlotRequest req)
    {
        var me = await SchoolViewer.LoadAsync(_db, User);
        if (me == null || !CanEditClass(me, req.ClassId)) return Forbid();
        var slot = new TimetableSlot { ActiveFrom = SchoolClock.Today };
        var error = await ApplyAsync(slot, req, null);
        if (error != null) return BadRequest(error);
        _db.TimetableSlots.Add(slot);
        await _db.SaveChangesAsync();
        await Audit("Created", slot.Id, $"Timetable: added {Describe(slot)}");
        return Ok(new { slot.Id });
    }

    [HttpPut("slots/{id:int}")]
    public async Task<IActionResult> Update(int id, [FromBody] TimetableSlotRequest req)
    {
        var me = await SchoolViewer.LoadAsync(_db, User);
        var slot = await ActiveSlotAsync(id);
        // Both the period's current class and the class it moves to must be the teacher's
        if (me == null || !CanEditClass(me, slot.ClassId) || !CanEditClass(me, req.ClassId)) return Forbid();
        var error = await ApplyAsync(slot, req, id);
        if (error != null) return BadRequest(error);
        await _db.SaveChangesAsync();
        await Audit("Updated", slot.Id, $"Timetable: updated {Describe(slot)}");
        return Ok(new { slot.Id });
    }

    [HttpDelete("slots/{id:int}")]
    public async Task<IActionResult> Delete(int id)
    {
        var me = await SchoolViewer.LoadAsync(_db, User);
        var slot = await ActiveSlotAsync(id);
        if (me == null || !CanEditClass(me, slot.ClassId)) return Forbid();
        await RemoveSlotsAsync(new[] { slot });
        await _db.SaveChangesAsync();
        await Audit("Deleted", id, $"Timetable: removed {Describe(slot)}");
        return NoContent();
    }

    /// <summary>
    /// POST /api/school/timetable/copy — copy one day's periods of a class to other days
    /// (e.g. Monday → Tuesday–Friday). The target days' periods are replaced.
    /// </summary>
    [HttpPost("copy")]
    public async Task<IActionResult> CopyDay([FromBody] TimetableCopyRequest req)
    {
        var me = await SchoolViewer.LoadAsync(_db, User);
        if (me == null || !CanEditClass(me, req.ClassId)) return Forbid();
        if (req.FromDay is < 1 or > 7) return BadRequest(new { message = "Choose the day to copy." });
        var targets = (req.ToDays ?? new()).Where(d => d is >= 1 and <= 7 && d != req.FromDay).Distinct().ToList();
        if (targets.Count == 0) return BadRequest(new { message = "Choose at least one day to copy to." });
        if (!await _db.SchoolClasses.AnyAsync(c => c.Id == req.ClassId)) return BadRequest(new { message = "Choose a class." });

        var source = await _db.TimetableSlots.AsNoTracking()
            .Where(s => s.ClassId == req.ClassId && s.DayOfWeek == req.FromDay && s.RemovedOn == null).ToListAsync();
        if (source.Count == 0) return BadRequest(new { message = "That day has no periods to copy." });

        await RemoveSlotsAsync(await _db.TimetableSlots
            .Where(s => s.ClassId == req.ClassId && targets.Contains(s.DayOfWeek) && s.RemovedOn == null).ToListAsync());
        foreach (var d in targets)
            foreach (var s in source)
                _db.TimetableSlots.Add(new TimetableSlot
                {
                    ClassId = s.ClassId, DayOfWeek = d, StartTime = s.StartTime, EndTime = s.EndTime,
                    Subject = s.Subject, TeacherEmployeeId = s.TeacherEmployeeId, Notes = s.Notes,
                    ActiveFrom = SchoolClock.Today
                });
        await _db.SaveChangesAsync();
        await Audit("Updated", req.ClassId, $"Timetable: copied {DayName(req.FromDay)} to {string.Join(", ", targets.Select(DayName))} (class {req.ClassId})");
        return Ok(new { copied = source.Count * targets.Count });
    }

    /// <summary>
    /// PUT /api/school/timetable/slots/{id}/log — "what we covered" for that period on a date
    /// (the period's teacher, the class's teachers, admins). An empty note removes it.
    /// </summary>
    [HttpPut("slots/{id:int}/log")]
    public async Task<IActionResult> SaveLog(int id, [FromBody] TimetableLogRequest req)
    {
        var me = await SchoolViewer.LoadAsync(_db, User);
        var found = await _db.TimetableSlots.AsNoTracking()
            .Where(s => s.Id == id)
            .Select(s => new { Slot = s, teacherName = s.Teacher != null ? s.Teacher.Name : s.Class.ClassTeacher != null ? s.Class.ClassTeacher.Name : null })
            .FirstOrDefaultAsync() ?? throw new KeyNotFoundException("Period not found.");
        var slot = found.Slot;
        if (me == null || !CanWriteLog(me, slot)) return Forbid();

        var day = (req.Date ?? SchoolClock.Today).Date;
        if (day > SchoolClock.Today) return BadRequest(new { message = "You can write the note on the day, not before." });
        if (!me.IsAdmin && day != SchoolClock.Today)
            return BadRequest(new { message = "Teachers can write the note only for today. Earlier days are read-only." });
        if (Iso(day) != slot.DayOfWeek) return BadRequest(new { message = $"This period is on {DayName(slot.DayOfWeek)}s." });
        if (!ActiveOn(slot, day)) return BadRequest(new { message = "This period wasn't on the timetable that day." });
        var note = (req.Note ?? "").Trim();
        if (note.Length > 1000) return BadRequest(new { message = "Keep the note under 1000 characters." });

        var log = await _db.TimetableLogs.FirstOrDefaultAsync(l => l.SlotId == id && l.Date == day);
        if (note.Length == 0)
        {
            if (log != null) { _db.TimetableLogs.Remove(log); await _db.SaveChangesAsync(); }
            return NoContent();
        }
        if (log == null) { log = new TimetableLog { SlotId = id, Date = day }; _db.TimetableLogs.Add(log); }
        log.Note = note;
        log.UpdatedByName = me.Name;
        log.UpdatedAt = DateTime.UtcNow;
        // The period as it is now, so the daily record stays right if the plan changes later
        log.StartTime = slot.StartTime;
        log.EndTime = slot.EndTime;
        log.Subject = slot.Subject;
        log.TeacherName = found.teacherName;
        await _db.SaveChangesAsync();
        return Ok(new { log.Note, log.UpdatedByName, log.UpdatedAt });
    }

    /// <summary>
    /// GET /api/school/timetable/record?classId=&amp;from=&amp;to= — the daily record (admins): for each
    /// date, the periods on the plan that day (or with a note) and the teacher's "what we covered"
    /// note. classId empty = every class. At most 31 days.
    /// </summary>
    [HttpGet("record")]
    [Authorize(Roles = UserAccess.Admin)]
    public async Task<IActionResult> Record([FromQuery] int? classId, [FromQuery] DateTime from, [FromQuery] DateTime? to)
    {
        var f = from.Date;
        var t = (to ?? from).Date;
        if (t < f) return BadRequest(new { message = "The end date must be on or after the start date." });
        if ((t - f).TotalDays > 30) return BadRequest(new { message = "Choose at most 31 days." });
        var today = SchoolClock.Today;

        var slots = await _db.TimetableSlots.AsNoTracking()
            .Where(s => (classId == null || s.ClassId == classId) && s.ActiveFrom <= t && (s.RemovedOn == null || s.RemovedOn > f))
            .Select(s => new
            {
                s.Id, s.ClassId, className = s.Class.Name, classOrder = s.Class.SortOrder, s.DayOfWeek, s.StartTime, s.EndTime,
                s.Subject, s.ActiveFrom, s.RemovedOn,
                teacherName = s.Teacher != null ? s.Teacher.Name : s.Class.ClassTeacher != null ? s.Class.ClassTeacher.Name : null
            }).ToListAsync();
        var logs = await _db.TimetableLogs.AsNoTracking()
            .Where(l => l.Date >= f && l.Date <= t && (classId == null || l.Slot.ClassId == classId))
            .Select(l => new
            {
                l.SlotId, l.Date, l.Note, l.UpdatedByName, l.UpdatedAt, l.StartTime, l.EndTime, l.Subject, l.TeacherName,
                l.Slot.ClassId, className = l.Slot.Class.Name, classOrder = l.Slot.Class.SortOrder,
                slotStart = l.Slot.StartTime, slotEnd = l.Slot.EndTime, slotSubject = l.Slot.Subject
            }).ToListAsync();

        var days = new List<object>();
        int periods = 0, written = 0;
        for (var d = f; d <= t; d = d.AddDays(1))
        {
            var dow = Iso(d);
            var dayLogs = logs.Where(l => l.Date == d).ToList();
            var rows = slots.Where(s => s.DayOfWeek == dow && s.ActiveFrom <= d && (s.RemovedOn == null || s.RemovedOn > d))
                .Select(s =>
                {
                    var l = dayLogs.FirstOrDefault(x => x.SlotId == s.Id);
                    return new RecordRow(s.Id, s.ClassId, s.className, s.classOrder,
                        l?.StartTime ?? s.StartTime, l?.EndTime ?? s.EndTime, l?.Subject ?? s.Subject, l?.TeacherName ?? s.teacherName,
                        l?.Note, l?.UpdatedByName, l?.UpdatedAt);
                }).ToList();
            // Notes on periods no longer on the plan that day (moved or removed since)
            rows.AddRange(dayLogs.Where(l => rows.All(r => r.SlotId != l.SlotId)).Select(l => new RecordRow(
                l.SlotId, l.ClassId, l.className, l.classOrder, l.StartTime ?? l.slotStart, l.EndTime ?? l.slotEnd,
                l.Subject ?? l.slotSubject, l.TeacherName, l.Note, l.UpdatedByName, l.UpdatedAt)).ToList());

            if (d <= today) { periods += rows.Count; written += rows.Count(r => r.Note != null); }
            days.Add(new
            {
                date = d.ToString("yyyy-MM-dd"), dayOfWeek = dow,
                periods = rows.OrderBy(r => r.ClassOrder).ThenBy(r => r.ClassName).ThenBy(r => r.Start).Select(r => new
                {
                    slotId = r.SlotId, classId = r.ClassId, className = r.ClassName, startTime = Hm(r.Start), endTime = Hm(r.End),
                    subject = r.Subject, teacherName = r.TeacherName, note = r.Note, noteBy = r.NoteBy, noteAt = r.NoteAt
                }).ToList()
            });
        }
        return Ok(new { from = f.ToString("yyyy-MM-dd"), to = t.ToString("yyyy-MM-dd"), today = today.ToString("yyyy-MM-dd"),
                        days, summary = new { periods, written } });
    }

    private sealed record RecordRow(int SlotId, int ClassId, string ClassName, int ClassOrder, TimeSpan Start, TimeSpan End,
        string Subject, string? TeacherName, string? Note, string? NoteBy, DateTime? NoteAt);

    // ── helpers ──

    /// <summary>On the plan on that school date (added on or before it, not removed by then).</summary>
    private static bool ActiveOn(TimetableSlot s, DateTime day) => s.ActiveFrom <= day && (s.RemovedOn == null || s.RemovedOn > day);

    private async Task<TimetableSlot> ActiveSlotAsync(int id) =>
        await _db.TimetableSlots.FirstOrDefaultAsync(s => s.Id == id && s.RemovedOn == null)
        ?? throw new KeyNotFoundException("Period not found.");

    /// <summary>
    /// Takes periods off the plan from today. They are kept (hidden) so past weeks and their notes stay
    /// as they were; one added today with no notes yet is simply deleted (a mistake).
    /// </summary>
    private async Task RemoveSlotsAsync(IEnumerable<TimetableSlot> slots)
    {
        var today = SchoolClock.Today;
        var list = slots.ToList();
        var ids = list.Select(s => s.Id).ToList();
        var withNotes = await _db.TimetableLogs.Where(l => ids.Contains(l.SlotId)).Select(l => l.SlotId).Distinct().ToListAsync();
        foreach (var s in list)
        {
            if (s.ActiveFrom >= today && !withNotes.Contains(s.Id)) _db.TimetableSlots.Remove(s);
            else s.RemovedOn = today;
        }
    }

    private static int Iso(DateTime d) => d.DayOfWeek == DayOfWeek.Sunday ? 7 : (int)d.DayOfWeek;
    private static string DayName(int iso) => CultureInfo.InvariantCulture.DateTimeFormat.GetDayName((DayOfWeek)(iso % 7));
    private static string Hm(TimeSpan t) => t.ToString(@"hh\:mm");
    private static string Describe(TimetableSlot s) => $"{DayName(s.DayOfWeek)} {Hm(s.StartTime)}–{Hm(s.EndTime)} {s.Subject} (class {s.ClassId})";

    /// <summary>Class teachers set up their class's timetable; admins may too (e.g. a class with no teacher yet).</summary>
    private static bool CanEditClass(SchoolViewer me, int classId) =>
        !me.IsParent && (me.IsAdmin || me.TeacherClassIds.Contains(classId));

    private bool CanWriteLog(SchoolViewer me, TimetableSlot s) =>
        me.IsAdmin
        || me.TeacherClassIds.Contains(s.ClassId)
        || (me.EmployeeId != null && s.TeacherEmployeeId == me.EmployeeId);

    private async Task<bool> CanSeeClassAsync(SchoolViewer me, int classId)
    {
        if (me.IsAdmin || me.TeacherClassIds.Contains(classId)) return true;
        if (me.IsParent)
            return await _db.Students.AnyAsync(s => me.ChildIds.Contains(s.Id) && s.ClassId == classId);
        // A subject teacher who teaches one of the class's periods
        return me.EmployeeId != null && await _db.TimetableSlots.AnyAsync(s => s.ClassId == classId && s.TeacherEmployeeId == me.EmployeeId && s.RemovedOn == null);
    }

    /// <summary>Periods in time order, with the note for <paramref name="day"/> on that weekday's periods.</summary>
    private async Task<List<object>> SlotsAsync(IQueryable<TimetableSlot> q, DateTime day, SchoolViewer me)
    {
        var dow = Iso(day);
        var rows = await q.AsNoTracking().Where(s => s.RemovedOn == null)
            .OrderBy(s => s.DayOfWeek).ThenBy(s => s.StartTime)
            .Select(s => new
            {
                s.Id, s.ClassId, className = s.Class.Name, s.DayOfWeek, s.StartTime, s.EndTime, s.Subject, s.Notes,
                s.TeacherEmployeeId,
                teacherName = s.Teacher != null ? s.Teacher.Name : s.Class.ClassTeacher != null ? s.Class.ClassTeacher.Name : null,
                log = s.DayOfWeek == dow
                    ? s.Logs.Where(l => l.Date == day).Select(l => new { l.Note, l.UpdatedByName, l.UpdatedAt }).FirstOrDefault()
                    : null
            }).ToListAsync();
        return rows.Select(s => (object)new
        {
            s.Id, s.ClassId, s.className, s.DayOfWeek, startTime = Hm(s.StartTime), endTime = Hm(s.EndTime),
            s.Subject, s.Notes, s.TeacherEmployeeId, s.teacherName, s.log,
            // Teachers write "what we covered" for today only (earlier days are read-only); admins any past day
            canWriteLog = !me.IsParent && s.DayOfWeek == dow && day <= SchoolClock.Today && (me.IsAdmin || day == SchoolClock.Today)
                          && (me.IsAdmin || me.TeacherClassIds.Contains(s.ClassId)
                          || (me.EmployeeId != null && s.TeacherEmployeeId == me.EmployeeId))
        }).ToList();
    }

    private async Task<object?> ApplyAsync(TimetableSlot slot, TimetableSlotRequest req, int? id)
    {
        if (!await _db.SchoolClasses.AnyAsync(c => c.Id == req.ClassId)) return new { message = "Choose a class.", field = "classId" };
        if (req.DayOfWeek is < 1 or > 7) return new { message = "Choose the day.", field = "dayOfWeek" };
        if (!TimeSpan.TryParseExact(req.StartTime ?? "", @"hh\:mm", CultureInfo.InvariantCulture, out var start))
            return new { message = "Enter the start time.", field = "startTime" };
        if (!TimeSpan.TryParseExact(req.EndTime ?? "", @"hh\:mm", CultureInfo.InvariantCulture, out var end))
            return new { message = "Enter the end time.", field = "endTime" };
        if (end <= start) return new { message = "The end time must be after the start time.", field = "endTime" };
        var subject = (req.Subject ?? "").Trim();
        if (subject.Length == 0) return new { message = "Enter what is taught (subject or activity).", field = "subject" };
        if (subject.Length > 100) return new { message = "Keep the subject under 100 characters.", field = "subject" };
        if (req.TeacherEmployeeId != null && !await _db.Employees.AnyAsync(e => e.Id == req.TeacherEmployeeId))
            return new { message = "Choose the teacher again.", field = "teacherEmployeeId" };

        var clash = await _db.TimetableSlots.AsNoTracking()
            .Where(s => s.ClassId == req.ClassId && s.DayOfWeek == req.DayOfWeek && s.Id != (id ?? 0)
                        && s.RemovedOn == null && s.StartTime < end && start < s.EndTime)
            .Select(s => new { s.Subject, s.StartTime, s.EndTime }).FirstOrDefaultAsync();
        if (clash != null)
            return new { message = $"Overlaps {clash.Subject} ({Hm(clash.StartTime)}–{Hm(clash.EndTime)}) on {DayName(req.DayOfWeek)}.", field = "startTime" };

        slot.ClassId = req.ClassId;
        slot.DayOfWeek = req.DayOfWeek;
        slot.StartTime = start;
        slot.EndTime = end;
        slot.Subject = subject;
        slot.TeacherEmployeeId = req.TeacherEmployeeId;
        slot.Notes = string.IsNullOrWhiteSpace(req.Notes) ? null : req.Notes.Trim()[..Math.Min(500, req.Notes.Trim().Length)];
        return null;
    }

    private Task Audit(string action, int id, string description) =>
        _audit.LogAsync(action, "Timetable", id.ToString(), description, User.Identity?.Name ?? "unknown",
            int.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out var uid) ? uid : null,
            null, null, HttpContext.Connection.RemoteIpAddress?.ToString());
}

public class TimetableSlotRequest
{
    public int ClassId { get; set; }
    public int DayOfWeek { get; set; }
    /// <summary>"HH:mm".</summary>
    public string? StartTime { get; set; }
    public string? EndTime { get; set; }
    public string? Subject { get; set; }
    public int? TeacherEmployeeId { get; set; }
    public string? Notes { get; set; }
}

public class TimetableCopyRequest
{
    public int ClassId { get; set; }
    public int FromDay { get; set; }
    public List<int>? ToDays { get; set; }
}

public class TimetableLogRequest
{
    public DateTime? Date { get; set; }
    public string? Note { get; set; }
}
