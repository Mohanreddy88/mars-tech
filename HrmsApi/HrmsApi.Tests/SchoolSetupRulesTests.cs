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
/// School setup rules: phone numbers (format, not shared between parents), one mother and one
/// father per child, and the "same child entered twice?" question.
///   Child Ali (born 3 Mar 2021) — Mum (Mother, 012-345 6789) and Dad (Father).
/// </summary>
public class SchoolSetupRulesTests
{
    private const int Ali = 1, Mum = 1, Dad = 2, Aunt = 3, Gran = 4;

    private static HrmsDbContext Setup()
    {
        var db = new HrmsDbContext(new DbContextOptionsBuilder<HrmsDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString()).Options);
        db.Students.Add(new Student { Id = Ali, FullName = "Ali Rahman", DateOfBirth = new DateTime(2021, 3, 3) });
        db.Parents.AddRange(
            new Parent { Id = Mum,  FullName = "Mum",  Relationship = "Mother", Phone = "012 345 6789" },  // old free text
            new Parent { Id = Dad,  FullName = "Dad",  Relationship = "Father" },
            new Parent { Id = Aunt, FullName = "Aunt", Relationship = "Mother" },
            new Parent { Id = Gran, FullName = "Gran", Relationship = "Guardian" });
        db.StudentParents.AddRange(
            new StudentParent { StudentId = Ali, ParentId = Mum },
            new StudentParent { StudentId = Ali, ParentId = Dad });
        db.CompanySettings.Add(new CompanySettings { Id = 1, LegalName = "Golden", SchoolFeaturesEnabled = true });
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

    private static ParentsController Parents(HrmsDbContext db) =>
        new(db, null!, new NoAudit()) { ControllerContext = AdminContext() };

    private static SchoolController School(HrmsDbContext db) =>
        new(db, new Settings(db), new NoAudit()) { ControllerContext = AdminContext() };

    private static string? Message(IActionResult r) =>
        (r as BadRequestObjectResult)?.Value?.GetType().GetProperty("message")?.GetValue(((BadRequestObjectResult)r).Value) as string;

    [Fact]
    public async Task Parent_phone_is_stored_as_plus60()
    {
        var db = Setup();
        var r = await Parents(db).Create(new ParentRequest { FullName = "Uncle", Relationship = "Guardian", Phone = "011-2345 6789" });
        r.Should().BeOfType<OkObjectResult>();
        db.Parents.Single(p => p.FullName == "Uncle").Phone.Should().Be("+601123456789");
    }

    [Fact]
    public async Task Parent_phone_in_wrong_format_is_refused()
    {
        var r = await Parents(Setup()).Create(new ParentRequest { FullName = "Uncle", Relationship = "Guardian", Phone = "012-345" });
        Message(r).Should().Contain("Malaysian number");
    }

    [Fact]
    public async Task Same_phone_as_another_parent_is_refused_even_typed_differently()
    {
        var r = await Parents(Setup()).Create(new ParentRequest { FullName = "Uncle", Relationship = "Guardian", Phone = "+60 12-345 6789" });
        Message(r).Should().Be("This phone number is already used by Mum.");
    }

    [Fact]
    public async Task Parent_keeps_own_phone_when_edited()
    {
        var r = await Parents(Setup()).Update(Mum, new ParentRequest
            { FullName = "Mum", Relationship = "Mother", Phone = "012-345 6789", StudentIds = new() { Ali } });
        r.Should().BeOfType<OkObjectResult>();
    }

    [Fact]
    public async Task Second_mother_for_a_child_is_refused_but_a_guardian_is_fine()
    {
        var db = Setup();
        var mother = await Parents(db).Update(Aunt, new ParentRequest { FullName = "Aunt", Relationship = "Mother", StudentIds = new() { Ali } });
        Message(mother).Should().Contain("Ali Rahman already has a mother: Mum");

        var guardian = await Parents(db).Update(Gran, new ParentRequest { FullName = "Gran", Relationship = "Guardian", StudentIds = new() { Ali } });
        guardian.Should().BeOfType<OkObjectResult>();
    }

    [Fact]
    public async Task Child_form_refuses_two_mothers()
    {
        var r = await School(Setup()).UpdateStudent(Ali, new StudentRequest
            { FullName = "Ali Rahman", DateOfBirth = new DateTime(2021, 3, 3), ParentIds = new() { Mum, Aunt } });
        Message(r).Should().Contain("only one mother");
    }

    [Fact]
    public async Task Same_child_twice_asks_first_then_saves_when_confirmed()
    {
        var db = Setup();
        var req = new StudentRequest { FullName = "ali rahman", DateOfBirth = new DateTime(2021, 3, 3) };
        var first = await School(db).CreateStudent(req);
        Message(first).Should().Contain("already on the list");

        req.AllowDuplicate = true;
        (await School(db).CreateStudent(req)).Should().BeOfType<OkObjectResult>();
        db.Students.Count().Should().Be(2);
    }

    [Fact]
    public async Task Same_name_but_different_birthday_is_a_different_child()
    {
        var r = await School(Setup()).CreateStudent(new StudentRequest { FullName = "Ali Rahman", DateOfBirth = new DateTime(2022, 5, 1) });
        r.Should().BeOfType<OkObjectResult>();
    }

    [Fact]
    public async Task Editing_a_child_does_not_ask_again()
    {
        var db = Setup();
        db.Students.Add(new Student { Id = 2, FullName = "Ali Rahman", DateOfBirth = new DateTime(2021, 3, 3) });
        db.SaveChanges();
        var r = await School(db).UpdateStudent(2, new StudentRequest
            { FullName = "Ali Rahman", DateOfBirth = new DateTime(2021, 3, 3), EmergencyContactPhone = "03-1234 5678" });
        r.Should().BeOfType<OkObjectResult>();
        db.Students.Find(2)!.EmergencyContactPhone.Should().Be("+60312345678");
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
