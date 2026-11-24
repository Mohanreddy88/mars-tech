using HrmsApi.Data;
using HrmsApi.Hubs;
using HrmsApi.Models;
using HrmsApi.Platform;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;

namespace HrmsApi.Services;

/// <summary>
/// The automatic steps of a school day, for one company (its database is the current one):
///   at "late after" (9:00)        — parents of children not checked in yet are asked if they're coming;
///   at "absent after" (9:30)      — children still not in are marked absent (with the parent's
///                                   absence note as the reason, if there is one) and parents are told;
///   at "automatic check-out" (7pm) — children the teacher didn't check out are checked out at their
///                                   session's end time, marked "automatic"; the office is told.
/// Each step runs once a day; reminders and absences only on school days (Mon–Fri, not a public holiday).
/// </summary>
public static class SchoolDayAutomation
{
    public const string AutoBy = "Automatic";

    public static async Task RunAsync(HrmsDbContext db, IPushService push, IChatNotifier live, DateTime nowUtc,
        ILogger? logger = null)
    {
        var s = await db.CompanySettings.FirstOrDefaultAsync();
        if (s == null || !s.SchoolFeaturesEnabled || !s.SchoolAutoAttendance) return;
        var times = await SchoolTimes.LoadAsync(db, s);   // session hours from the price list in force
        var local = DateTime.SpecifyKind(nowUtc, DateTimeKind.Utc) + SchoolClock.Offset;
        var today = local.Date;
        var now = TimeOnly.FromDateTime(local);

        // Evening: anyone still checked in today goes home "automatically" (any day there is attendance)
        if (now >= times.AutoCheckOutAt && s.SchoolAutoCheckOutOn != today)
        {
            s.SchoolAutoCheckOutOn = today;
            await db.SaveChangesAsync();
            await AutoCheckOutAsync(db, push, live, times, today, logger);
        }

        var schoolDay = today.DayOfWeek is not (DayOfWeek.Saturday or DayOfWeek.Sunday)
                        && !await db.PublicHolidays.AnyAsync(h => h.Date.Date == today);
        if (!schoolDay) return;

        // Only on days the school is taking attendance (someone checked in): otherwise nobody is
        // reminded or marked absent — e.g. a day the teachers don't use check-in at all.
        var takingAttendance = await db.StudentAttendance.AnyAsync(a => a.Date == today && a.CheckInAt != null);

        if (now >= times.LateAfter && now < times.AbsentAfter && s.SchoolRemindedOn != today && takingAttendance)
        {
            s.SchoolRemindedOn = today;
            await db.SaveChangesAsync();
            await RemindParentsAsync(db, push, live, times, today, logger);
        }

        if (now >= times.AbsentAfter && s.SchoolAutoAbsentOn != today)
        {
            // Never mark a whole day absent after the fact (server started or updated late in the day)
            var windowEnd = times.AbsentAfter.AddHours(2);
            if (windowEnd < times.AbsentAfter) windowEnd = new TimeOnly(23, 59);   // past midnight
            if (now >= windowEnd || now >= times.AutoCheckOutAt)
            {
                s.SchoolAutoAbsentOn = today;
                await db.SaveChangesAsync();
            }
            else if (takingAttendance)
            {
                s.SchoolAutoAbsentOn = today;
                s.SchoolRemindedOn ??= today;   // past the reminder time too
                await db.SaveChangesAsync();
                await MarkAbsentAsync(db, push, live, times, today, logger);
            }
        }
    }

    /// <summary>Active children with no attendance yet today, and whether a parent reported them absent.</summary>
    private static async Task<List<(Student child, ParentNote? absence)>> NotInYetAsync(HrmsDbContext db, DateTime today)
    {
        var marked = db.StudentAttendance.Where(a => a.Date == today).Select(a => a.StudentId);
        var kids = await db.Students.Where(s => s.IsActive && !marked.Contains(s.Id)).ToListAsync();
        var ids = kids.Select(k => k.Id).ToList();
        var notes = await db.ParentNotes.AsNoTracking()
            .Where(n => ids.Contains(n.StudentId) && n.Kind == ParentNote.Absence && n.CancelledAt == null
                        && n.FromDate <= today && n.ToDate >= today)
            .ToListAsync();
        return kids.Select(k => (k, notes.FirstOrDefault(n => n.StudentId == k.Id))).ToList();
    }

    private static async Task RemindParentsAsync(HrmsDbContext db, IPushService push, IChatNotifier live, SchoolTimes t,
        DateTime today, ILogger? logger)
    {
        var list = await NotInYetAsync(db, today);
        foreach (var (child, absence) in list.Where(x => x.absence == null))
        {
            var parents = await SchoolParticipants.ParentUserIdsAsync(db, child.Id);
            await SchoolAlerts.SendAsync(db, push, live, parents, $"{child.FullName} hasn't arrived yet",
                $"Is {child.FullName} coming to school today? If not, please report the absence before " +
                $"{t.AbsentAfter:HH\\:mm}, or {child.FullName} will be marked absent.",
                "school_attendance", $"/parent/child/{child.Id}?date={today:yyyy-MM-dd}", "attendance", new { studentId = child.Id });
        }
        logger?.LogInformation("School day: reminded parents of {Count} children not in yet", list.Count(x => x.absence == null));
    }

    private static async Task MarkAbsentAsync(HrmsDbContext db, IPushService push, IChatNotifier live, SchoolTimes t,
        DateTime today, ILogger? logger)
    {
        var list = await NotInYetAsync(db, today);
        foreach (var (child, absence) in list)
        {
            db.StudentAttendance.Add(new StudentAttendance
            {
                StudentId = child.Id, Date = today, Status = StudentAttendance.Absent, AutoAbsent = true,
                AbsenceReason = absence != null
                    ? "Reported by parent" + (absence.Message != null ? $": {absence.Message}" : "")
                    : $"Not checked in by {t.AbsentAfter:HH\\:mm}"
            });
        }
        await db.SaveChangesAsync();

        // Parents who didn't tell the school hear that their child was marked absent
        foreach (var (child, _) in list.Where(x => x.absence == null))
        {
            var parents = await SchoolParticipants.ParentUserIdsAsync(db, child.Id);
            await SchoolAlerts.SendAsync(db, push, live, parents, $"{child.FullName} was marked absent today",
                $"{child.FullName} wasn't checked in by {t.AbsentAfter:HH\\:mm}. If {child.FullName} is on the way, " +
                "the teacher will check them in on arrival.",
                "school_attendance", $"/parent/child/{child.Id}?date={today:yyyy-MM-dd}", "attendance", new { studentId = child.Id });
        }
        logger?.LogInformation("School day: {Count} children marked absent automatically", list.Count);
    }

    private static async Task AutoCheckOutAsync(HrmsDbContext db, IPushService push, IChatNotifier live, SchoolTimes t,
        DateTime today, ILogger? logger)
    {
        var open = await db.StudentAttendance.Include(a => a.Student)
            .Where(a => a.Date == today && a.Status == StudentAttendance.Present && a.CheckInAt != null && a.CheckOutAt == null)
            .ToListAsync();
        if (open.Count == 0) return;
        foreach (var a in open)
        {
            var end = SchoolTimes.ToUtc(today, t.EndFor(a.Student.SessionType));
            a.CheckOutAt = end > a.CheckInAt ? end : a.CheckInAt;
            a.CheckOutBy = AutoBy;
            a.PickedUpBy = "Not recorded";
            a.AutoCheckOut = true;
            a.UpdatedAt = DateTime.UtcNow;
        }
        await db.SaveChangesAsync();

        var office = await SchoolParticipants.StaffUserIdsAsync(db, Conversation.Office, null);
        var names = string.Join(", ", open.Select(a => a.Student.FullName).Take(10)) + (open.Count > 10 ? "…" : "");
        await SchoolAlerts.SendAsync(db, push, live, office, "Children checked out automatically",
            $"{open.Count} child{(open.Count == 1 ? " was" : "ren were")} not checked out today and " +
            $"{(open.Count == 1 ? "was" : "were")} checked out automatically at the session's end: {names}.",
            "school_attendance", $"/school/attendance?date={today:yyyy-MM-dd}", "attendance", new { count = open.Count });
        logger?.LogInformation("School day: {Count} children checked out automatically", open.Count);
    }
}

/// <summary>
/// Runs <see cref="SchoolDayAutomation"/> every two minutes for every active company (each in its
/// own database), or for the single database when companies are switched off.
/// </summary>
public sealed class SchoolDayService : BackgroundService
{
    private static readonly TimeSpan Every = TimeSpan.FromMinutes(2);
    private readonly IServiceScopeFactory _scopes;
    private readonly ILogger<SchoolDayService> _logger;

    public SchoolDayService(IServiceScopeFactory scopes, ILogger<SchoolDayService> logger)
    {
        _scopes = scopes; _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        // Let the app finish starting (migrations) first
        try { await Task.Delay(TimeSpan.FromMinutes(1), stoppingToken); } catch (OperationCanceledException) { return; }

        while (!stoppingToken.IsCancellationRequested)
        {
            try { await RunOnceAsync(); }
            catch (Exception ex) { _logger.LogWarning(ex, "School day automation failed"); }
            try { await Task.Delay(Every, stoppingToken); } catch (OperationCanceledException) { return; }
        }
    }

    private async Task RunOnceAsync()
    {
        using var root = _scopes.CreateScope();
        var tenancy = root.ServiceProvider.GetRequiredService<IOptions<TenancyOptions>>().Value;
        if (!tenancy.Enabled)
        {
            await RunForCurrentAsync(root.ServiceProvider, "default");
            return;
        }
        var catalog = root.ServiceProvider.GetRequiredService<TenantCatalog>();
        foreach (var tenant in (await catalog.AllAsync()).Where(t => t.Status == TenantStatus.Active))
        {
            using var scope = _scopes.CreateScope();
            scope.ServiceProvider.GetRequiredService<ITenantContext>().Use(tenant);
            try { await RunForCurrentAsync(scope.ServiceProvider, tenant.Slug); }
            catch (Exception ex) { _logger.LogWarning(ex, "School day automation failed for {Company}", tenant.Slug); }
        }
    }

    private async Task RunForCurrentAsync(IServiceProvider sp, string company)
    {
        var db = sp.GetRequiredService<HrmsDbContext>();
        await SchoolDayAutomation.RunAsync(db, sp.GetRequiredService<IPushService>(), sp.GetRequiredService<IChatNotifier>(),
            DateTime.UtcNow, _logger);
    }
}
