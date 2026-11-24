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
/// The sliding "highlights" cards at the top of the admin home (website and app): what needs
/// attention right now, built from the company's own data. A card is only there when it applies;
/// with nothing to do there is one "All caught up" card.
/// Each card has a <c>page</c> key; the website and the app open their own screen for it.
/// </summary>
[ApiController]
[Route("api/dashboard")]
[Authorize(Roles = UserAccess.Admin)]
public class HighlightsController : ControllerBase
{
    private readonly HrmsDbContext _db;
    private readonly ICompanySettingsService _settings;

    public HighlightsController(HrmsDbContext db, ICompanySettingsService settings)
    {
        _db = db; _settings = settings;
    }

    /// <summary>Payroll for the month is expected from this day on.</summary>
    private const int PayrollDueDay = 20;

    /// <summary>GET /api/dashboard/highlights — the admin's highlight cards, most urgent first.</summary>
    [HttpGet("highlights")]
    public async Task<IActionResult> Get()
    {
        var settings = await _settings.GetAsync();
        var today = SchoolClock.Today;
        var cards = new List<HighlightCard>();

        // ── HR: things to do ──
        var leaves = await _db.LeaveRequests.CountAsync(l => l.Status == "Pending");
        if (leaves > 0)
            cards.Add(new("leave", "hr", "leave", "warn", $"{leaves} leave request{S(leaves)} waiting",
                "Approve or reject them so the team knows where they stand.", "approvals", "Review"));

        var periods = await _db.AttendancePeriods.CountAsync(p => p.Status == "Submitted");
        var timesheets = await _db.Timesheets.CountAsync(t => t.Status == "Submitted");
        if (periods + timesheets > 0)
            cards.Add(new("attendance", "hr", "attendance", "warn", $"{periods + timesheets} attendance submission{S(periods + timesheets)} to approve",
                "Approved attendance is used for payroll.", "approvals-attendance", "Review"));

        if (today.Day >= PayrollDueDay
            && await _db.Employees.AnyAsync(e => e.IsActive)
            && !await _db.Payrolls.AnyAsync(p => p.Month == today.Month && p.Year == today.Year))
        {
            var month = today.ToString("MMMM", CultureInfo.InvariantCulture);
            cards.Add(new("payroll", "hr", "payroll", "warn", $"{month} payroll not generated yet",
                "Generate the payslips before the month ends.", "payroll", "Run payroll"));
        }

        // ── School: things to do ──
        if (settings.SchoolFeaturesEnabled)
        {
            var pickups = await _db.PickupPeople.CountAsync(p => p.Status == PickupPerson.Pending);
            if (pickups > 0)
                cards.Add(new("pickup", "school", "pickup", "warn", $"{pickups} pick-up {(pickups == 1 ? "person" : "people")} to approve",
                    "Parents added them to collect their children.", "pickup-people", "Review"));

            var claims = await _db.FeePaymentClaims.CountAsync(c => c.Status == FeePaymentClaim.Pending);
            if (claims > 0)
                cards.Add(new("fees", "school", "fees", "warn", $"{claims} fee payment{S(claims)} to confirm",
                    "Parents said they've paid — check and confirm.", "school-fees", "Confirm"));

            var unread = await OfficeUnreadAsync();
            if (unread > 0)
                cards.Add(new("messages", "school", "messages", "info", $"{unread} unread parent message{S(unread)}",
                    "Parents are waiting for the office's reply.", "school-messages", "Open"));
        }

        // Chatbot AI stopped (no credit / key not accepted)
        if (settings.AssistantAiEnabled)
        {
            var last = await _db.BotAiUsageLog.AsNoTracking().OrderByDescending(u => u.AskedAt).ThenByDescending(u => u.Id).FirstOrDefaultAsync();
            if (last is { Succeeded: false } && AiErrors.IsBlocking(last.Error)
                && (settings.AssistantAiKeySetAt == null || settings.AssistantAiKeySetAt < last.AskedAt))
                cards.Add(new("ai", "hr", "ai", "bad", "Chatbot AI answers stopped", last.Error!, "chatbot", "Fix"));
        }

        // ── Today and coming up (information) ──
        if (settings.SchoolFeaturesEnabled && today.DayOfWeek is not (DayOfWeek.Saturday or DayOfWeek.Sunday))
        {
            var children = await _db.Students.CountAsync(s => s.IsActive);
            if (children > 0)
            {
                var att = _db.StudentAttendance.Where(a => a.Date == today);
                var checkedIn = await att.CountAsync(a => a.Status == StudentAttendance.Present && a.CheckInAt != null);
                var absent = await att.CountAsync(a => a.Status == StudentAttendance.Absent);
                var late = await att.CountAsync(a => a.IsLate);
                cards.Add(new("today", "school", "children", "good", $"{checkedIn} of {children} children checked in today",
                    string.Join(" · ", new[] { absent > 0 ? $"{absent} absent" : null, late > 0 ? $"{late} late" : null }
                        .Where(x => x != null).DefaultIfEmpty("Attendance for today")),
                    "school-attendance", "Open"));
            }
        }

        var holiday = await _db.PublicHolidays.AsNoTracking()
            .Where(h => h.Date >= today && h.Date <= today.AddDays(30)).OrderBy(h => h.Date).FirstOrDefaultAsync();
        if (holiday != null)
        {
            var days = (holiday.Date.Date - today).Days;
            cards.Add(new("holiday", "hr", "holiday", "info", $"Next public holiday: {holiday.Name}",
                $"{holiday.Date:ddd d MMM}" + (days == 0 ? " · today" : days == 1 ? " · tomorrow" : $" · in {days} days"), "holidays", "View"));
        }

        var birthdays = await BirthdaysThisWeekAsync(today);
        if (birthdays.Count > 0)
            cards.Add(new("birthdays", "hr", "birthday", "info", birthdays.Count == 1 ? "Birthday this week" : $"{birthdays.Count} birthdays this week",
                string.Join(", ", birthdays.Take(4)) + (birthdays.Count > 4 ? "…" : ""), "employees", "Team"));

        if (!cards.Any(c => c.Tone is "warn" or "bad"))
            cards.Insert(0, new("done", "hr", "done", "good", "All caught up", "Nothing waiting for you right now.", null, null));

        // Most urgent first, then the rest in the order added
        var order = new Dictionary<string, int> { ["bad"] = 0, ["warn"] = 1, ["good"] = 2, ["info"] = 3 };
        return Ok(cards.Select((c, i) => (c, i)).OrderBy(x => order[x.c.Tone]).ThenBy(x => x.i).Select(x => x.c));
    }

    /// <summary>"Ms Tan (Thu)" — active employees with a birthday in the next 7 days.</summary>
    private async Task<List<string>> BirthdaysThisWeekAsync(DateTime today)
    {
        var people = await _db.Employees.AsNoTracking().Where(e => e.IsActive && e.DateOfBirth != null)
            .Select(e => new { e.Name, Dob = e.DateOfBirth!.Value }).ToListAsync();
        var list = new List<(DateTime when, string text)>();
        foreach (var p in people)
        {
            for (var d = 0; d < 7; d++)
            {
                var day = today.AddDays(d);
                if (p.Dob.Month == day.Month && p.Dob.Day == day.Day)
                    list.Add((day, $"{p.Name} ({(d == 0 ? "today" : day.ToString("ddd", CultureInfo.InvariantCulture))})"));
            }
        }
        return list.OrderBy(x => x.when).Select(x => x.text).ToList();
    }

    /// <summary>Unread parent messages in office conversations (what the admin is asked to answer).</summary>
    private async Task<int> OfficeUnreadAsync()
    {
        if (!int.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out var me)) return 0;
        return await _db.Conversations.Where(c => c.Kind == Conversation.Office)
            .SelectMany(c => c.Messages.Where(m => m.SenderUserId != me
                && m.Id > (_db.ConversationReads.Where(r => r.ConversationId == c.Id && r.UserId == me)
                    .Select(r => (int?)r.LastReadMessageId).FirstOrDefault() ?? 0)))
            .CountAsync();
    }

    private static string S(int n) => n == 1 ? "" : "s";
}

/// <summary>
/// One highlight card. <c>Group</c>: "hr" or "school". <c>Icon</c>: a name the website and app map
/// to their own icon. <c>Tone</c>: "bad" (broken), "warn" (to do), "good", "info".
/// <c>Page</c>: which screen it opens (each app maps the key), or null.
/// </summary>
public sealed record HighlightCard(string Key, string Group, string Icon, string Tone, string Title, string Text,
    string? Page, string? Action);
