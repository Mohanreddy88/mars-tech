using FluentAssertions;
using HrmsApi.Data;
using HrmsApi.Models;
using HrmsApi.Services;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;

namespace HrmsApi.Tests;

/// <summary>
/// One record per leave day: leave typed on a timesheet and leave requested by the employee
/// must never be deducted twice, whichever comes first.
/// November 2026: 2nd = Monday, 6th = Friday, 9th = Monday.
/// </summary>
public class LeaveTimesheetOverlapTests
{
    private sealed class NoHolidays : ITimesheetService
    {
        public Task<Timesheet> GenerateTimesheetAsync(int employeeId, int month, int year) => throw new NotSupportedException();
        public Task<(List<Timesheet> Generated, int Skipped, List<string> Errors)> GenerateTimesheetsForAllEmployeesAsync(int month, int year) => throw new NotSupportedException();
        public Task<int> GetWorkingDaysInMonthAsync(int month, int year, string? state = null) => Task.FromResult(22);
        public Task<List<DateTime>> GetPublicHolidaysInMonthAsync(int month, int year, string? state = null) => Task.FromResult(new List<DateTime>());
    }

    private static DateTime D(int day) => new(2026, 11, day, 0, 0, 0, DateTimeKind.Utc);

    private static (HrmsDbContext db, LeaveService svc) Setup()
    {
        var db = new HrmsDbContext(new DbContextOptionsBuilder<HrmsDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString()).Options);
        db.Employees.Add(new Employee { Id = 1, Name = "Mounika", EmployeeCode = "EMP000002", Email = "m@test.com",
                                        Salary = 5000, JoinDate = new DateTime(2020, 1, 1), Gender = "Female" });
        db.LeaveTypes.Add(new LeaveType { Id = 1, Name = "Annual Leave", Code = "AL", DefaultDaysPerYear = 14 });
        db.LeaveTypes.Add(new LeaveType { Id = 2, Name = "Medical Leave", Code = "ML", DefaultDaysPerYear = 14 });
        db.EmployeeLeaveBalances.Add(new EmployeeLeaveBalance { EmployeeId = 1, LeaveTypeId = 1, Year = 2026, TotalDays = 14, BalanceDays = 14 });
        db.EmployeeLeaveBalances.Add(new EmployeeLeaveBalance { EmployeeId = 1, LeaveTypeId = 2, Year = 2026, TotalDays = 14, BalanceDays = 14 });
        db.SaveChanges();
        return (db, new LeaveService(db, new NoHolidays(), NullLogger<LeaveService>.Instance));
    }

    private static AttendancePeriod AddTimesheet(HrmsDbContext db, string status, params (int Day, string? Code)[] days)
    {
        var period = new AttendancePeriod
        {
            EmployeeId = 1, StartDate = D(1), EndDate = D(15), Status = status,
            Days = days.Select(d => new AttendancePeriodDay { Date = D(d.Day), Note = d.Code, Hours = d.Code == null ? 8 : 0 }).ToList()
        };
        db.AttendancePeriods.Add(period);
        db.SaveChanges();
        return period;
    }

    private static decimal Used(HrmsDbContext db, int leaveTypeId) =>
        db.EmployeeLeaveBalances.Single(b => b.EmployeeId == 1 && b.LeaveTypeId == leaveTypeId && b.Year == 2026).UsedDays;

    private static LeaveRequestCreate Request(int typeId, int from, int to) =>
        new() { EmployeeId = 1, LeaveTypeId = typeId, StartDate = D(from), EndDate = D(to), Reason = "Family matters" };

    [Fact]
    public async Task TimesheetFirst_RecordsApprovedLeave_AndEmployeeCannotApplyAgain()
    {
        var (db, svc) = Setup();
        var period = AddTimesheet(db, "Submitted", (3, "AL"), (4, "AL"), (5, null));

        var created = await svc.RecordTimesheetLeaveAsync(period, approvedByUserId: 99);

        created.Should().ContainSingle();
        created[0].Status.Should().Be("Approved");
        created[0].StartDate.Should().Be(D(3));
        created[0].EndDate.Should().Be(D(4));
        created[0].TotalDays.Should().Be(2);
        created[0].Reason.Should().StartWith(LeaveService.TimesheetLeaveReason);
        Used(db, 1).Should().Be(2);

        // The employee later applies for the same days: refused, nothing deducted again
        var act = () => svc.CreateLeaveRequestAsync(Request(1, 3, 4));
        (await act.Should().ThrowAsync<InvalidOperationException>()).WithMessage("*already approved (recorded from the timesheet)*");
        Used(db, 1).Should().Be(2);
        db.LeaveRequests.Count().Should().Be(1);
    }

    [Fact]
    public async Task ApprovedRequestFirst_TimesheetDoesNotDeductAgain()
    {
        var (db, svc) = Setup();
        var lr = await svc.CreateLeaveRequestAsync(Request(1, 3, 4));
        await svc.ApproveLeaveRequestAsync(lr.Id, 99, "ok");
        Used(db, 1).Should().Be(2);

        var period = AddTimesheet(db, "Submitted", (3, "AL"), (4, "AL"));
        var created = await svc.RecordTimesheetLeaveAsync(period, 99);

        created.Should().BeEmpty();
        Used(db, 1).Should().Be(2);
    }

    [Fact]
    public async Task PendingRequest_IsLeftForHrToApprove_AndDeductedOnlyThen()
    {
        var (db, svc) = Setup();
        var lr = await svc.CreateLeaveRequestAsync(Request(1, 3, 4));

        var period = AddTimesheet(db, "Submitted", (3, "AL"), (4, "AL"));
        var created = await svc.RecordTimesheetLeaveAsync(period, 99);

        created.Should().BeEmpty();
        Used(db, 1).Should().Be(0);

        await svc.ApproveLeaveRequestAsync(lr.Id, 99, "ok");
        Used(db, 1).Should().Be(2);
    }

    [Fact]
    public async Task PartlyOverlappingRequest_IsRefused()
    {
        var (db, svc) = Setup();
        var lr = await svc.CreateLeaveRequestAsync(Request(1, 3, 4));
        await svc.ApproveLeaveRequestAsync(lr.Id, 99, "ok");

        var act = () => svc.CreateLeaveRequestAsync(Request(1, 4, 6));
        (await act.Should().ThrowAsync<InvalidOperationException>()).WithMessage("*already approved*");
    }

    [Fact]
    public async Task ConsecutiveDaysAcrossAWeekend_BecomeOneRequest_PerLeaveType()
    {
        var (db, svc) = Setup();
        var period = AddTimesheet(db, "Submitted", (6, "AL"), (9, "AL"), (10, "ML"), (12, "AL"));

        var created = await svc.RecordTimesheetLeaveAsync(period, 99);

        created.Select(c => (c.StartDate.Day, c.EndDate.Day, c.TotalDays, c.LeaveTypeId))
               .Should().Equal((6, 9, 2m, 1), (10, 10, 1m, 2), (12, 12, 1m, 1));
        Used(db, 1).Should().Be(3);
        Used(db, 2).Should().Be(1);
    }

    [Fact]
    public async Task DayDeductedByAnOlderApprovedTimesheet_CannotBeRequested()
    {
        // Timesheets approved before this change deducted leave without creating a leave request
        var (db, svc) = Setup();
        AddTimesheet(db, "Approved", (3, "AL"));

        var act = () => svc.CreateLeaveRequestAsync(Request(1, 3, 3));
        (await act.Should().ThrowAsync<InvalidOperationException>()).WithMessage("*approved timesheet*");
    }

    [Fact]
    public async Task ResubmittingTheSamePendingDates_StillUpdatesTheRequest()
    {
        var (db, svc) = Setup();
        var first = await svc.CreateLeaveRequestAsync(Request(1, 3, 4));

        var again = await svc.CreateLeaveRequestAsync(new LeaveRequestCreate
            { EmployeeId = 1, LeaveTypeId = 1, StartDate = D(3), EndDate = D(4), Reason = "Changed reason" });

        again.Id.Should().Be(first.Id);
        db.LeaveRequests.Count().Should().Be(1);
    }
}
