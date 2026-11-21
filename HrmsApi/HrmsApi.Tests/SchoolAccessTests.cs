using System.Security.Claims;
using FluentAssertions;
using HrmsApi.Controllers;
using HrmsApi.Data;
using HrmsApi.Hubs;
using HrmsApi.Models;
using HrmsApi.Services;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace HrmsApi.Tests;

/// <summary>
/// School features: who may see which child and which message thread.
///   Class N2 (teacher: Tan) — child Ali, parents Mum (login) and Dad (no login).
///   Class K1 (teacher: Lee) — child Bala.
/// </summary>
public class SchoolAccessTests
{
    private const int AdminUser = 1, TanUser = 2, LeeUser = 3, MumUser = 4, ClerkUser = 5;
    private const int N2 = 1, K1 = 2, Ali = 1, Bala = 2;

    private static HrmsDbContext Setup()
    {
        var db = new HrmsDbContext(new DbContextOptionsBuilder<HrmsDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString()).Options);

        db.Users.AddRange(
            new User { Id = AdminUser, Username = "admin", Email = "admin@school.test", Role = "Admin" },
            new User { Id = TanUser,   Username = "tan",   Email = "tan@school.test",   Role = "Employee" },
            new User { Id = LeeUser,   Username = "lee",   Email = "lee@school.test",   Role = "Employee" },
            new User { Id = MumUser,   Username = "mum",   Email = "mum@home.test",     Role = SchoolViewer.ParentRole },
            new User { Id = ClerkUser, Username = "clerk", Email = "clerk@school.test", Role = "Employee" });
        db.Employees.AddRange(
            new Employee { Id = 10, Name = "Ms Tan",  EmployeeCode = "E1", Email = "tan@school.test",   Salary = 3000, JoinDate = new DateTime(2020, 1, 1), Gender = "Female" },
            new Employee { Id = 11, Name = "Ms Lee",  EmployeeCode = "E2", Email = "lee@school.test",   Salary = 3000, JoinDate = new DateTime(2020, 1, 1), Gender = "Female" },
            new Employee { Id = 12, Name = "Clerk",   EmployeeCode = "E3", Email = "clerk@school.test", Salary = 2500, JoinDate = new DateTime(2020, 1, 1), Gender = "Male" });
        db.SchoolClasses.AddRange(
            new SchoolClass { Id = N2, Name = "N2", ClassTeacherId = 10 },
            new SchoolClass { Id = K1, Name = "K1", ClassTeacherId = 11 });
        db.Students.AddRange(
            new Student { Id = Ali,  FullName = "Ali",  ClassId = N2 },
            new Student { Id = Bala, FullName = "Bala", ClassId = K1 });
        db.Parents.AddRange(
            new Parent { Id = 1, FullName = "Mum", Relationship = "Mother", Email = "mum@home.test", UserId = MumUser },
            new Parent { Id = 2, FullName = "Dad", Relationship = "Father" });
        db.StudentParents.AddRange(
            new StudentParent { StudentId = Ali, ParentId = 1 },
            new StudentParent { StudentId = Ali, ParentId = 2 });
        db.CompanySettings.Add(new CompanySettings { Id = 1, LegalName = "Golden", SchoolFeaturesEnabled = true });
        db.SaveChanges();
        return db;
    }

    private static ClaimsPrincipal As(int userId, string role) =>
        new(new ClaimsIdentity(new[] { new Claim(ClaimTypes.NameIdentifier, userId.ToString()), new Claim(ClaimTypes.Role, role) }, "test"));

    [Fact]
    public async Task ClassTeacher_SeesOwnClassTeacherThreadsOnly()
    {
        var db = Setup();
        var tan = await SchoolViewer.LoadAsync(db, As(TanUser, "Employee"));

        tan!.IsTeacher.Should().BeTrue();
        tan.IsAdmin.Should().BeFalse();
        tan.TeacherClassIds.Should().Equal(N2);
        tan.CanAccessConversation(Conversation.Teacher, Ali, N2).Should().BeTrue();
        tan.CanAccessConversation(Conversation.Office, Ali, N2).Should().BeFalse("office threads are for the admins");
        tan.CanAccessConversation(Conversation.Teacher, Bala, K1).Should().BeFalse("another teacher's class");
        tan.CanSeeStudent(Bala, K1).Should().BeFalse();
    }

    [Fact]
    public async Task EmployeeWithoutClass_IsNotStaff()
    {
        var db = Setup();
        var clerk = await SchoolViewer.LoadAsync(db, As(ClerkUser, "Employee"));
        clerk!.IsStaff.Should().BeFalse();
        clerk.CanAccessConversation(Conversation.Teacher, Ali, N2).Should().BeFalse();
    }

    [Fact]
    public async Task Parent_SeesOwnChildrenOnly_AndLosesAccessWhenDeactivated()
    {
        var db = Setup();
        var mum = await SchoolViewer.LoadAsync(db, As(MumUser, SchoolViewer.ParentRole));
        mum!.IsParent.Should().BeTrue();
        mum.ChildIds.Should().Equal(Ali);
        mum.CanAccessConversation(Conversation.Office, Ali, N2).Should().BeTrue();
        mum.CanAccessConversation(Conversation.Teacher, Bala, K1).Should().BeFalse();

        // Child leaves the school: no longer listed
        db.Students.Find(Ali)!.IsActive = false;
        db.SaveChanges();
        (await SchoolViewer.LoadAsync(db, As(MumUser, SchoolViewer.ParentRole)))!.ChildIds.Should().BeEmpty();

        // Parent record switched off: not a parent any more
        db.Students.Find(Ali)!.IsActive = true;
        db.Parents.Find(1)!.IsActive = false;
        db.SaveChanges();
        var off = await SchoolViewer.LoadAsync(db, As(MumUser, SchoolViewer.ParentRole));
        off!.IsParent.Should().BeFalse();
        off.CanAccessConversation(Conversation.Office, Ali, N2).Should().BeFalse();
    }

    [Fact]
    public async Task DisabledLogin_GetsNothing()
    {
        var db = Setup();
        db.Users.Find(TanUser)!.IsActive = false;
        db.SaveChanges();
        (await SchoolViewer.LoadAsync(db, As(TanUser, "Employee"))).Should().BeNull();
    }

    [Fact]
    public async Task Participants_AdminsPlusClassTeacher_ParentsWithLoginOnly()
    {
        var db = Setup();
        (await SchoolParticipants.StaffUserIdsAsync(db, Conversation.Teacher, N2)).Should().BeEquivalentTo(new[] { AdminUser, TanUser });
        (await SchoolParticipants.StaffUserIdsAsync(db, Conversation.Office, N2)).Should().BeEquivalentTo(new[] { AdminUser });
        (await SchoolParticipants.ParentUserIdsAsync(db, Ali)).Should().BeEquivalentTo(new[] { MumUser }, "Dad has no login");
    }

    // ── Messages controller ──

    private sealed class NoLive : IChatNotifier
    {
        public List<(List<int> users, string ev)> Sent { get; } = new();
        public Task SendAsync(IEnumerable<int> userIds, string eventName, object payload)
        {
            Sent.Add((userIds.ToList(), eventName));
            return Task.CompletedTask;
        }
    }

    private sealed class NoPush : IPushService
    {
        public bool Enabled => false;
        public Task SendToUsersAsync(HrmsDbContext db, IReadOnlyCollection<int> userIds, string title, string body, string type, string? link = null) => Task.CompletedTask;
    }

    private static (MessagesController ctl, NoLive live) Controller(HrmsDbContext db, int userId, string role)
    {
        var live = new NoLive();
        var ctl = new MessagesController(db, live, new NoPush())
        {
            ControllerContext = new ControllerContext { HttpContext = new DefaultHttpContext { User = As(userId, role) } }
        };
        return (ctl, live);
    }

    [Fact]
    public async Task TeacherReply_ReachesParentsAndAdmins_AndIsSignedAsTeacher()
    {
        var db = Setup();
        db.Conversations.Add(new Conversation { Id = 1, StudentId = Ali, Kind = Conversation.Teacher });
        db.SaveChanges();

        var (ctl, live) = Controller(db, TanUser, "Employee");
        var result = await ctl.Send(1, new SendMessageForm { Body = "Ali did well today" });

        var msg = (result as OkObjectResult)!.Value as MessageDto;
        msg!.SenderRole.Should().Be(Conversation.Teacher);
        msg.SenderName.Should().Be("Ms Tan");
        live.Sent.Should().ContainSingle(s => s.ev == "message");
        live.Sent[0].users.Should().BeEquivalentTo(new[] { MumUser, AdminUser, TanUser });
    }

    [Fact]
    public async Task Teacher_CannotOpenOfficeThread_OrAnotherClass()
    {
        var db = Setup();
        var (ctl, _) = Controller(db, TanUser, "Employee");

        (await ctl.Open(new OpenConversationRequest { StudentId = Ali, Kind = Conversation.Office })).Should().BeOfType<ForbidResult>();
        (await ctl.Open(new OpenConversationRequest { StudentId = Bala, Kind = Conversation.Teacher })).Should().BeOfType<ForbidResult>();
        (await ctl.Open(new OpenConversationRequest { StudentId = Ali, Kind = Conversation.Teacher })).Should().BeOfType<OkObjectResult>();
    }

    [Fact]
    public async Task EmptyMessage_IsRefused()
    {
        var db = Setup();
        db.Conversations.Add(new Conversation { Id = 1, StudentId = Ali, Kind = Conversation.Office });
        db.SaveChanges();
        var (ctl, _) = Controller(db, MumUser, SchoolViewer.ParentRole);
        (await ctl.Send(1, new SendMessageForm { Body = "   " })).Should().BeOfType<BadRequestObjectResult>();
    }
}
