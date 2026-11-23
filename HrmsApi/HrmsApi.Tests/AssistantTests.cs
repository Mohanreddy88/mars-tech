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
using Microsoft.Extensions.Configuration;

namespace HrmsApi.Tests;

/// <summary>Help chatbot: word matching, who sees which answers, unanswered questions.</summary>
public class AssistantTests
{
    // ── Matching ──

    private static List<BotFaq> Starter(bool school = true) =>
        BotStarterFaqs.For(school).Select((f, i) => { f.Id = i + 1; return f; }).ToList();

    [Theory]
    [InlineData("how to apply leave", "How do I apply for leave?")]
    [InlineData("I want to take annual leave next week", "How do I apply for leave?")]
    [InlineData("leave balance", "How many leave days do I have left?")]
    [InlineData("where is my payslip", "Where can I find my payslip?")]
    [InlineData("download payslips", "Where can I find my payslip?")]
    [InlineData("forgot password", "I forgot my password")]
    [InlineData("how to pay yuran", "How do I pay school fees?")]
    [InlineData("my son has fever, not coming today", "My child is sick or absent today")]
    [InlineData("grandma will pick up", "Someone else is picking up my child")]
    [InlineData("what is socso", "What are the EPF, SOCSO, EIS and PCB deductions?")]
    public void FindsTheRightAnswer(string typed, string expected)
    {
        var best = BotMatcher.Rank(Starter(), typed).First();
        best.faq.Question.Should().Be(expected);
        best.score.Should().BeGreaterThanOrEqualTo(BotMatcher.MinScore);
    }

    [Theory]
    [InlineData("what's the weather like")]
    [InlineData("asdfgh")]
    [InlineData("the")]
    public void UnrelatedText_HasNoAnswer(string typed)
    {
        var best = BotMatcher.Rank(Starter(), typed).FirstOrDefault();
        (best.faq == null || best.score < BotMatcher.MinScore).Should().BeTrue();
    }

    [Theory]
    [InlineData("hi", "greeting")]
    [InlineData("Hello!", "greeting")]
    [InlineData("thank you", "thanks")]
    [InlineData("terima kasih", "thanks")]
    [InlineData("hi, how do I apply leave", null)]
    public void SmallTalk(string typed, string? expected) => BotMatcher.SmallTalk(typed).Should().Be(expected);

    [Fact]
    public void Words_DropsCommonWordsAndEndings() =>
        BotMatcher.Words("How do I download my Payslips?").Should().Equal("download", "payslip");

    // ── Controller ──

    private const int AdminUser = 1, StaffUser = 2, ParentUser = 3;

    private static HrmsDbContext Setup(bool school = true)
    {
        var db = new HrmsDbContext(new DbContextOptionsBuilder<HrmsDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString()).Options);
        db.Users.AddRange(
            new User { Id = AdminUser,  Username = "admin", Email = "admin@co.test", Role = "Admin" },
            new User { Id = StaffUser,  Username = "siti",  Email = "siti@co.test",  Role = "Employee" },
            new User { Id = ParentUser, Username = "mum",   Email = "mum@home.test", Role = SchoolViewer.ParentRole });
        db.Employees.Add(new Employee { Id = 10, Name = "Siti Aminah", EmployeeCode = "E1", Email = "siti@co.test", Salary = 3000, JoinDate = new DateTime(2020, 1, 1), Gender = "Female" });
        db.Parents.Add(new Parent { Id = 1, FullName = "Mum Lim", Relationship = "Mother", UserId = ParentUser });
        db.CompanySettings.Add(new CompanySettings { Id = 1, LegalName = "Golden Sdn Bhd", DisplayName = "Golden Kids", Phone = "+60312345678", FeeDueDay = 5, SchoolFeaturesEnabled = school });
        db.BotFaqs.AddRange(Starter());
        db.SaveChanges();
        return db;
    }

    /// <summary>Stands in for Claude: returns a fixed answer (or null = failure) and counts calls.</summary>
    private sealed class FakeAi : IAssistantAi
    {
        /// <summary>The server has its own key (the old "configured").</summary>
        public bool HasServerKey { get; init; } = true;
        public string Model => "test-model";
        public string? CheckResult { get; init; }
        public string? LastCompanyKey { get; private set; }
        public Task<string?> CheckKeyAsync(string apiKey, CancellationToken ct) => Task.FromResult(CheckResult);
        public string? Answer { get; init; } = "You owe RM 450.";
        public string? Page { get; init; }
        /// <summary>Fail with this reason (e.g. no credit) instead of answering.</summary>
        public string? Error { get; set; }
        public int Calls { get; private set; }
        public AssistantTools? LastTools { get; private set; }
        public Task<AiAnswer?> AnswerAsync(string? companyKey, AssistantTools tools, string system, IReadOnlyList<ChatTurn> history,
            string question, CancellationToken ct)
        {
            Calls++;
            LastCompanyKey = companyKey;
            LastTools = tools;
            if (Error != null) return Task.FromResult<AiAnswer?>(AiAnswer.Fail(Error));
            return Task.FromResult(Answer == null ? null : new AiAnswer(Answer, Page, 100, 20, 1));
        }
    }

    private const string TestSecret = "test-server-secret-for-encrypting-company-keys-1234567890";

    private static AssistantController Controller(HrmsDbContext db, int userId, string role, IAssistantAi? ai = null, int? dailyLimit = null) =>
        new(db, new CompanySettingsService(db, new ConfigurationBuilder().Build()), ai ?? new FakeAi { HasServerKey = false }, null!,
            new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["Assistant:DailyLimitPerUser"] = dailyLimit?.ToString(),
                ["Jwt:Key"] = TestSecret
            }).Build())
        {
            ControllerContext = new ControllerContext
            {
                HttpContext = new DefaultHttpContext
                {
                    User = new ClaimsPrincipal(new ClaimsIdentity(new[]
                    {
                        new Claim(ClaimTypes.NameIdentifier, userId.ToString()), new Claim(ClaimTypes.Role, role)
                    }, "test"))
                }
            }
        };

    /// <summary>The anonymous object of an OkObjectResult, as JSON (camelCase like the API).</summary>
    private static JsonElement Json(IActionResult r) =>
        JsonSerializer.SerializeToElement(((OkObjectResult)r).Value, new JsonSerializerOptions(JsonSerializerDefaults.Web));

    private static List<string> Questions(JsonElement start) =>
        start.GetProperty("topics").EnumerateArray()
            .SelectMany(t => t.GetProperty("items").EnumerateArray().Select(i => i.GetProperty("question").GetString()!))
            .ToList();

    [Fact]
    public async Task Parent_SeesParentAndEveryoneAnswers_NotStaffOnes()
    {
        var db = Setup();
        var start = Json(await Controller(db, ParentUser, SchoolViewer.ParentRole).Start());

        var questions = Questions(start);
        questions.Should().Contain("How do I pay school fees?").And.Contain("I forgot my password");
        questions.Should().NotContain("Where can I find my payslip?");
        start.GetProperty("greeting").GetString().Should().StartWith("Hi Mum!").And.Contain("Golden Kids");
        start.GetProperty("canMessageSchool").GetBoolean().Should().BeTrue();
        questions.Should().Contain("How do I contact Golden Kids?", "placeholders are filled in");
    }

    [Fact]
    public async Task Staff_SeeStaffAnswers_AndParentOnesHiddenWhenSchoolOff()
    {
        var db = Setup(school: false);
        var start = Json(await Controller(db, StaffUser, "Employee").Start());
        var questions = Questions(start);
        questions.Should().Contain("Where can I find my payslip?");
        questions.Should().NotContain("How do I pay school fees?");
        start.GetProperty("canMessageSchool").GetBoolean().Should().BeFalse();

        // An admin sees everything (but not parent answers while the school features are off)
        var admin = Questions(Json(await Controller(db, AdminUser, "Admin").Start()));
        admin.Should().Contain("Where can I find my payslip?").And.NotContain("How do I pay school fees?");
    }

    [Fact]
    public async Task Ask_AnswersWithFilledPlaceholders_AndPageLink()
    {
        var db = Setup();
        var r = Json(await Controller(db, ParentUser, SchoolViewer.ParentRole).Ask(new AskRequest { Text = "when is the fee due date" }));
        var answer = r.GetProperty("answer");
        answer.GetProperty("answer").GetString().Should().Contain("day 5");
        answer.GetProperty("action").GetProperty("key").GetString().Should().Be("fees");
    }

    [Fact]
    public async Task Ask_StaffAnswerNotGivenToParent_AndUnansweredIsLoggedOnce()
    {
        var db = Setup();
        var ctl = Controller(db, ParentUser, SchoolViewer.ParentRole);

        var r = Json(await ctl.Ask(new AskRequest { Text = "where is my payslip" }));
        r.GetProperty("unanswered").GetBoolean().Should().BeTrue("payslips are for staff");

        await ctl.Ask(new AskRequest { Text = "where is my payslip" });
        db.BotUnansweredQuestions.Should().ContainSingle(u => u.UserId == ParentUser && u.Audience == BotFaq.ForParents);
    }

    [Fact]
    public async Task AdminStarter_AddsOnce()
    {
        var db = Setup();
        db.BotFaqs.RemoveRange(db.BotFaqs);
        db.SaveChanges();
        var ctl = Controller(db, AdminUser, "Admin");

        var first = Json(await ctl.AddStarter()).GetProperty("added").GetInt32();
        first.Should().Be(Starter().Count);
        Json(await ctl.AddStarter()).GetProperty("added").GetInt32().Should().Be(0);
    }

    [Fact]
    public async Task AdminCreate_ValidatesAudienceAndLink()
    {
        var db = Setup();
        var ctl = Controller(db, AdminUser, "Admin");
        (await ctl.Create(new BotFaqRequest { Question = "Q", Answer = "A", Audience = "Everyone" })).Should().BeOfType<BadRequestObjectResult>();
        (await ctl.Create(new BotFaqRequest { Question = "Q", Answer = "A", Audience = BotFaq.ForAll, Action = "nowhere" })).Should().BeOfType<BadRequestObjectResult>();
        (await ctl.Create(new BotFaqRequest { Question = "Office hours?", Answer = "8am to 6pm", Audience = BotFaq.ForAll, Category = "Contact" }))
            .Should().BeOfType<OkObjectResult>();
    }

    // ── AI answers ──

    private static void TurnAiOn(HrmsDbContext db)
    {
        db.CompanySettings.Find(1)!.AssistantAiEnabled = true;
        db.SaveChanges();
    }

    [Fact]
    public async Task Ai_NotUsed_WithoutKeyOrCompanySwitch()
    {
        var db = Setup();
        var ai = new FakeAi();   // has a key...
        var r = Json(await Controller(db, ParentUser, SchoolViewer.ParentRole, ai).Ask(new AskRequest { Text = "how much do I owe" }));
        ai.Calls.Should().Be(0, "...but the company switch is off");
        r.GetProperty("source").GetString().Should().NotBe("ai");

        TurnAiOn(db);
        var noKey = new FakeAi { HasServerKey = false };
        Json(await Controller(db, ParentUser, SchoolViewer.ParentRole, noKey).Ask(new AskRequest { Text = "how much do I owe" }));
        noKey.Calls.Should().Be(0, "no API key on the server");
        db.BotAiUsageLog.Should().BeEmpty();
    }

    [Fact]
    public async Task Ai_AnswersPersonalQuestions_ButClearGeneralFaqStaysFree()
    {
        var db = Setup();
        TurnAiOn(db);
        var ai = new FakeAi { Page = "fees" };

        // "my fees" is about the parent's own data: AI, even though an FAQ about fees exists
        var r = Json(await Controller(db, ParentUser, SchoolViewer.ParentRole, ai).Ask(new AskRequest { Text = "how much are my fees this month" }));
        r.GetProperty("source").GetString().Should().Be("ai");
        r.GetProperty("answer").GetProperty("answer").GetString().Should().Be("You owe RM 450.");
        r.GetProperty("answer").GetProperty("action").GetProperty("key").GetString().Should().Be("fees");
        ai.Calls.Should().Be(1);
        db.BotAiUsageLog.Should().ContainSingle(u => u.UserId == ParentUser && u.Succeeded && u.InputTokens == 100);

        // A general question with a clear FAQ answer: no AI call
        var staffAi = new FakeAi();
        var faq = Json(await Controller(db, StaffUser, "Employee", staffAi).Ask(new AskRequest { Text = "how do I apply for annual leave" }));
        faq.GetProperty("source").GetString().Should().Be("faq");
        staffAi.Calls.Should().Be(0);
    }

    [Fact]
    public async Task Admin_sees_why_AI_answers_fail_until_one_works_again()
    {
        var db = Setup();
        TurnAiOn(db);
        var ai = new FakeAi { Error = "Your Anthropic credit has run out." };
        var admin = Controller(db, AdminUser, "Admin", ai);

        Json(await admin.AiStatus()).GetProperty("problem").ValueKind.Should().Be(JsonValueKind.Null);

        for (var i = 0; i < 2; i++)
        {
            var r = Json(await Controller(db, ParentUser, SchoolViewer.ParentRole, ai).Ask(new AskRequest { Text = "how much do I owe" }));
            r.GetProperty("source").GetString().Should().NotBe("ai", "a failed AI call never reaches the user");
        }
        var problem = Json(await admin.AiStatus()).GetProperty("problem");
        problem.GetProperty("message").GetString().Should().Be("Your Anthropic credit has run out.");
        problem.GetProperty("failures").GetInt32().Should().Be(2);

        // Credit added: the next answer works and the warning goes away
        ai.Error = null;
        Json(await Controller(db, ParentUser, SchoolViewer.ParentRole, ai).Ask(new AskRequest { Text = "how much do I owe" }))
            .GetProperty("source").GetString().Should().Be("ai");
        Json(await admin.AiStatus()).GetProperty("problem").ValueKind.Should().Be(JsonValueKind.Null);
    }

    [Theory]
    [InlineData("{\"type\":\"error\",\"error\":{\"type\":\"invalid_request_error\",\"message\":\"Your credit balance is too low to access the Anthropic API.\"}}", "credit has run out")]
    [InlineData("something unexpected", "Anthropic refused the request: something unexpected")]
    public void Anthropic_errors_are_explained_for_the_admin(string apiError, string expected)
    {
        var ex = new Anthropic.Exceptions.AnthropicBadRequestException
        {
            StatusCode = System.Net.HttpStatusCode.BadRequest,
            ResponseBody = apiError
        };
        AiErrors.Describe(ex).Should().Contain(expected);
    }

    [Fact]
    public void Network_and_timeout_failures_are_explained()
    {
        AiErrors.Describe(new HttpRequestException("no route")).Should().Contain("couldn't reach Anthropic");
        AiErrors.Describe(new TaskCanceledException()).Should().Contain("didn't answer in time");
    }

    [Fact]
    public async Task Ai_Failure_FallsBackToFaq_AndUnknownStillLogged()
    {
        var db = Setup();
        TurnAiOn(db);
        var broken = new FakeAi { Answer = null };

        var r = Json(await Controller(db, ParentUser, SchoolViewer.ParentRole, broken).Ask(new AskRequest { Text = "when are my fees due" }));
        r.GetProperty("source").GetString().Should().Be("faq", "the FAQ answer is used when the AI fails");
        r.GetProperty("answer").GetProperty("answer").GetString().Should().Contain("day 5");

        var none = Json(await Controller(db, ParentUser, SchoolViewer.ParentRole, broken).Ask(new AskRequest { Text = "what is the meaning of life" }));
        none.GetProperty("unanswered").GetBoolean().Should().BeTrue();
        db.BotAiUsageLog.Should().HaveCount(2).And.OnlyContain(u => !u.Succeeded);
        db.BotUnansweredQuestions.Should().ContainSingle();
    }

    [Fact]
    public async Task Ai_DailyLimitPerUser()
    {
        var db = Setup();
        TurnAiOn(db);
        var ai = new FakeAi();
        var ctl = Controller(db, ParentUser, SchoolViewer.ParentRole, ai, dailyLimit: 2);
        for (var i = 0; i < 3; i++) await ctl.Ask(new AskRequest { Text = $"what is my child doing {i}" });
        ai.Calls.Should().Be(2, "the third question that day doesn't go to the AI");
    }

    [Fact]
    public async Task AiSwitch_AdminOnly_AndNeedsKey()
    {
        var db = Setup();
        (await Controller(db, AdminUser, "Admin", new FakeAi { HasServerKey = false }).SetAi(new AiSettingsRequest { Enabled = true }))
            .Should().BeOfType<BadRequestObjectResult>();
        (await Controller(db, AdminUser, "Admin", new FakeAi()).SetAi(new AiSettingsRequest { Enabled = true }))
            .Should().BeOfType<OkObjectResult>();
        db.CompanySettings.AsNoTracking().Single().AssistantAiEnabled.Should().BeTrue();
    }

    // ── Company's own AI key ──

    [Fact]
    public void SecretBox_RoundTrips_AndNeedsTheSameSecret()
    {
        var sealedKey = SecretBox.Encrypt("sk-ant-api03-secret", TestSecret, "assistant-ai-key");
        sealedKey.Should().StartWith("v1:").And.NotContain("sk-ant");
        SecretBox.TryDecrypt(sealedKey, TestSecret, "assistant-ai-key").Should().Be("sk-ant-api03-secret");
        SecretBox.TryDecrypt(sealedKey, "another-server-secret-entirely-0000000", "assistant-ai-key").Should().BeNull();
        SecretBox.TryDecrypt(sealedKey, TestSecret, "other-purpose").Should().BeNull();
        SecretBox.TryDecrypt("v1:not-base64!", TestSecret, "assistant-ai-key").Should().BeNull();
    }

    private const string GoodKey = "sk-ant-api03-abcdefghijklmnopqrstuvwxyz-WXYZ";

    [Fact]
    public async Task ConnectKey_Tested_StoredEncrypted_AndUsedForAnswers()
    {
        var db = Setup();
        var ai = new FakeAi { HasServerKey = false };
        var admin = Controller(db, AdminUser, "Admin", ai);

        (await admin.ConnectKey(new AiKeyRequest { ApiKey = "hello" })).Should().BeOfType<BadRequestObjectResult>();
        (await Controller(db, AdminUser, "Admin", new FakeAi { HasServerKey = false, CheckResult = "This API key isn't valid." })
            .ConnectKey(new AiKeyRequest { ApiKey = GoodKey })).Should().BeOfType<BadRequestObjectResult>("Anthropic refused it");
        db.CompanySettings.AsNoTracking().Single().AssistantAiKeyEncrypted.Should().BeNull();

        (await admin.ConnectKey(new AiKeyRequest { ApiKey = GoodKey })).Should().BeOfType<OkObjectResult>();
        var s = db.CompanySettings.AsNoTracking().Single();
        s.AssistantAiKeyEncrypted.Should().NotContain("sk-ant", "never stored in plain text");
        s.AssistantAiKeyHint.Should().Be("…WXYZ");
        s.AssistantAiEnabled.Should().BeTrue();

        var status = Json(await admin.AiStatus());
        status.GetProperty("keySource").GetString().Should().Be("company");
        status.GetProperty("keyHint").GetString().Should().Be("…WXYZ");
        status.GetRawText().Should().NotContain("abcdefghij", "the key itself is never sent back");

        // A parent's personal question now goes to the AI with the company's key
        var r = Json(await Controller(db, ParentUser, SchoolViewer.ParentRole, ai).Ask(new AskRequest { Text = "how much do I owe" }));
        r.GetProperty("source").GetString().Should().Be("ai");
        ai.LastCompanyKey.Should().Be(GoodKey);
    }

    [Fact]
    public async Task DisconnectKey_TurnsAiOff_WhenServerHasNoKey()
    {
        var db = Setup();
        var ai = new FakeAi { HasServerKey = false };
        var admin = Controller(db, AdminUser, "Admin", ai);
        await admin.ConnectKey(new AiKeyRequest { ApiKey = GoodKey });

        (await admin.DisconnectKey()).Should().BeOfType<OkObjectResult>();
        var s = db.CompanySettings.AsNoTracking().Single();
        s.AssistantAiKeyEncrypted.Should().BeNull();
        s.AssistantAiEnabled.Should().BeFalse();
        Json(await admin.AiStatus()).GetProperty("configured").GetBoolean().Should().BeFalse();
    }

    [Fact]
    public async Task ConnectKey_AdminOnlyAttribute()
    {
        var attr = typeof(AssistantController).GetMethod(nameof(AssistantController.ConnectKey))!
            .GetCustomAttributes(typeof(Microsoft.AspNetCore.Authorization.AuthorizeAttribute), false)
            .Cast<Microsoft.AspNetCore.Authorization.AuthorizeAttribute>();
        attr.Should().Contain(a => a.Roles == "Admin");
        await Task.CompletedTask;
    }

    // ── AI tools: each person sees only their own data ──

    private static (HrmsDbContext db, AssistantTools tools) ParentTools()
    {
        var db = Setup();
        db.Students.AddRange(new Student { Id = 1, FullName = "Aisha Lim" }, new Student { Id = 2, FullName = "Other Child" });
        db.StudentParents.Add(new StudentParent { StudentId = 1, ParentId = 1 });
        db.FeeInvoices.AddRange(
            new FeeInvoice { Id = 1, InvoiceNo = "INV-1", StudentId = 1, Year = 2026, Month = 11, DueDate = new DateTime(2026, 11, 5), Total = 500, AmountPaid = 50, Status = FeeInvoice.Partial, SentAt = DateTime.UtcNow },
            new FeeInvoice { Id = 2, InvoiceNo = "INV-2", StudentId = 2, Year = 2026, Month = 11, DueDate = new DateTime(2026, 11, 5), Total = 999, Status = FeeInvoice.Unpaid, SentAt = DateTime.UtcNow });
        db.SaveChanges();
        var settings = db.CompanySettings.Single();
        var me = new AssistantUser(ParentUser, "Mum Lim", false, true, new List<int> { 1 }, null, new List<int>(), true, BotFaq.ForParents);
        return (db, new AssistantTools(db, null!, settings, me, new List<(string, string)> { ("fees", "Fees") }));
    }

    private static IReadOnlyDictionary<string, JsonElement> Input(object o) =>
        JsonSerializer.SerializeToElement(o).EnumerateObject().ToDictionary(p => p.Name, p => p.Value);

    [Fact]
    public async Task Tools_ParentGetsOwnFeesOnly_AndNoStaffTools()
    {
        var (_, tools) = ParentTools();
        tools.Definitions().Select(t => JsonSerializer.SerializeToElement(t).GetProperty("name").GetString())
            .Should().Contain("get_my_fees").And.NotContain("get_my_payslips").And.NotContain("get_attendance_today");

        var fees = JsonDocument.Parse(await tools.RunAsync("get_my_fees", Input(new { }))).RootElement;
        fees.GetProperty("outstanding").GetDecimal().Should().Be(450, "only her own child's invoice");
        fees.GetProperty("invoices").GetArrayLength().Should().Be(1);

        var other = JsonDocument.Parse(await tools.RunAsync("get_child_day", Input(new { child_id = 2 }))).RootElement;
        other.GetProperty("error").GetString().Should().Contain("not linked");

        await FluentActions.Awaiting(() => tools.RunAsync("get_my_payslips", Input(new { })))
            .Should().ThrowAsync<InvalidOperationException>("staff tools are refused for a parent");
    }

    [Fact]
    public async Task Tools_SuggestPage_OnlyKnownPages()
    {
        var (_, tools) = ParentTools();
        await tools.RunAsync("suggest_page", Input(new { page = "payroll-admin" }));
        tools.SuggestedPage.Should().BeNull();
        await tools.RunAsync("suggest_page", Input(new { page = "fees" }));
        tools.SuggestedPage.Should().Be("fees");
    }

    private static List<string> ToolNames(AssistantTools t) =>
        t.Definitions().Select(d => JsonSerializer.SerializeToElement(d).GetProperty("name").GetString()!).ToList();

    private static AssistantTools ToolsFor(HrmsDbContext db, AssistantUser me) =>
        new(db, null!, db.CompanySettings.Single(), me, new List<(string, string)>());

    [Fact]
    public async Task Tools_AdminGetsSchoolAndHrTools_OthersDoNot()
    {
        var (db, parent) = ParentTools();
        var admin = ToolsFor(db, new AssistantUser(AdminUser, "Admin", true, false, new(), null, new(), true, BotFaq.ForEmployees));
        var teacher = ToolsFor(db, new AssistantUser(StaffUser, "Siti", false, false, new(), 10, new() { 7 }, true, BotFaq.ForEmployees));

        ToolNames(admin).Should().Contain(new[] { "get_unpaid_fees", "get_pending_approvals", "get_payroll_summary", "offer_download" });
        ToolNames(teacher).Should().Contain("get_children").And.Contain("get_parent_messages_waiting")
            .And.NotContain("get_unpaid_fees").And.NotContain("get_pending_approvals");
        ToolNames(parent).Should().NotContain("get_unpaid_fees").And.NotContain("get_children");

        await FluentActions.Awaiting(() => parent.RunAsync("get_unpaid_fees", Input(new { })))
            .Should().ThrowAsync<InvalidOperationException>();
        await FluentActions.Awaiting(() => teacher.RunAsync("get_pending_approvals", Input(new { })))
            .Should().ThrowAsync<InvalidOperationException>();

        var fees = JsonDocument.Parse(await admin.RunAsync("get_unpaid_fees", Input(new { }))).RootElement;
        fees.GetProperty("invoices").GetInt32().Should().Be(2, "the admin sees every family's unpaid invoices");
        fees.GetProperty("outstanding").GetDecimal().Should().Be(450 + 999);
    }

    [Fact]
    public async Task Tools_TeacherSeesOnlyOwnClassChildren()
    {
        var (db, _) = ParentTools();
        db.SchoolClasses.AddRange(new SchoolClass { Id = 7, Name = "N2" }, new SchoolClass { Id = 8, Name = "K1" });
        db.Students.Find(1)!.ClassId = 7;
        db.Students.Find(2)!.ClassId = 8;
        db.SaveChanges();
        var teacher = ToolsFor(db, new AssistantUser(StaffUser, "Siti", false, false, new(), 10, new() { 7 }, true, BotFaq.ForEmployees));

        var kids = JsonDocument.Parse(await teacher.RunAsync("get_children", Input(new { }))).RootElement;
        kids.EnumerateArray().Select(k => k.GetProperty("fullName").GetString()).Should().Equal("Aisha Lim");
    }

    [Fact]
    public async Task Tools_Downloads_LimitedByRole()
    {
        var (db, parent) = ParentTools();
        // Parent: own invoice only; no admin reports
        (await parent.RunAsync("offer_download", Input(new { report = "invoice", invoice_no = "INV-2" }))).Should().Contain("\"ok\":false");
        parent.Download.Should().BeNull();
        await parent.RunAsync("offer_download", Input(new { report = "invoice", invoice_no = "INV-1" }));
        parent.Download!.Value.Path.Should().Be("school/fees/invoices/1/pdf");
        (await parent.RunAsync("offer_download", Input(new { report = "payroll" }))).Should().Contain("\"ok\":false");

        var admin = ToolsFor(db, new AssistantUser(AdminUser, "Admin", true, false, new(), null, new(), true, BotFaq.ForEmployees));
        await admin.RunAsync("offer_download", Input(new { report = "unpaid-fees", year = 2026, month = 11 }));
        admin.Download!.Value.Path.Should().Be("school/fees/export?unpaidOnly=true&year=2026&month=11");
        admin.Download!.Value.Label.Should().Contain("Nov 2026");
    }
}
