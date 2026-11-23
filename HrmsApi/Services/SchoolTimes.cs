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

    /// <summary>When the child's session ends (half day, full day, daycare).</summary>
    public TimeOnly EndFor(string? sessionType) => sessionType switch
    {
        Student.HalfDay => HalfDayEnd,
        Student.Daycare => DaycareEnd,
        _ => FullDayEnd
    };

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

    public object ToDto() => new
    {
        start = Fmt(Start), lateAfter = Fmt(LateAfter), absentAfter = Fmt(AbsentAfter),
        halfDayEnd = Fmt(HalfDayEnd), fullDayEnd = Fmt(FullDayEnd), daycareEnd = Fmt(DaycareEnd),
        autoCheckOutAt = Fmt(AutoCheckOutAt), auto = Auto
    };

    private static string Fmt(TimeOnly t) => t.ToString("HH:mm", CultureInfo.InvariantCulture);
}
