using System.Globalization;
using HrmsApi.Models;

namespace HrmsApi.Services;

/// <summary>
/// The school day's times (Company Settings), in school local time (<see cref="SchoolClock"/>):
/// start, "late after", "absent after", each session's end, and the evening automatic check-out.
/// </summary>
public sealed record SchoolTimes(TimeOnly Start, TimeOnly LateAfter, TimeOnly AbsentAfter, TimeOnly HalfDayEnd,
    TimeOnly FullDayEnd, TimeOnly DaycareEnd, TimeOnly AutoCheckOutAt, bool Auto)
{
    public static readonly SchoolTimes Default = new(new(8, 30), new(9, 0), new(9, 30), new(12, 30), new(16, 30), new(18, 30), new(19, 0), true);

    public static SchoolTimes From(CompanySettings s) => new(
        Parse(s.SchoolStart, Default.Start), Parse(s.SchoolLateAfter, Default.LateAfter), Parse(s.SchoolAbsentAfter, Default.AbsentAfter),
        Parse(s.SchoolHalfDayEnd, Default.HalfDayEnd), Parse(s.SchoolFullDayEnd, Default.FullDayEnd),
        Parse(s.SchoolDaycareEnd, Default.DaycareEnd), Parse(s.SchoolAutoCheckOutAt, Default.AutoCheckOutAt), s.SchoolAutoAttendance);

    /// <summary>
    /// Session hours from the price list in force (Half day 08:00–12:00, Full day 07:30–18:30);
    /// empty when there is none, and then the Company Settings times are used.
    /// </summary>
    public IReadOnlyDictionary<string, (TimeOnly Start, TimeOnly End)> Sessions { get; init; } =
        new Dictionary<string, (TimeOnly, TimeOnly)>();

    /// <summary>The price list the session hours come from ("2027"), or null.</summary>
    public string? PriceList { get; init; }

    /// <summary>When the child's session ends (half day, full day, daycare).</summary>
    public TimeOnly EndFor(string? sessionType) =>
        Sessions.TryGetValue(sessionType ?? "", out var s) ? s.End : sessionType switch
        {
            Student.HalfDay => HalfDayEnd,
            Student.Daycare => DaycareEnd,
            _ => FullDayEnd
        };

    /// <summary>When the child's session starts.</summary>
    public TimeOnly StartFor(string? sessionType) =>
        Sessions.TryGetValue(sessionType ?? "", out var s) ? s.Start : Start;

    /// <summary>
    /// The timings in force: Company Settings, with the session hours of today's price list
    /// (Fees → Price lists) when there is one — so the hours are changed in one place each year.
    /// </summary>
    public static async Task<SchoolTimes> LoadAsync(HrmsApi.Data.HrmsDbContext db, CompanySettings? settings = null)
    {
        settings ??= await Microsoft.EntityFrameworkCore.EntityFrameworkQueryableExtensions
            .FirstOrDefaultAsync(Microsoft.EntityFrameworkCore.EntityFrameworkQueryableExtensions.AsNoTracking(db.CompanySettings))
            ?? new CompanySettings();
        var t = From(settings);
        var list = await FeePrices.ForDateAsync(db, SchoolClock.Today);
        if (list == null) return t;
        var sessions = list.Sessions.Where(s => s.Offered)
            .ToDictionary(s => s.SessionType, s => (Parse(s.Start, t.Start), Parse(s.End, t.FullDayEnd)));
        return t with { Sessions = sessions, PriceList = list.Name };
    }

    /// <summary>A school-local time on a school day, as UTC (how times are stored).</summary>
    public static DateTime ToUtc(DateTime day, TimeOnly t) =>
        DateTime.SpecifyKind(day.Date + t.ToTimeSpan() - SchoolClock.Offset, DateTimeKind.Utc);

    /// <summary>A stored UTC time as school-local time of day.</summary>
    public static TimeOnly LocalTimeOf(DateTime utc) =>
        TimeOnly.FromDateTime(DateTime.SpecifyKind(utc, DateTimeKind.Utc) + SchoolClock.Offset);

    public static TimeOnly Parse(string? s, TimeOnly fallback) =>
        TimeOnly.TryParseExact(s?.Trim(), "HH:mm", CultureInfo.InvariantCulture, DateTimeStyles.None, out var t) ? t : fallback;

    public static bool IsValid(string? s) =>
        TimeOnly.TryParseExact(s?.Trim(), "HH:mm", CultureInfo.InvariantCulture, DateTimeStyles.None, out _);

    /// <summary>
    /// The timings for the apps. <c>halfDayEnd</c> etc. are the hours in force (from the price list
    /// when there is one); <c>settings</c> holds the Company Settings values the admin edits.
    /// </summary>
    public object ToDto() => new
    {
        start = Fmt(Start), lateAfter = Fmt(LateAfter), absentAfter = Fmt(AbsentAfter),
        halfDayEnd = Fmt(EndFor(Student.HalfDay)), fullDayEnd = Fmt(EndFor(Student.FullDay)), daycareEnd = Fmt(EndFor(Student.Daycare)),
        autoCheckOutAt = Fmt(AutoCheckOutAt), auto = Auto,
        priceList = PriceList,
        sessions = Sessions.Select(s => new { sessionType = s.Key, start = Fmt(s.Value.Start), end = Fmt(s.Value.End) })
    };

    private static string Fmt(TimeOnly t) => t.ToString("HH:mm", CultureInfo.InvariantCulture);
}
