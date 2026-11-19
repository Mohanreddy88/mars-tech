using FluentAssertions;
using HrmsApi.Data;
using HrmsApi.Models;
using HrmsApi.Services;
using Microsoft.EntityFrameworkCore;

namespace HrmsApi.Tests;

/// <summary>Reports read attendance from approved timesheets. November 2026: 6th = Friday, 7th = Saturday.</summary>
public class AttendanceDaysTests
{
    private static DateTime D(int day) => new(2026, 11, day);

    [Fact]
    public async Task ClassifiesApprovedTimesheetDays_AndIgnoresUnapprovedOnes()
    {
        var db = new HrmsDbContext(new DbContextOptionsBuilder<HrmsDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString()).Options);
        db.Employees.Add(new Employee { Id = 1, Name = "Mounika", EmployeeCode = "E2", Email = "m@t.com" });
        db.AttendancePeriods.Add(new AttendancePeriod
        {
            EmployeeId = 1, StartDate = D(1), EndDate = D(15), Status = "Approved",
            Days = new List<AttendancePeriodDay>
            {
                new() { Date = D(2), Hours = 8 },                                // Present
                new() { Date = D(3), Hours = 4 },                                // Half day
                new() { Date = D(4), Hours = 0, Note = "AL", Remarks = "Family" },// Leave
                new() { Date = D(5), Hours = 0 },                                // Absent (working day)
                new() { Date = D(7), Hours = 0, IsWeekend = true },              // Saturday: not a working day
            }
        });
        db.AttendancePeriods.Add(new AttendancePeriod
        {
            EmployeeId = 1, StartDate = D(16), EndDate = D(30), Status = "Submitted",
            Days = new List<AttendancePeriodDay> { new() { Date = D(16), Hours = 8 } }
        });
        await db.SaveChangesAsync();

        var days = await AttendanceDays.ApprovedAsync(db, D(1), D(30));

        days.Select(d => (d.Date.Day, d.Status)).Should().Equal(
            (2, "Present"), (3, "HalfDay"), (4, "Leave"), (5, "Absent"));
        days.Single(d => d.Status == "Leave").LeaveCode.Should().Be("AL");
        days.Should().OnlyContain(d => d.EmployeeName == "Mounika" && d.DepartmentName == "Unassigned");
    }

    [Fact]
    public async Task IncludeNonWorkingDays_ListsWeekendsAndHolidays_ButWorkedWeekendStaysPresent()
    {
        var db = new HrmsDbContext(new DbContextOptionsBuilder<HrmsDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString()).Options);
        db.Employees.Add(new Employee { Id = 1, Name = "Mounika", EmployeeCode = "E2", Email = "m@t.com" });
        db.AttendancePeriods.Add(new AttendancePeriod
        {
            EmployeeId = 1, StartDate = D(1), EndDate = D(15), Status = "Approved",
            Days = new List<AttendancePeriodDay>
            {
                new() { Date = D(6), Hours = 8 },                                // Friday: Present
                new() { Date = D(7), Hours = 0, IsWeekend = true },              // Saturday off
                new() { Date = D(8), Hours = 8, IsWeekend = true },              // Sunday worked
                new() { Date = D(9), Hours = 0, IsPublicHoliday = true },        // Public holiday
            }
        });
        await db.SaveChangesAsync();

        var withAll = await AttendanceDays.ApprovedAsync(db, D(1), D(30), includeNonWorkingDays: true);
        withAll.Select(d => (d.Date.Day, d.Status)).Should().Equal(
            (6, "Present"), (7, "Weekend"), (8, "Present"), (9, "Holiday"));

        var workingOnly = await AttendanceDays.ApprovedAsync(db, D(1), D(30));
        workingOnly.Select(d => d.Date.Day).Should().Equal(6, 8);
    }
}
