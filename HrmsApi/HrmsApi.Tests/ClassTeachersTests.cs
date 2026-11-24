using System.Security.Claims;
using FluentAssertions;
using HrmsApi.Controllers;
using HrmsApi.Data;
using HrmsApi.Models;
using HrmsApi.Services;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace HrmsApi.Tests;

/// <summary>
/// A class with several teachers: Ms Tan leads N2 (parents see her), Ms Lee also teaches N2.
/// Both see N2's children and get its parents' messages; Mr Raj teaches K1 only.
/// </summary>
public class ClassTeachersTests
{
    private const int N2 = 1, K1 = 2, Tan = 10, Lee = 11, Raj = 12, TanUser = 2, LeeUser = 3, RajUser = 4, AdminUser = 1;

    private static HrmsDbContext Setup()
    {
        var db = new HrmsDbContext(new DbContextOptionsBuilder<HrmsDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString()).Options);
        db.Users.AddRange(
            new User { Id = AdminUser, Username = "admin", Email = "admin@school.test", Role = "Admin", IsActive = true },
            new User { Id = TanUser, Username = "tan", Email = "tan@school.test", Role = "Employee", IsActive = true },
            new User { Id = LeeUser, Username = "lee", Email = "lee@school.test", Role = "Employee", IsActive = true },
            new User { Id = RajUser, Username = "raj", Email = "raj@school.test", Role = "Employee", IsActive = true });
        Employee E(int id, string name, string email) => new()
            { Id = id, Name = name, EmployeeCode = $"E{id}", Email = email, Salary = 3000, JoinDate = new DateTime(2020, 1, 1), Gender = "Female" };
        db.Employees.AddRange(E(Tan, "Ms Tan", "tan@school.test"), E(Lee, "Ms Lee", "lee@school.test"), E(Raj, "Mr Raj", "raj@school.test"));
        db.SchoolClasses.AddRange(new SchoolClass { Id = N2, Name = "N2", ClassTeacherId = Tan }, new SchoolClass { Id = K1, Name = "K1", ClassTeacherId = Raj });
        db.CompanySettings.Add(new CompanySettings { Id = 1, LegalName = "Golden", SchoolFeaturesEnabled = true });
        db.SaveChanges();
        return db;
    }

    private static ClaimsPrincipal Login(int userId, string role) =>
        new(new ClaimsIdentity(new[] { new Claim(ClaimTypes.NameIdentifier, userId.ToString()), new Claim(ClaimTypes.Role, role) }, "test"));

    private static SchoolController Admin(HrmsDbContext db) =>
        new(db, new Settings(db), new NoAudit()) { ControllerContext = new ControllerContext { HttpContext = new DefaultHttpContext { User = Login(AdminUser, "Admin") } } };

    [Fact]
    public async Task Another_teacher_of_the_class_sees_it_and_gets_its_parents_messages()
    {
        var db = Setup();
        (await Admin(db).UpdateClass(N2, new SchoolClassRequest { Name = "N2", ClassTeacherId = Tan, TeacherIds = new() { Lee }, IsActive = true }))
            .Should().BeOfType<OkObjectResult>();

        (await SchoolViewer.LoadAsync(db, Login(LeeUser, "Employee")))!.TeacherClassIds.Should().Equal(N2);
        (await SchoolViewer.LoadAsync(db, Login(TanUser, "Employee")))!.TeacherClassIds.Should().Equal(N2);
        (await SchoolViewer.LoadAsync(db, Login(RajUser, "Employee")))!.TeacherClassIds.Should().Equal(K1);

        var n2Staff = await SchoolParticipants.StaffUserIdsAsync(db, Conversation.Teacher, N2);
        n2Staff.Should().BeEquivalentTo(new[] { AdminUser, TanUser, LeeUser });
        (await SchoolParticipants.StaffUserIdsAsync(db, Conversation.Office, N2)).Should().Equal(AdminUser);

        // Parents still see only the lead teacher
        db.SchoolClasses.Include(c => c.ClassTeacher).Single(c => c.Id == N2).ClassTeacher!.Name.Should().Be("Ms Tan");
    }

    [Fact]
    public async Task Taking_a_teacher_off_the_class_removes_their_access()
    {
        var db = Setup();
        await Admin(db).UpdateClass(N2, new SchoolClassRequest { Name = "N2", ClassTeacherId = Tan, TeacherIds = new() { Lee }, IsActive = true });
        await Admin(db).UpdateClass(N2, new SchoolClassRequest { Name = "N2", ClassTeacherId = Tan, TeacherIds = new(), IsActive = true });
        (await SchoolViewer.LoadAsync(db, Login(LeeUser, "Employee")))!.TeacherClassIds.Should().BeEmpty();
    }

    [Fact]
    public async Task Other_teachers_need_a_lead_and_the_lead_is_not_listed_twice()
    {
        var db = Setup();
        var r = await Admin(db).UpdateClass(N2, new SchoolClassRequest { Name = "N2", ClassTeacherId = null, TeacherIds = new() { Lee }, IsActive = true });
        r.Should().BeOfType<BadRequestObjectResult>();

        await Admin(db).UpdateClass(N2, new SchoolClassRequest { Name = "N2", ClassTeacherId = Tan, TeacherIds = new() { Tan, Lee }, IsActive = true });
        db.SchoolClassTeachers.Select(t => t.EmployeeId).Should().Equal(Lee);
    }

    private sealed class NoAudit : IAuditService
    {
        public Task LogAsync(string action, string entityType, string? entityId, string description, string username,
            int? userId = null, string? oldValues = null, string? newValues = null, string? ipAddress = null) => Task.CompletedTask;
    }

    private sealed class Settings(HrmsDbContext db) : ICompanySettingsService
    {
        public Task<CompanySettings> GetAsync() => db.CompanySettings.FirstAsync();
    }
}
