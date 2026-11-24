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

/// <summary>Parent home banners: admins manage them; parents see the live ones meant for them.</summary>
public class BannersTests
{
    private const int AdminUser = 1, MumUser = 2, OtherUser = 3;

    private static HrmsDbContext Setup()
    {
        var db = new HrmsDbContext(new DbContextOptionsBuilder<HrmsDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString()).Options);
        db.Users.AddRange(
            new User { Id = AdminUser, Username = "admin", Email = "admin@school.test", Role = "Admin", IsActive = true },
            new User { Id = MumUser, Username = "mum", Email = "mum@home.test", Role = SchoolViewer.ParentRole, IsActive = true },
            new User { Id = OtherUser, Username = "other", Email = "other@home.test", Role = SchoolViewer.ParentRole, IsActive = true });
        db.SchoolClasses.AddRange(new SchoolClass { Id = 1, Name = "N2" }, new SchoolClass { Id = 2, Name = "K1" });
        db.Students.AddRange(new Student { Id = 1, FullName = "Ali", ClassId = 1 }, new Student { Id = 2, FullName = "Bala", ClassId = 2 });
        db.Parents.AddRange(
            new Parent { Id = 1, FullName = "Mum", Relationship = "Mother", UserId = MumUser },
            new Parent { Id = 2, FullName = "Other", Relationship = "Mother", UserId = OtherUser });
        db.StudentParents.AddRange(new StudentParent { StudentId = 1, ParentId = 1 }, new StudentParent { StudentId = 2, ParentId = 2 });
        db.CompanySettings.Add(new CompanySettings { Id = 1, LegalName = "Golden", SchoolFeaturesEnabled = true });
        db.SaveChanges();
        return db;
    }

    private static BannersController Ctl(HrmsDbContext db, int userId, string role) =>
        new(db, new NoAudit(), new Settings(db))
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

    private static List<string> Titles(IActionResult r) =>
        JsonSerializer.SerializeToElement(((OkObjectResult)r).Value, new JsonSerializerOptions(JsonSerializerDefaults.Web))
            .EnumerateArray().Select(e => e.GetProperty("title").GetString()!).ToList();

    private static string? Message(IActionResult r) =>
        (r as BadRequestObjectResult)?.Value?.GetType().GetProperty("message")?.GetValue(((BadRequestObjectResult)r).Value) as string;

    [Fact]
    public async Task Parents_see_live_banners_for_the_school_and_their_childs_class_in_order()
    {
        var db = Setup();
        var admin = Ctl(db, AdminUser, "Admin");
        var today = SchoolClock.Today;
        (await admin.Create(new BannerForm { Title = "Holiday camp", Link = "https://forms.example.com/camp", ButtonText = "Register" })).Should().BeOfType<OkObjectResult>();
        await admin.Create(new BannerForm { Title = "N2 photo day", ClassId = 1 });
        await admin.Create(new BannerForm { Title = "K1 trip", ClassId = 2 });
        await admin.Create(new BannerForm { Title = "Next month", StartsOn = today.AddDays(10) });
        await admin.Create(new BannerForm { Title = "Last week", EndsOn = today.AddDays(-1) });
        await admin.Create(new BannerForm { Title = "Switched off", IsActive = false });

        Titles(await Ctl(db, MumUser, SchoolViewer.ParentRole).Current()).Should().Equal("Holiday camp", "N2 photo day");
        Titles(await Ctl(db, OtherUser, SchoolViewer.ParentRole).Current()).Should().Equal("Holiday camp", "K1 trip");

        // Reorder: the photo day goes first
        var photo = db.SchoolBanners.Single(b => b.Title == "N2 photo day").Id;
        await admin.Move(photo, up: true);
        Titles(await Ctl(db, MumUser, SchoolViewer.ParentRole).Current()).Should().Equal("N2 photo day", "Holiday camp");

        Titles(await admin.GetAll()).Should().HaveCount(6, "admins see every banner");
    }

    [Fact]
    public async Task Only_admins_manage_banners()
    {
        var db = Setup();
        (await Ctl(db, MumUser, SchoolViewer.ParentRole).Create(new BannerForm { Title = "Mine" })).Should().BeOfType<ForbidResult>();
        (await Ctl(db, MumUser, SchoolViewer.ParentRole).GetAll()).Should().BeOfType<ForbidResult>();
        db.SchoolBanners.Should().BeEmpty();
    }

    [Fact]
    public async Task Button_must_open_a_parent_page_or_an_https_address()
    {
        var db = Setup();
        var admin = Ctl(db, AdminUser, "Admin");
        Message(await admin.Create(new BannerForm { Title = "X", Link = "javascript:alert(1)" })).Should().Contain("https://");
        Message(await admin.Create(new BannerForm { Title = "X", Link = "http://plain.example.com" })).Should().Contain("https://");
        Message(await admin.Create(new BannerForm { Title = "X", ButtonText = "Go" })).Should().Be("Choose what the button opens.");
        Message(await admin.Create(new BannerForm { Title = "" })).Should().Be("Enter a headline.");

        (await admin.Create(new BannerForm { Title = "Fees", Link = "fees" })).Should().BeOfType<OkObjectResult>();
        db.SchoolBanners.Single().ButtonText.Should().Be("Find out more", "a button gets a default label");
    }

    [Theory]
    [InlineData(false, null, null, "Off")]
    [InlineData(true, 1, null, "Scheduled")]
    [InlineData(true, null, -1, "Ended")]
    [InlineData(true, -1, 1, "Live")]
    public void Status_follows_switch_and_dates(bool active, int? startIn, int? endIn, string expected)
    {
        var today = new DateTime(2026, 11, 24);
        BannersController.Status(active, startIn == null ? null : today.AddDays(startIn.Value),
            endIn == null ? null : today.AddDays(endIn.Value), today).Should().Be(expected);
    }

    [Fact]
    public async Task Without_banners_parents_still_get_slides_from_their_own_data()
    {
        var db = Setup();
        var mum = Ctl(db, MumUser, SchoolViewer.ParentRole);
        Titles(await mum.Current()).Should().Equal("Welcome to Golden");

        var today = SchoolClock.Today;
        db.FeeInvoices.Add(new FeeInvoice { StudentId = 1, InvoiceNo = "INV-1", Year = today.Year, Month = today.Month,
            Total = 930, AmountPaid = 0, Status = FeeInvoice.Unpaid, DueDate = today.AddDays(7), SentAt = DateTime.UtcNow });
        db.FeeInvoices.Add(new FeeInvoice { StudentId = 2, InvoiceNo = "INV-2", Year = today.Year, Month = today.Month,
            Total = 500, Status = FeeInvoice.Unpaid, DueDate = today.AddDays(7), SentAt = DateTime.UtcNow });   // another family's
        db.Announcements.Add(new Announcement { Title = "Sports day", Body = "Friday", CreatedByName = "Office" });
        db.Announcements.Add(new Announcement { Title = "K1 trip", Body = "Zoo", ClassId = 2, CreatedByName = "Office" });   // not Mum's class
        db.PublicHolidays.Add(new PublicHoliday { Name = "Christmas", Date = today.AddDays(3), Year = today.Year });
        db.SaveChanges();

        Titles(await mum.Current()).Should().Equal("RM 930.00 school fees due", "New from the school", "School closed: Christmas");

        // School banners come first; the automatic ones follow
        await Ctl(db, AdminUser, "Admin").Create(new BannerForm { Title = "Holiday camp" });
        Titles(await mum.Current()).First().Should().Be("Holiday camp");
    }

    private sealed class Settings(HrmsDbContext db) : ICompanySettingsService
    {
        public Task<CompanySettings> GetAsync() => db.CompanySettings.FirstAsync();
    }

    private sealed class NoAudit : IAuditService
    {
        public Task LogAsync(string action, string entityType, string? entityId, string description, string username,
            int? userId = null, string? oldValues = null, string? newValues = null, string? ipAddress = null) => Task.CompletedTask;
    }
}
