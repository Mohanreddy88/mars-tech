using System.Security.Claims;
using System.Text.Json;
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
/// Parent app Account page: own phone number, children's contacts, and pick-up people that the
/// office approves.  Ali (N2) — Mum (Mother, login) and Dad (Father); Bala is someone else's child.
/// </summary>
public class ParentAccountTests
{
    private const int AdminUser = 1, MumUser = 2, OtherUser = 3, Ali = 1, Bala = 2, Mum = 1, Dad = 2, Other = 3;

    private static HrmsDbContext Setup()
    {
        var db = new HrmsDbContext(new DbContextOptionsBuilder<HrmsDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString()).Options);
        db.Users.AddRange(
            new User { Id = AdminUser, Username = "admin", Email = "admin@school.test", Role = "Admin", IsActive = true },
            new User { Id = MumUser, Username = "mum", Email = "mum@home.test", Role = SchoolViewer.ParentRole, IsActive = true },
            new User { Id = OtherUser, Username = "other", Email = "other@home.test", Role = SchoolViewer.ParentRole, IsActive = true });
        db.SchoolClasses.Add(new SchoolClass { Id = 1, Name = "N2" });
        db.Students.AddRange(
            new Student { Id = Ali, FullName = "Ali", ClassId = 1, MedicalNotes = "Peanuts" },
            new Student { Id = Bala, FullName = "Bala", ClassId = 1 });
        db.Parents.AddRange(
            new Parent { Id = Mum, FullName = "Mum", Relationship = "Mother", UserId = MumUser, Phone = "+60123456789" },
            new Parent { Id = Dad, FullName = "Dad", Relationship = "Father", Phone = "+60198765432" },
            new Parent { Id = Other, FullName = "Other", Relationship = "Mother", UserId = OtherUser, Phone = "+60111111111" });
        db.StudentParents.AddRange(
            new StudentParent { StudentId = Ali, ParentId = Mum },
            new StudentParent { StudentId = Ali, ParentId = Dad },
            new StudentParent { StudentId = Bala, ParentId = Other });
        db.CompanySettings.Add(new CompanySettings { Id = 1, LegalName = "Golden", SchoolFeaturesEnabled = true });
        db.SaveChanges();
        return db;
    }

    private static ParentAccountController Ctl(HrmsDbContext db, int userId, string role) =>
        new(db, new NoPush(), new Live())
        {
            ControllerContext = new ControllerContext
            {
                HttpContext = new DefaultHttpContext
                {
                    User = new ClaimsPrincipal(new ClaimsIdentity(new[]
                        { new Claim(ClaimTypes.NameIdentifier, userId.ToString()), new Claim(ClaimTypes.Role, role) }, "test"))
                }
            }
        };

    private static JsonElement Json(IActionResult r) =>
        JsonSerializer.SerializeToElement(((OkObjectResult)r).Value, new JsonSerializerOptions(JsonSerializerDefaults.Web));

    private static string? Message(IActionResult r) =>
        (r as BadRequestObjectResult)?.Value?.GetType().GetProperty("message")?.GetValue(((BadRequestObjectResult)r).Value) as string;

    [Fact]
    public async Task Parent_sees_own_details_children_and_both_parents_as_contacts()
    {
        var db = Setup();
        var a = Json(await Ctl(db, MumUser, SchoolViewer.ParentRole).Account());
        a.GetProperty("parent").GetProperty("fullName").GetString().Should().Be("Mum");
        var child = a.GetProperty("children").EnumerateArray().Single();
        child.GetProperty("fullName").GetString().Should().Be("Ali");
        child.GetProperty("medicalNotes").GetString().Should().Be("Peanuts");
        child.GetProperty("contacts").EnumerateArray().Select(c => c.GetProperty("fullName").GetString())
            .Should().Equal("Mum", "Dad");
    }

    [Fact]
    public async Task Parent_can_change_their_phone_but_not_to_another_parents_number()
    {
        var db = Setup();
        var mum = Ctl(db, MumUser, SchoolViewer.ParentRole);
        Message(await mum.SetPhone(new PhoneRequest { Phone = "019-876 5432" })).Should().Contain("already used");
        (await mum.SetPhone(new PhoneRequest { Phone = "012-222 3333" })).Should().BeOfType<OkObjectResult>();
        db.Parents.AsNoTracking().Single(p => p.Id == Mum).Phone.Should().Be("+60122223333");
    }

    [Fact]
    public async Task Pickup_person_waits_for_the_office_then_can_collect_the_child()
    {
        var db = Setup();
        var mum = Ctl(db, MumUser, SchoolViewer.ParentRole);

        (await mum.AddPickupPerson(new PickupPersonRequest { StudentIds = new() { Bala }, FullName = "Gran", Relationship = "Grandmother", Phone = "0133333333" }))
            .Should().BeOfType<ForbidResult>("not her child");
        Message(await mum.AddPickupPerson(new PickupPersonRequest { StudentIds = new() { Ali }, FullName = "Gran", Relationship = "Grandmother" }))
            .Should().Contain("phone");

        (await mum.AddPickupPerson(new PickupPersonRequest { StudentIds = new() { Ali }, FullName = "Gran", Relationship = "Grandmother", Phone = "0133333333" }))
            .Should().BeOfType<OkObjectResult>();
        var gran = db.PickupPeople.Single();
        gran.Status.Should().Be(PickupPerson.Pending);
        db.Notifications.Should().Contain(n => n.UserId == AdminUser && n.Type == "school_pickup_person");
        Message(await mum.AddPickupPerson(new PickupPersonRequest { StudentIds = new() { Ali }, FullName = "gran", Relationship = "Grandmother", Phone = "0133333333" }))
            .Should().Contain("already on the list");

        // Office approves: the parent is told
        var admin = Ctl(db, AdminUser, "Admin");
        Json(await admin.List(null)).GetArrayLength().Should().Be(1);
        (await admin.Approve(gran.Id)).Should().BeOfType<OkObjectResult>();
        db.PickupPeople.AsNoTracking().Single().Status.Should().Be(PickupPerson.Approved);
        db.Notifications.Should().Contain(n => n.UserId == MumUser && n.Title == "Pick-up person approved");
        Json(await admin.List(null)).GetArrayLength().Should().Be(0, "nothing left to approve");
    }

    [Fact]
    public async Task Rejected_pickup_person_shows_the_reason_to_the_parent()
    {
        var db = Setup();
        await Ctl(db, MumUser, SchoolViewer.ParentRole).AddPickupPerson(new PickupPersonRequest
            { StudentIds = new() { Ali }, FullName = "Uncle", Relationship = "Uncle", Phone = "0144444444" });
        var id = db.PickupPeople.Single().Id;
        await Ctl(db, AdminUser, "Admin").Reject(id, new RejectPickupRequest { Reason = "Please bring his IC to the office first" });

        var person = Json(await Ctl(db, MumUser, SchoolViewer.ParentRole).Account())
            .GetProperty("children")[0].GetProperty("pickupPeople")[0];
        person.GetProperty("status").GetString().Should().Be(PickupPerson.Rejected);
        person.GetProperty("rejectReason").GetString().Should().Contain("IC");
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
