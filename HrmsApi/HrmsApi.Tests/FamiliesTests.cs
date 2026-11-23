using System.Security.Claims;
using System.Text.Json;
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
/// Families (School → Families): one screen sets a child's mother and father; half-siblings are
/// two families sharing a parent.
///   Rudvik — mother Mounika, father Mohan (by mistake also linked to Narsi, father of his half-brother Arjun).
///   Arjun  — mother Mounika, father Narsi.
/// </summary>
public class FamiliesTests
{
    private const int Rudvik = 1, Arjun = 2, Mounika = 1, Mohan = 2, Narsi = 3, Gran = 4;

    private static HrmsDbContext Setup()
    {
        var db = new HrmsDbContext(new DbContextOptionsBuilder<HrmsDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString()).Options);
        db.Students.AddRange(
            new Student { Id = Rudvik, FullName = "Rudvik Reddy" },
            new Student { Id = Arjun,  FullName = "Arjun" });
        db.Parents.AddRange(
            new Parent { Id = Mounika, FullName = "Mounika", Relationship = "Mother" },
            new Parent { Id = Mohan,   FullName = "Mohan",   Relationship = "Father" },
            new Parent { Id = Narsi,   FullName = "Narsi",   Relationship = "Father" },
            new Parent { Id = Gran,    FullName = "Gran",    Relationship = "Guardian" });
        db.StudentParents.AddRange(
            new StudentParent { StudentId = Rudvik, ParentId = Mounika },
            new StudentParent { StudentId = Rudvik, ParentId = Narsi },   // the mistake
            new StudentParent { StudentId = Rudvik, ParentId = Gran },
            new StudentParent { StudentId = Arjun,  ParentId = Mounika },
            new StudentParent { StudentId = Arjun,  ParentId = Narsi });
        db.Users.Add(new User { Id = 1, Username = "admin", Email = "admin@school.test", Role = "Admin", IsActive = true });
        db.CompanySettings.Add(new CompanySettings { Id = 1, LegalName = "Montessori", SchoolFeaturesEnabled = true });
        db.SaveChanges();
        return db;
    }

    private static ControllerContext AdminContext() => new()
    {
        HttpContext = new DefaultHttpContext
        {
            User = new ClaimsPrincipal(new ClaimsIdentity(new[]
                { new Claim(ClaimTypes.NameIdentifier, "1"), new Claim(ClaimTypes.Role, "Admin") }, "test"))
        }
    };

    private static FamiliesController Families(HrmsDbContext db) => new(db, new NoAudit()) { ControllerContext = AdminContext() };

    private static HashSet<int> ParentsOf(HrmsDbContext db, int child) =>
        db.StudentParents.Where(sp => sp.StudentId == child).Select(sp => sp.ParentId).ToHashSet();

    private static string? Message(IActionResult r) =>
        (r as BadRequestObjectResult)?.Value?.GetType().GetProperty("message")?.GetValue(((BadRequestObjectResult)r).Value) as string;

    [Fact]
    public async Task Saving_a_family_replaces_the_wrong_father_and_keeps_the_mother_and_guardian()
    {
        var db = Setup();
        (await Families(db).Save(new FamilyRequest { MotherId = Mounika, FatherId = Mohan, StudentIds = new() { Rudvik } }))
            .Should().BeOfType<OkObjectResult>();

        ParentsOf(db, Rudvik).Should().BeEquivalentTo(new[] { Mounika, Mohan, Gran });
        ParentsOf(db, Arjun).Should().BeEquivalentTo(new[] { Mounika, Narsi }, "the half-brother keeps his own father");
    }

    [Fact]
    public async Task Families_list_groups_children_by_mother_and_father()
    {
        var db = Setup();
        await Families(db).Save(new FamilyRequest { MotherId = Mounika, FatherId = Mohan, StudentIds = new() { Rudvik } });

        var ok = (OkObjectResult)await Families(db).GetAll();
        var json = JsonDocument.Parse(JsonSerializer.Serialize(ok.Value)).RootElement;
        json.GetArrayLength().Should().Be(2);
        var fathers = json.EnumerateArray().Select(f => f.GetProperty("father").GetProperty("FullName").GetString()).ToList();
        fathers.Should().BeEquivalentTo(new[] { "Mohan", "Narsi" });
        json.EnumerateArray().Should().OnlyContain(f => f.GetProperty("mother").GetProperty("FullName").GetString() == "Mounika");
    }

    [Fact]
    public async Task Removing_a_child_unlinks_only_this_mother_and_father()
    {
        var db = Setup();
        await Families(db).Save(new FamilyRequest { MotherId = Mounika, FatherId = Narsi, RemoveStudentIds = new() { Rudvik } });
        ParentsOf(db, Rudvik).Should().BeEquivalentTo(new[] { Gran });
        ParentsOf(db, Arjun).Should().BeEquivalentTo(new[] { Mounika, Narsi });
    }

    [Fact]
    public async Task Mother_must_be_saved_as_mother_and_a_family_needs_a_parent_and_a_child()
    {
        var db = Setup();
        Message(await Families(db).Save(new FamilyRequest { MotherId = Mohan, StudentIds = new() { Rudvik } }))
            .Should().Contain("not mother");
        Message(await Families(db).Save(new FamilyRequest { StudentIds = new() { Rudvik } }))
            .Should().Contain("Choose the mother");
        Message(await Families(db).Save(new FamilyRequest { MotherId = Mounika, StudentIds = new() }))
            .Should().Contain("at least one child");
    }

    [Fact]
    public async Task Admins_see_siblings_and_how_they_are_related()
    {
        var db = Setup();
        await Families(db).Save(new FamilyRequest { MotherId = Mounika, FatherId = Mohan, StudentIds = new() { Rudvik } });

        var school = new SchoolController(db, new Settings(db), new NoAudit()) { ControllerContext = AdminContext() };
        var dto = (StudentDto)((OkObjectResult)await school.GetStudent(Rudvik)).Value!;
        dto.Siblings.Should().ContainSingle(s => s.Id == Arjun && s.Via == "Same mother");
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
