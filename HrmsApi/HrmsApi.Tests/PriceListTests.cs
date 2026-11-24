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
/// Price lists (one per year) with Golden Montessori's "Price &amp; Terms, 2024":
///   Half day 8:00–12:00 RM 930 (breakfast) · Full day 7:30–18:30 RM 1,450 (breakfast, lunch &amp; tea-break)
///   One-time: Registration 300, Uniform 280, Bedding 210 (full day only) · Twice a year: Supplies 450 (Jan, Jul)
///   Deposit 1,000 (2nd month).  Upon registration: half 1,960 / full 2,690.  2nd month: half 1,930 / full 2,450.
/// Ali — half day, Sara — full day (sisters: Sara gets the sibling discount on the monthly part only).
/// </summary>
public class PriceListTests
{
    private const int AdminUser = 1, Ali = 1, Sara = 2;

    private static HrmsDbContext Setup(decimal siblingDiscount = 0)
    {
        var db = new HrmsDbContext(new DbContextOptionsBuilder<HrmsDbContext>().UseInMemoryDatabase(Guid.NewGuid().ToString()).Options);
        db.Users.Add(new User { Id = AdminUser, Username = "admin", Email = "a@school.test", Role = "Admin", IsActive = true });
        db.Students.AddRange(
            new Student { Id = Ali, FullName = "Ali", SessionType = Student.HalfDay, DateOfBirth = new DateTime(2020, 1, 1) },
            new Student { Id = Sara, FullName = "Sara", SessionType = Student.FullDay, DateOfBirth = new DateTime(2022, 1, 1) });
        db.Parents.Add(new Parent { Id = 1, FullName = "Mum", Relationship = "Mother" });
        db.StudentParents.AddRange(new StudentParent { StudentId = Ali, ParentId = 1 }, new StudentParent { StudentId = Sara, ParentId = 1 });
        db.CompanySettings.Add(new CompanySettings { Id = 1, LegalName = "Golden Montessori", SchoolFeaturesEnabled = true, SiblingDiscountPercent = siblingDiscount, FeeDueDay = 7 });
        db.FeePriceLists.Add(new FeePriceList
        {
            Name = "2024", EffectiveFrom = new DateTime(2024, 11, 1), TwiceAYearMonths = "1,7",
            Sessions =
            {
                new FeePriceSession { SessionType = Student.HalfDay, Start = "08:00", End = "12:00", MealsIncluded = "breakfast", MonthlyFee = 930 },
                new FeePriceSession { SessionType = Student.FullDay, Start = "07:30", End = "18:30", MealsIncluded = "breakfast, lunch & tea-break", MonthlyFee = 1450 },
                new FeePriceSession { SessionType = Student.Daycare, Offered = false, Start = "07:30", End = "18:30" }
            },
            Charges =
            {
                new FeePriceCharge { Name = "Registration", Kind = FeePriceCharge.OneTime, Amount = 300, SortOrder = 0 },
                new FeePriceCharge { Name = "Supplies", Kind = FeePriceCharge.TwiceAYear, Amount = 450, SortOrder = 1 },
                new FeePriceCharge { Name = "Uniform (2 + 1 sports)", Kind = FeePriceCharge.OneTime, Amount = 280, SortOrder = 2 },
                new FeePriceCharge { Name = "Bedding", Kind = FeePriceCharge.OneTime, Amount = 210, SessionType = Student.FullDay, SortOrder = 3 },
                new FeePriceCharge { Name = "Deposit", Kind = FeePriceCharge.Deposit, Amount = 1000, SortOrder = 4 }
            }
        });
        db.SaveChanges();
        return db;
    }

    private static ControllerContext Admin() => new()
    {
        HttpContext = new DefaultHttpContext
        {
            User = new ClaimsPrincipal(new ClaimsIdentity(new[] { new Claim(ClaimTypes.NameIdentifier, "1"), new Claim(ClaimTypes.Role, "Admin") }, "test"))
        }
    };

    private static FeesController Fees(HrmsDbContext db) => new(db, new Settings(db), new Live(), new NoPush(), new NoAudit()) { ControllerContext = Admin() };
    private static PriceListsController Lists(HrmsDbContext db) => new(db, new Settings(db), new NoAudit()) { ControllerContext = Admin() };

    private static decimal Total(HrmsDbContext db, int child, int year, int month) =>
        db.FeeInvoices.AsNoTracking().Single(i => i.StudentId == child && i.Year == year && i.Month == month).Total;

    [Fact]
    public async Task New_children_pay_the_registration_total_then_the_deposit_month_then_the_monthly_fee()
    {
        var db = Setup();
        await Fees(db).Generate(new GenerateInvoicesRequest { Year = 2024, Month = 11 });
        Total(db, Ali, 2024, 11).Should().Be(1960, "half day upon registration");
        Total(db, Sara, 2024, 11).Should().Be(2690, "full day upon registration (with bedding)");

        await Fees(db).Generate(new GenerateInvoicesRequest { Year = 2024, Month = 12 });
        Total(db, Ali, 2024, 12).Should().Be(1930, "2nd month: fee + deposit");
        Total(db, Sara, 2024, 12).Should().Be(2450);
        db.StudentDeposits.Count(d => d.Status == StudentDeposit.Held).Should().Be(2);

        // January is a twice-a-year month, but they joined less than 3 months ago: no supplies again
        await Fees(db).Generate(new GenerateInvoicesRequest { Year = 2025, Month = 1 });
        Total(db, Ali, 2025, 1).Should().Be(930);

        await Fees(db).Generate(new GenerateInvoicesRequest { Year = 2025, Month = 7 });
        Total(db, Ali, 2025, 7).Should().Be(930 + 450, "supplies in July");
        Total(db, Sara, 2025, 7).Should().Be(1450 + 450);
    }

    [Fact]
    public async Task Sibling_discount_is_only_on_the_monthly_part()
    {
        var db = Setup(siblingDiscount: 10);
        await Fees(db).Generate(new GenerateInvoicesRequest { Year = 2024, Month = 11 });
        Total(db, Ali, 2024, 11).Should().Be(1960, "eldest pays in full");
        Total(db, Sara, 2024, 11).Should().Be(2690 - 145, "10% off the RM 1,450 monthly fee only");
    }

    [Fact]
    public async Task A_new_year_price_list_takes_over_from_its_start_date()
    {
        var db = Setup();
        await Fees(db).Generate(new GenerateInvoicesRequest { Year = 2024, Month = 11 });   // registration
        await Fees(db).Generate(new GenerateInvoicesRequest { Year = 2024, Month = 12 });   // deposit month
        var created = (OkObjectResult)await Lists(db).Create(new NewPriceListRequest { Name = "2025", EffectiveFrom = new DateTime(2025, 11, 1) });
        var id = db.FeePriceLists.Single(p => p.Name == "2025").Id;
        db.FeePriceSessions.Count(s => s.PriceListId == id).Should().Be(3, "copied from 2024");

        // Raise the fees for 2025
        var update = new PriceListRequest
        {
            Name = "2025", EffectiveFrom = new DateTime(2025, 11, 1), TwiceAYearMonths = "1,7",
            Sessions = new()
            {
                new() { SessionType = Student.HalfDay, Start = "08:00", End = "12:00", MonthlyFee = 990 },
                new() { SessionType = Student.FullDay, Start = "07:30", End = "18:30", MonthlyFee = 1500 },
                new() { SessionType = Student.Daycare, Offered = false }
            },
            Charges = new() { new() { Name = "Registration", Kind = FeePriceCharge.OneTime, Amount = 300 } }
        };
        (await Lists(db).Update(id, update)).Should().BeOfType<OkObjectResult>();

        await Fees(db).Generate(new GenerateInvoicesRequest { Year = 2025, Month = 10 });
        Total(db, Ali, 2025, 10).Should().Be(930, "still the 2024 prices in October");
        await Fees(db).Generate(new GenerateInvoicesRequest { Year = 2025, Month = 11 });
        Total(db, Ali, 2025, 11).Should().Be(990, "2025 prices from November");
    }

    [Fact]
    public async Task Price_list_rules()
    {
        var db = Setup();
        var bad = new PriceListRequest
        {
            Name = "2025", EffectiveFrom = new DateTime(2025, 11, 1),
            Sessions = new() { new() { SessionType = Student.HalfDay, Start = "12:00", End = "08:00", MonthlyFee = 900 } }
        };
        var id = db.FeePriceLists.Single().Id;
        (await Lists(db).Update(id, bad)).Should().BeOfType<BadRequestObjectResult>("end before start");
        (await Lists(db).Delete(id)).Should().BeOfType<BadRequestObjectResult>("already in use");
    }

    [Fact]
    public async Task A_deposit_is_refunded_or_deducted_from_an_unpaid_invoice()
    {
        var db = Setup();
        await Fees(db).Generate(new GenerateInvoicesRequest { Year = 2024, Month = 11 });
        await Fees(db).Generate(new GenerateInvoicesRequest { Year = 2024, Month = 12 });
        await Fees(db).Generate(new GenerateInvoicesRequest { Year = 2025, Month = 1 });
        var aliDeposit = db.StudentDeposits.Single(d => d.StudentId == Ali);
        var saraDeposit = db.StudentDeposits.Single(d => d.StudentId == Sara);

        await Lists(db).Settle(aliDeposit.Id, new SettleDepositRequest { How = "refund", Note = "Bank transfer" });
        db.StudentDeposits.AsNoTracking().Single(d => d.Id == aliDeposit.Id).Status.Should().Be(StudentDeposit.Refunded);

        var jan = db.FeeInvoices.Single(i => i.StudentId == Sara && i.Year == 2025 && i.Month == 1);
        (await Lists(db).Settle(saraDeposit.Id, new SettleDepositRequest { How = "deduct", InvoiceId = jan.Id })).Should().BeOfType<OkObjectResult>();
        Total(db, Sara, 2025, 1).Should().Be(1450 - 1000);
        (await Lists(db).Settle(saraDeposit.Id, new SettleDepositRequest { How = "refund" })).Should().BeOfType<BadRequestObjectResult>("already settled");
    }

    [Fact]
    public async Task Session_hours_come_from_the_price_list_in_force()
    {
        var db = Setup();
        var t = await SchoolTimes.LoadAsync(db);
        t.PriceList.Should().Be("2024");
        t.StartFor(Student.FullDay).Should().Be(new TimeOnly(7, 30));
        t.EndFor(Student.HalfDay).Should().Be(new TimeOnly(12, 0));
        t.EndFor(Student.FullDay).Should().Be(new TimeOnly(18, 30));
    }

    [Fact]
    public void Price_and_terms_pdf_is_made()
    {
        var db = Setup();
        var list = db.FeePriceLists.Include(p => p.Sessions).Include(p => p.Charges).Single();
        FeePdf.PriceTerms(db.CompanySettings.First(), list).Length.Should().BeGreaterThan(1000);
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
