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
    string   Status,        // Present, HalfDay, Absent, Leave
    decimal  WorkHours,
    string?  LeaveCode,     // AL, ML, … on leave days
    string?  Remarks);

/// <summary>
/// Attendance for reports, read from approved timesheets (AttendancePeriods / AttendancePeriodDays) —
/// the attendance employees submit and HR approves. (The older Attendances table is no longer filled.)
/// Each day: a leave code → Leave; 8+ hours → Present; some hours → HalfDay; no hours on a working
/// day → Absent. Weekends and public holidays without hours are not working days and are left out.
/// </summary>
public static class AttendanceDays
{
    public const decimal FullDayHours = 8m;

    public static async Task<List<AttendanceDayRecord>> ApprovedAsync(
        HrmsDbContext db, DateTime startDate, DateTime endDate, int? employeeId = null)
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
            else if (weekend || d.IsPublicHoliday)  continue;            // not a working day
            else                                    status = "Absent";

            result.Add(new AttendanceDayRecord(d.Id, d.Date.Date, d.EmployeeId, d.EmployeeName, d.DepartmentName,
                                               status, leave != null ? 0 : d.Hours, leave, d.Remarks));
        }

        return result.OrderBy(r => r.Date).ThenBy(r => r.EmployeeName).ToList();
    }
}
