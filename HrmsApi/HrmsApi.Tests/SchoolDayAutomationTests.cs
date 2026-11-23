using FluentAssertions;
using HrmsApi.Data;
using HrmsApi.Hubs;
using HrmsApi.Models;
using HrmsApi.Services;
using Microsoft.EntityFrameworkCore;

namespace HrmsApi.Tests;

/// <summary>
/// The school day's automatic steps (Monday 23 Nov 2026, school time = UTC+8):
///   9:00 parents of children not in are asked · 9:30 still not in = absent · 7pm not checked out = automatic check-out.
///   Ali — no news; Sara — mother reported absent; Bala — checked in 8:10, never checked out (half day).
/// </summary>
public class SchoolDayAutomationTests
{
    private const int MumUser = 2, AdminUser = 1, Ali = 1, Sara = 2, Bala = 3;
    private static readonly DateTime Monday = new(2026, 11, 23);

    /// <summary>A school-local time on Monday, as UTC.</summary>
    private static DateTime At(int h, int m) => SchoolTimes.ToUtc(Monday, new TimeOnly(h, m));

    private static HrmsDbContext Setup(bool school = true, bool auto = true)
    {
        var db = new HrmsDbContext(new DbContextOptionsBuilder<HrmsDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString()).Options);
        db.Users.AddRange(
            new User { Id = AdminUser, Username = "admin", Email = "a@school.test", Role = "Admin", IsActive = true },
            new User { Id = MumUser, Username = "mum", Email = "m@home.test", Role = SchoolViewer.ParentRole, IsActive = true });
        db.Students.AddRange(
            new Student { Id = Ali, FullName = "Ali", SessionType = Student.FullDay },
            new Student { Id = Sara, FullName = "Sara", SessionType = Student.FullDay },
            new Student { Id = Bala, FullName = "Bala", SessionType = Student.HalfDay });
        db.Parents.Add(new Parent { Id = 1, FullName = "Mum", Relationship = "Mother", UserId = MumUser });
        db.StudentParents.AddRange(
            new StudentParent { StudentId = Ali, ParentId = 1 }, new StudentParent { StudentId = Sara, ParentId = 1 });
        db.ParentNotes.Add(new ParentNote { StudentId = Sara, Kind = ParentNote.Absence, FromDate = Monday, ToDate = Monday,
            Message = "Fever", CreatedByUserId = MumUser, CreatedByName = "Mum" });
        db.StudentAttendance.Add(new StudentAttendance { StudentId = Bala, Date = Monday, Status = StudentAttendance.Present,
            CheckInAt = At(8, 10), CheckInBy = "Ms Tan" });
        db.CompanySettings.Add(new CompanySettings { Id = 1, LegalName = "Golden", SchoolFeaturesEnabled = school, SchoolAutoAttendance = auto });
        db.SaveChanges();
        return db;
    }

    private static Task Run(HrmsDbContext db, DateTime utc) => SchoolDayAutomation.RunAsync(db, new NoPush(), new Live(), utc);

    [Fact]
    public async Task At_9_parents_of_children_not_in_are_asked_once()
    {
        var db = Setup();
        await Run(db, At(8, 55));
        db.Notifications.Should().BeEmpty("too early");

        await Run(db, At(9, 2));
        db.Notifications.Where(n => n.UserId == MumUser).Select(n => n.Title).Should().Equal("Ali hasn't arrived yet");
        await Run(db, At(9, 10));
        db.Notifications.Count().Should().Be(1, "once a day");
    }

    [Fact]
    public async Task At_930_children_not_in_are_absent_with_the_parents_note_as_reason()
    {
        var db = Setup();
        await Run(db, At(9, 31));
        var ali = db.StudentAttendance.Single(a => a.StudentId == Ali);
        ali.Status.Should().Be(StudentAttendance.Absent);
        ali.AutoAbsent.Should().BeTrue();
        ali.AbsenceReason.Should().Contain("09:30");
        db.StudentAttendance.Single(a => a.StudentId == Sara).AbsenceReason.Should().Be("Reported by parent: Fever");
        db.StudentAttendance.Single(a => a.StudentId == Bala).Status.Should().Be(StudentAttendance.Present);
        db.Notifications.Should().ContainSingle(n => n.Title == "Ali was marked absent today", "Sara's mother already told the school");
    }

    [Fact]
    public async Task At_7pm_children_not_checked_out_go_home_automatically_at_their_session_end()
    {
        var db = Setup();
        await Run(db, At(19, 1));
        var bala = db.StudentAttendance.Single(a => a.StudentId == Bala);
        bala.AutoCheckOut.Should().BeTrue();
        bala.CheckOutBy.Should().Be(SchoolDayAutomation.AutoBy);
        SchoolClock.LocalTime(bala.CheckOutAt!.Value).Should().Be("12:30", "half day ends at 12:30");
        db.Notifications.Should().Contain(n => n.UserId == AdminUser && n.Title == "Children checked out automatically");
    }

    [Fact]
    public async Task No_one_is_marked_absent_after_the_fact_or_on_a_day_nobody_takes_attendance()
    {
        // Server updated at 4pm: the 9:30 step is skipped for today, not run late
        var late = Setup();
        await Run(late, At(16, 0));
        late.StudentAttendance.Count(a => a.Status == StudentAttendance.Absent).Should().Be(0);
        late.Notifications.Should().BeEmpty();
        await Run(late, At(16, 5));
        late.StudentAttendance.Count(a => a.Status == StudentAttendance.Absent).Should().Be(0, "today is done");

        // Nobody checked in (attendance not taken today): no reminders, no absences
        var unused = Setup();
        unused.StudentAttendance.RemoveRange(unused.StudentAttendance);
        unused.SaveChanges();
        await Run(unused, At(9, 5));
        await Run(unused, At(9, 35));
        unused.StudentAttendance.Should().BeEmpty();
        unused.Notifications.Should().BeEmpty();
    }

    [Fact]
    public async Task Nothing_happens_on_weekends_holidays_or_when_switched_off()
    {
        var saturday = Setup();
        await SchoolDayAutomation.RunAsync(saturday, new NoPush(), new Live(), SchoolTimes.ToUtc(Monday.AddDays(5), new TimeOnly(9, 40)));
        saturday.StudentAttendance.Count().Should().Be(1);

        var holiday = Setup();
        holiday.PublicHolidays.Add(new PublicHoliday { Name = "Holiday", Date = Monday, Year = 2026 });
        holiday.SaveChanges();
        await Run(holiday, At(9, 40));
        holiday.StudentAttendance.Count().Should().Be(1);

        var off = Setup(auto: false);
        await Run(off, At(9, 40));
        off.StudentAttendance.Count().Should().Be(1);
    }

    [Fact]
    public void Late_and_session_end_times()
    {
        var t = SchoolTimes.Default;
        (SchoolTimes.LocalTimeOf(At(9, 1)) > t.LateAfter).Should().BeTrue();
        (SchoolTimes.LocalTimeOf(At(8, 59)) > t.LateAfter).Should().BeFalse();
        t.EndFor(Student.Daycare).Should().Be(new TimeOnly(18, 30));
        t.EndFor(Student.FullDay).Should().Be(new TimeOnly(16, 30));
    }

    private sealed class Live : IChatNotifier
    {
        public Task SendAsync(IEnumerable<int> userIds, string eventName, object payload) => Task.CompletedTask;
    }

    private sealed class NoPush : IPushService
    {
        public bool Enabled => false;
        public Task SendToUsersAsync(HrmsDbContext db, IReadOnlyCollection<int> userIds, string title, string body, string type, string? link = null) => Task.CompletedTask;
    }
}
