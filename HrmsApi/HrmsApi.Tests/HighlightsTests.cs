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

/// <summary>Admin home highlight cards: only what applies, most urgent first, "All caught up" otherwise.</summary>
public class HighlightsTests
{
    private static HrmsDbContext Db(bool school = true)
    {
        var db = new HrmsDbContext(new DbContextOptionsBuilder<HrmsDbContext>().UseInMemoryDatabase(Guid.NewGuid().ToString()).Options);
        db.CompanySettings.Add(new CompanySettings { Id = 1, LegalName = "Golden", SchoolFeaturesEnabled = school });
        db.SaveChanges();
        return db;
    }

    private static List<HighlightCard> Cards(HrmsDbContext db)
    {
        var ctl = new HighlightsController(db, new Settings(db))
        {
            ControllerContext = new ControllerContext
            {
                HttpContext = new DefaultHttpContext
                {
                    User = new ClaimsPrincipal(new ClaimsIdentity(new[] { new Claim(ClaimTypes.NameIdentifier, "1"), new Claim(ClaimTypes.Role, "Admin") }, "test"))
                }
            }
        };
        var ok = (OkObjectResult)ctl.Get().GetAwaiter().GetResult();
        return ((IEnumerable<HighlightCard>)ok.Value!).ToList();
    }

    [Fact]
    public void Nothing_to_do_shows_all_caught_up()
    {
        Cards(Db()).Select(c => c.Key).Should().Contain("done");
    }

    [Fact]
    public void Things_to_do_come_first_and_replace_all_caught_up()
    {
        var db = Db();
        db.LeaveRequests.Add(new LeaveRequest { EmployeeId = 1, Status = "Pending", StartDate = DateTime.Today, EndDate = DateTime.Today });
        db.Students.Add(new Student { Id = 1, FullName = "Ali" });
        db.PickupPeople.Add(new PickupPerson { StudentId = 1, FullName = "Gran", Relationship = "Grandmother", AddedByName = "Mum" });
        db.PublicHolidays.Add(new PublicHoliday { Name = "Deepavali", Date = SchoolClock.Today.AddDays(5), Year = SchoolClock.Today.Year });
        db.SaveChanges();

        var cards = Cards(db);
        cards.Select(c => c.Key).Should().NotContain("done");
        cards.Should().Contain(c => c.Key == "leave" && c.Title == "1 leave request waiting" && c.Page == "approvals");
        cards.Should().Contain(c => c.Key == "pickup" && c.Page == "pickup-people");
        cards.Should().Contain(c => c.Key == "holiday" && c.Title.Contains("Deepavali"));
        cards.TakeWhile(c => c.Tone == "warn").Should().HaveCountGreaterThanOrEqualTo(2, "things to do come first");
    }

    [Fact]
    public void School_cards_only_when_school_features_are_on()
    {
        var db = Db(school: false);
        db.Students.Add(new Student { Id = 1, FullName = "Ali" });
        db.PickupPeople.Add(new PickupPerson { StudentId = 1, FullName = "Gran", Relationship = "Grandmother", AddedByName = "Mum" });
        db.SaveChanges();
        Cards(db).Should().NotContain(c => c.Group == "school");
    }

    private sealed class Settings(HrmsDbContext db) : ICompanySettingsService
    {
        public Task<CompanySettings> GetAsync() => db.CompanySettings.FirstAsync();
    }
}
