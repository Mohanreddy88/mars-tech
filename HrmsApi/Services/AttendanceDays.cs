using HrmsApi.Data;
using Microsoft.EntityFrameworkCore;

namespace HrmsApi.Services;

/// <summary>One day of approved attendance, as reports show it.</summary>
public record AttendanceDayRecord(
    int      Id,
    DateTime Date,
    int      EmployeeId,
    string   EmployeeName,
    string   DepartmentName,
    string   Status,        // Present, HalfDay, Absent, Leave (+ Weekend, Holiday when asked for)
    decimal  WorkHours,
    string?  LeaveCode,     // AL, ML, … on leave days
    string?  Remarks);

/// <summary>
/// Attendance for reports, read from approved timesheets (AttendancePeriods / AttendancePeriodDays) —
/// the attendance employees submit and HR approves. (The older Attendances table is no longer filled.)
/// Each day: a leave code → Leave; 8+ hours → Present; some hours → HalfDay; no hours on a working
/// day → Absent. Weekends and public holidays without hours are not working days: they are left out,
/// or — with <c>includeNonWorkingDays</c> (the Attendance Report) — listed as "Weekend" / "Holiday".
/// </summary>
public static class AttendanceDays
{
    public const decimal FullDayHours = 8m;

    /// <summary>Statuses that are not working days (never counted as present/absent).</summary>
    public static bool IsNonWorking(string status) => status is "Weekend" or "Holiday";

    public static async Task<List<AttendanceDayRecord>> ApprovedAsync(
        HrmsDbContext db, DateTime startDate, DateTime endDate, int? employeeId = null,
        bool includeNonWorkingDays = false)
    {
        var start = startDate.Date;
        var end   = endDate.Date;

        var rows = await db.AttendancePeriodDays
            .Where(d => d.AttendancePeriod.Status == "Approved"
                     && d.Date.Date >= start && d.Date.Date <= end
                     && (employeeId == null || d.AttendancePeriod.EmployeeId == employeeId))
            .Select(d => new
            {
                d.Id, d.Date, d.Hours, d.Note, d.Remarks, d.IsWeekend, d.IsPublicHoliday,
                d.AttendancePeriod.EmployeeId,
                EmployeeName   = d.AttendancePeriod.Employee.Name,
                DepartmentName = d.AttendancePeriod.Employee.Department != null
                                 ? d.AttendancePeriod.Employee.Department.Name : "Unassigned",
            })
            .ToListAsync();

        var result = new List<AttendanceDayRecord>(rows.Count);
        foreach (var d in rows)
        {
            var leave   = string.IsNullOrWhiteSpace(d.Note) ? null : d.Note.Trim();
            var weekend = d.IsWeekend || d.Date.DayOfWeek is DayOfWeek.Saturday or DayOfWeek.Sunday;

            string status;
            if (leave != null)                      status = "Leave";
            else if (d.Hours >= FullDayHours)       status = "Present";
            else if (d.Hours > 0)                   status = "HalfDay";
            else if (weekend || d.IsPublicHoliday)                       // not a working day
            {
                if (!includeNonWorkingDays) continue;
                status = d.IsPublicHoliday ? "Holiday" : "Weekend";
            }
            else                                    status = "Absent";

            result.Add(new AttendanceDayRecord(d.Id, d.Date.Date, d.EmployeeId, d.EmployeeName, d.DepartmentName,
                                               status, leave != null ? 0 : d.Hours, leave, d.Remarks));
        }

        return result.OrderBy(r => r.Date).ThenBy(r => r.EmployeeName).ToList();
    }
}
