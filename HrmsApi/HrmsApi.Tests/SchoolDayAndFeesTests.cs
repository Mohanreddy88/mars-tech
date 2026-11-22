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
/// School phases 3 and 4.
///   Class N2 (teacher Tan): Ali (born 2021, full day, takes Mandarin) and his sister Sara
///   (born 2022, half day) — both children of Mum (parent login). Class K1 (teacher Lee): Bala.
///   Fees: full day RM 800, half day RM 500, Mandarin RM 80; sibling discount 10%.
/// </summary>
public class SchoolDayAndFeesTests
{
    private const int AdminUser = 1, TanUser = 2, LeeUser = 3, MumUser = 4;
    private const int N2 = 1, K1 = 2, Ali = 1, Sara = 2, Bala = 3, Mandarin = 3;

    private static HrmsDbContext Setup()
    {
        var db = new HrmsDbContext(new DbContextOptionsBuilder<HrmsDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString()).Options);
        db.Users.AddRange(
            new User { Id = AdminUser, Username = "admin", Email = "admin@school.test", Role = "Admin" },
            new User { Id = TanUser,   Username = "tan",   Email = "tan@school.test",   Role = "Employee" },
            new User { Id = LeeUser,   Username = "lee",   Email = "lee@school.test",   Role = "Employee" },
            new User { Id = MumUser,   Username = "mum",   Email = "mum@home.test",     Role = SchoolViewer.ParentRole });
        db.Employees.AddRange(
            new Employee { Id = 10, Name = "Ms Tan", EmployeeCode = "E1", Email = "tan@school.test", Salary = 3000, JoinDate = new DateTime(2020, 1, 1), Gender = "Female" },
            new Employee { Id = 11, Name = "Ms Lee", EmployeeCode = "E2", Email = "lee@school.test", Salary = 3000, JoinDate = new DateTime(2020, 1, 1), Gender = "Female" });
        db.SchoolClasses.AddRange(
            new SchoolClass { Id = N2, Name = "N2", ClassTeacherId = 10 },
            new SchoolClass { Id = K1, Name = "K1", ClassTeacherId = 11 });
        db.Students.AddRange(
            new Student { Id = Ali,  FullName = "Ali",  ClassId = N2, SessionType = Student.FullDay, DateOfBirth = new DateTime(2021, 1, 1) },
            new Student { Id = Sara, FullName = "Sara", ClassId = N2, SessionType = Student.HalfDay, DateOfBirth = new DateTime(2022, 6, 1) },
            new Student { Id = Bala, FullName = "Bala", ClassId = K1, SessionType = Student.FullDay });
        db.Parents.Add(new Parent { Id = 1, FullName = "Mum", Relationship = "Mother", UserId = MumUser });
        db.StudentParents.AddRange(
            new StudentParent { StudentId = Ali, ParentId = 1 },
            new StudentParent { StudentId = Sara, ParentId = 1 });
        db.FeeItems.AddRange(
            new FeeItem { Id = 1, Name = "Full day tuition", Kind = FeeItem.Session, SessionType = Student.FullDay, Amount = 800 },
            new FeeItem { Id = 2, Name = "Half day tuition", Kind = FeeItem.Session, SessionType = Student.HalfDay, Amount = 500 },
            new FeeItem { Id = Mandarin, Name = "Mandarin", Kind = FeeItem.AddOn, Amount = 80 });
        db.StudentFeeAddOns.Add(new StudentFeeAddOn { StudentId = Ali, FeeItemId = Mandarin });
        db.CompanySettings.Add(new CompanySettings { Id = 1, LegalName = "Golden", SchoolFeaturesEnabled = true, SiblingDiscountPercent = 10, FeeDueDay = 7 });
        db.SaveChanges();
        return db;
    }

    private static ControllerContext As(int userId, string role) => new()
    {
        HttpContext = new DefaultHttpContext
        {
            User = new ClaimsPrincipal(new ClaimsIdentity(new[]
                { new Claim(ClaimTypes.NameIdentifier, userId.ToString()), new Claim(ClaimTypes.Role, role), new Claim(ClaimTypes.Name, "user" + userId) }, "test"))
        }
    };

    private static (SchoolDayController ctl, Live live) Day(HrmsDbContext db, int userId, string role)
    {
        var live = new Live();
        return (new SchoolDayController(db, live, new NoPush(), new NoAudit()) { ControllerContext = As(userId, role) }, live);
    }

    private static FeesController Fees(HrmsDbContext db, int userId = AdminUser, string role = "Admin") =>
        new(db, new Settings(db), new Live(), new NoPush(), new NoAudit()) { ControllerContext = As(userId, role) };

    private static JsonElement Json(IActionResult r) => JsonSerializer.SerializeToElement(((ObjectResult)r).Value);
    private static string? Message(IActionResult r) =>
        r is BadRequestObjectResult b ? JsonSerializer.SerializeToElement(b.Value).GetProperty("message").GetString() : null;

    private static readonly DateTime Today = SchoolClock.Today;

    // ════════════ Fees ════════════

    [Fact]
    public async Task Invoices_charge_session_and_addons_with_sibling_discount_for_the_younger_child()
    {
        var db = Setup();
        var r = Json(await Fees(db).Generate(new GenerateInvoicesRequest { Year = 2026, Month = 12 }));
        r.GetProperty("created").GetInt32().Should().Be(3);

        var inv = db.FeeInvoices.Include(i => i.Lines).ToDictionary(i => i.StudentId);
        inv[Ali].Total.Should().Be(880);             // eldest: 800 + Mandarin 80, no discount
        inv[Sara].Total.Should().Be(450);            // 500 − 10%
        inv[Sara].Lines.Should().Contain(l => l.Amount == -50 && l.Description.StartsWith("Sibling discount"));
        inv[Bala].Total.Should().Be(800);
        inv.Values.Should().OnlyContain(i => i.SentAt == null && i.Status == FeeInvoice.Unpaid && i.InvoiceNo.StartsWith("INV-202612-"));

        var again = Json(await Fees(db).Generate(new GenerateInvoicesRequest { Year = 2026, Month = 12 }));
        again.GetProperty("created").GetInt32().Should().Be(0);
        again.GetProperty("alreadyHad").GetInt32().Should().Be(3);
    }

    [Fact]
    public async Task Child_without_a_fee_for_their_session_is_skipped()
    {
        var db = Setup();
        db.Students.Find(Bala)!.SessionType = Student.Daycare;
        db.SaveChanges();
        var r = Json(await Fees(db).Generate(new GenerateInvoicesRequest { Year = 2026, Month = 12 }));
        r.GetProperty("created").GetInt32().Should().Be(2);
        r.GetProperty("skipped").GetArrayLength().Should().Be(1);
    }

    [Fact]
    public async Task Payments_move_the_invoice_to_part_paid_then_paid_and_never_above_the_balance()
    {
        var db = Setup();
        await Fees(db).Generate(new GenerateInvoicesRequest { Year = 2026, Month = 12 });
        var sara = db.FeeInvoices.Single(i => i.StudentId == Sara);

        (await Fees(db).AddPayment(sara.Id, new PaymentRequest { Amount = 400, Method = "Cash" })).Should().BeOfType<OkObjectResult>();
        db.FeeInvoices.Find(sara.Id)!.Status.Should().Be(FeeInvoice.Partial);

        Message(await Fees(db).AddPayment(sara.Id, new PaymentRequest { Amount = 100, Method = "Cash" })).Should().Contain("more than the balance");

        await Fees(db).AddPayment(sara.Id, new PaymentRequest { Amount = 50, Method = "Bank transfer", Reference = "MBB123" });
        var paid = db.FeeInvoices.Include(i => i.Payments).Single(i => i.Id == sara.Id);
        paid.Status.Should().Be(FeeInvoice.Paid);
        paid.AmountPaid.Should().Be(450);
        paid.Payments.Select(p => p.ReceiptNo).Should().OnlyHaveUniqueItems().And.AllSatisfy(n => n.Should().StartWith("RCP-"));

        Message(await Fees(db).VoidInvoice(sara.Id, new VoidInvoiceRequest { Reason = "test" })).Should().Contain("has payments");
    }

    [Fact]
    public async Task Parents_see_only_their_childrens_invoices_and_only_once_sent()
    {
        var db = Setup();
        await Fees(db).Generate(new GenerateInvoicesRequest { Year = 2026, Month = 12 });
        var ali = db.FeeInvoices.Single(i => i.StudentId == Ali);
        var bala = db.FeeInvoices.Single(i => i.StudentId == Bala);
        var mum = Fees(db, MumUser, SchoolViewer.ParentRole);

        (await mum.GetInvoice(ali.Id)).Should().BeOfType<ForbidResult>("not sent yet");
        Json(await mum.Mine()).GetProperty("invoices").GetArrayLength().Should().Be(0);

        Json(await Fees(db).Send(new SendInvoicesRequest { Year = 2026, Month = 12 })).GetProperty("sent").GetInt32().Should().Be(3);
        (await mum.GetInvoice(ali.Id)).Should().BeOfType<OkObjectResult>();
        (await mum.GetInvoice(bala.Id)).Should().BeOfType<ForbidResult>("another family's child");
        var mine = Json(await mum.Mine());
        mine.GetProperty("invoices").GetArrayLength().Should().Be(2);
        mine.GetProperty("outstanding").GetDecimal().Should().Be(880 + 450);
        db.Notifications.Count(n => n.UserId == MumUser && n.Type == "school_fees").Should().Be(2);
    }

    [Fact]
    public async Task Editing_lines_recalculates_and_cannot_go_below_what_was_paid()
    {
        var db = Setup();
        await Fees(db).Generate(new GenerateInvoicesRequest { Year = 2026, Month = 12 });
        var bala = db.FeeInvoices.Single(i => i.StudentId == Bala);
        await Fees(db).AddPayment(bala.Id, new PaymentRequest { Amount = 300, Method = "Cash" });

        var ok = await Fees(db).UpdateInvoice(bala.Id, new UpdateInvoiceRequest { Lines = new()
        {
            new() { Description = "Full day tuition (from 15 Dec)", Amount = 400 },
            new() { Description = "Registration", Amount = 100 }
        }});
        Json(ok).GetProperty("Total").GetDecimal().Should().Be(500);

        Message(await Fees(db).UpdateInvoice(bala.Id, new UpdateInvoiceRequest { Lines = new() { new() { Description = "x", Amount = 200 } } }))
            .Should().Contain("less than what was already paid");
    }

    [Fact]
    public async Task Invoice_and_receipt_pdfs_are_generated()
    {
        var db = Setup();
        db.CompanySettings.Find(1)!.FeePaymentInstructions = "Maybank 5123 4567 8901";
        db.SaveChanges();
        await Fees(db).Generate(new GenerateInvoicesRequest { Year = 2026, Month = 12 });
        var sara = db.FeeInvoices.Single(i => i.StudentId == Sara);
        await Fees(db).AddPayment(sara.Id, new PaymentRequest { Amount = 200, Method = "Cash" });
        var paymentId = db.FeePayments.Single().Id;

        var invoice = await Fees(db).InvoicePdf(sara.Id) as FileContentResult;
        var receipt = await Fees(db).ReceiptPdf(paymentId) as FileContentResult;
        invoice!.FileContents.Take(4).Should().Equal((byte)'%', (byte)'P', (byte)'D', (byte)'F');
        receipt!.FileContents.Take(4).Should().Equal((byte)'%', (byte)'P', (byte)'D', (byte)'F');
        invoice.FileDownloadName.Should().StartWith("INV-");
    }

    [Fact]
    public async Task Send_again_only_when_asked_and_counts_each_send()
    {
        var db = Setup();
        await Fees(db).Generate(new GenerateInvoicesRequest { Year = 2026, Month = 12 });
        var ali = db.FeeInvoices.Single(i => i.StudentId == Ali);

        Json(await Fees(db).Send(new SendInvoicesRequest { Year = 2026, Month = 12, ClassId = N2 })).GetProperty("sent").GetInt32()
            .Should().Be(2, "only class N2 (Ali and Sara)");
        Json(await Fees(db).Send(new SendInvoicesRequest { InvoiceIds = new() { ali.Id } })).GetProperty("sent").GetInt32()
            .Should().Be(0, "already sent, and not asked to send again");
        Json(await Fees(db).Send(new SendInvoicesRequest { InvoiceIds = new() { ali.Id }, Resend = true })).GetProperty("sent").GetInt32()
            .Should().Be(1);
        db.FeeInvoices.Find(ali.Id)!.SendCount.Should().Be(2);
        db.FeeInvoices.Single(i => i.StudentId == Bala).SentAt.Should().BeNull();
    }

    [Fact]
    public async Task Parent_reports_payment_office_confirms_and_receipt_is_issued()
    {
        var db = Setup();
        await Fees(db).Generate(new GenerateInvoicesRequest { Year = 2026, Month = 12 });
        var sara = db.FeeInvoices.Single(i => i.StudentId == Sara);
        var mum = Fees(db, MumUser, SchoolViewer.ParentRole);
        var claim = new PaymentClaimForm { Amount = 450, Method = "Bank transfer", Reference = "MBB 991", PaidOn = Today };

        (await mum.CreateClaim(sara.Id, claim)).Should().BeOfType<ForbidResult>("the invoice wasn't sent yet");
        await Fees(db).Send(new SendInvoicesRequest { Year = 2026, Month = 12 });

        (await mum.CreateClaim(sara.Id, claim)).Should().BeOfType<OkObjectResult>();
        db.Notifications.Should().Contain(n => n.UserId == AdminUser && n.Type == "school_fees_claim");
        Message(await mum.CreateClaim(sara.Id, claim)).Should().Contain("still waiting");

        var id = db.FeePaymentClaims.Single().Id;
        (await Fees(db).ConfirmClaim(id, null)).Should().BeOfType<OkObjectResult>();
        var inv = db.FeeInvoices.Include(i => i.Payments).Single(i => i.Id == sara.Id);
        inv.Status.Should().Be(FeeInvoice.Paid);
        inv.Payments.Single().Method.Should().Be("Bank transfer");
        inv.Payments.Single().Reference.Should().Be("MBB 991");
        db.FeePaymentClaims.Single().Status.Should().Be(FeePaymentClaim.Confirmed);
        db.FeePaymentClaims.Single().PaymentId.Should().Be(inv.Payments.Single().Id);

        Message(await mum.CreateClaim(sara.Id, claim)).Should().Contain("already paid");
    }

    [Fact]
    public async Task Rejected_claim_tells_the_parent_why()
    {
        var db = Setup();
        await Fees(db).Generate(new GenerateInvoicesRequest { Year = 2026, Month = 12 });
        await Fees(db).Send(new SendInvoicesRequest { Year = 2026, Month = 12 });
        var ali = db.FeeInvoices.Single(i => i.StudentId == Ali);
        await Fees(db, MumUser, SchoolViewer.ParentRole).CreateClaim(ali.Id, new PaymentClaimForm { Amount = 100, Method = "DuitNow / QR" });
        var id = db.FeePaymentClaims.Single().Id;

        Message(await Fees(db).RejectClaim(id, new VoidInvoiceRequest())).Should().Contain("why");
        (await Fees(db).RejectClaim(id, new VoidInvoiceRequest { Reason = "Not in our account yet" })).Should().BeOfType<NoContentResult>();
        db.Notifications.Should().Contain(n => n.UserId == MumUser && n.Message.Contains("Not in our account yet"));
        db.FeeInvoices.Find(ali.Id)!.AmountPaid.Should().Be(0);
    }

    // ════════════ Attendance, notes, daily report ════════════

    [Fact]
    public async Task Teacher_checks_in_own_class_only_and_parents_are_told()
    {
        var db = Setup();
        var (tan, live) = Day(db, TanUser, "Employee");

        (await tan.CheckIn(Bala, new CheckInRequest())).Should().BeOfType<ForbidResult>("Bala is in Ms Lee's class");
        (await tan.CheckIn(Ali, new CheckInRequest())).Should().BeOfType<OkObjectResult>();

        var a = db.StudentAttendance.Single(x => x.StudentId == Ali);
        a.Date.Should().Be(Today);
        a.CheckInBy.Should().Be("Ms Tan");
        live.Sent.Should().Contain(s => s.ev == "day" && s.users.Contains(MumUser));
        db.Notifications.Should().Contain(n => n.UserId == MumUser && n.Type == "school_attendance");
    }

    [Fact]
    public async Task Check_out_needs_who_picked_up_and_future_days_are_refused()
    {
        var db = Setup();
        var (tan, _) = Day(db, TanUser, "Employee");
        Message(await tan.CheckOut(Ali, new CheckOutRequest { PickedUpBy = "Mum" })).Should().Contain("hasn't been checked in");
        await tan.CheckIn(Ali, new CheckInRequest { Time = "00:00" });
        Message(await tan.CheckOut(Ali, new CheckOutRequest())).Should().Contain("Who picked");
        (await tan.CheckOut(Ali, new CheckOutRequest { PickedUpBy = "Mum (Mother)" })).Should().BeOfType<OkObjectResult>();
        db.StudentAttendance.Single().PickedUpBy.Should().Be("Mum (Mother)");

        Message(await tan.CheckIn(Sara, new CheckInRequest { Date = Today.AddDays(1) })).Should().Contain("future");
    }

    [Fact]
    public async Task Parent_absence_note_reaches_the_class_teacher_and_office_but_not_for_past_days()
    {
        var db = Setup();
        var (mum, live) = Day(db, MumUser, SchoolViewer.ParentRole);

        Message(await mum.CreateNote(new ParentNoteRequest { StudentId = Ali, Kind = ParentNote.Absence, FromDate = Today.AddDays(-1) }))
            .Should().Contain("past");
        (await mum.CreateNote(new ParentNoteRequest { StudentId = Bala, Kind = ParentNote.Absence, FromDate = Today }))
            .Should().BeOfType<ForbidResult>("not her child");

        (await mum.CreateNote(new ParentNoteRequest { StudentId = Ali, Kind = ParentNote.Absence, FromDate = Today, ToDate = Today.AddDays(2), Message = "Fever" }))
            .Should().BeOfType<OkObjectResult>();
        live.Sent.Should().Contain(s => s.ev == "note" && s.users.Contains(TanUser) && s.users.Contains(AdminUser) && !s.users.Contains(LeeUser));

        // The teacher sees it on today's list
        var (tan, _) = Day(db, TanUser, "Employee");
        var list = Json(await tan.GetAttendance(N2, null));
        var aliRow = list.GetProperty("rows").EnumerateArray().Single(r => r.GetProperty("studentId").GetInt32() == Ali);
        aliRow.GetProperty("notes").GetArrayLength().Should().Be(1);
    }

    [Fact]
    public async Task Parents_see_the_daily_report_only_after_it_is_sent()
    {
        var db = Setup();
        var (tan, _) = Day(db, TanUser, "Employee");
        var (mum, _) = Day(db, MumUser, SchoolViewer.ParentRole);

        (await tan.SaveReport(Ali, null, new DailyReportRequest { Lunch = "All", Mood = "Happy", NapFrom = "12:30", NapTo = "14:00" }))
            .Should().BeOfType<OkObjectResult>();
        Json(await mum.GetDay(Ali, null)).GetProperty("report").ValueKind.Should().Be(JsonValueKind.Null);

        Message(await tan.SaveReport(Ali, null, new DailyReportRequest { Mood = "Grumpy" })).Should().Contain("mood");

        Json(await tan.Publish(new PublishReportsRequest { StudentIds = new() { Ali, Bala } })).GetProperty("published").GetInt32().Should().Be(1);
        Json(await mum.GetDay(Ali, null)).GetProperty("report").GetProperty("Lunch").GetString().Should().Be("All");
        (await mum.GetDay(Bala, null)).Should().BeOfType<ForbidResult>();
    }

    // ── fakes ──

    private sealed class Live : IChatNotifier
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
