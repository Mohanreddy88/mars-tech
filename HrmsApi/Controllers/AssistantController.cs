using System.Security.Claims;
using HrmsApi.Data;
using HrmsApi.Models;
using HrmsApi.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace HrmsApi.Controllers;

/// <summary>
/// The help chatbot ("Assistant"): a menu of topics plus answers to typed questions, from the
/// questions and answers the company's admins write (<see cref="BotFaq"/>). No AI and no outside
/// service. Parents see the parent and "everyone" answers, staff the employee and "everyone"
/// ones; admins see all. Questions it can't answer are kept for the admins (admin/unanswered).
/// </summary>
[ApiController]
[Route("api/assistant")]
[Authorize]
public class AssistantController : ControllerBase
{
    private const int RelatedCount = 3;
    private const int MaxLoggedPerUserPerDay = 30;
    /// <summary>With AI on, an FAQ answer is used directly only when it fits this well.</summary>
    private const double StrongFaqScore = 6.0;
    private const int MaxHistoryTurns = 10;

    private readonly HrmsDbContext _db;
    private readonly ICompanySettingsService _settings;
    private readonly IAssistantAi _ai;
    private readonly ILeaveService _leave;
    private readonly int _dailyAiLimit;
    private readonly IPushService? _push;
    private readonly IEmailQueue? _email;

    /// <summary>After a problem that won't fix itself (no credit, bad key), the AI is tried again after this long.</summary>
    private static readonly TimeSpan AiPause = TimeSpan.FromMinutes(10);
    /// <summary>Admins are told about the same AI problem at most this often.</summary>
    private static readonly TimeSpan AiAlertEvery = TimeSpan.FromHours(24);
    private const string AiDownType = "assistant_ai_down", AiUpType = "assistant_ai_up";
    private const string ChatbotPage = "/master/chatbot";

    public AssistantController(HrmsDbContext db, ICompanySettingsService settings, IAssistantAi ai, ILeaveService leave,
        IConfiguration config, IPushService? push = null, IEmailQueue? email = null)
    {
        _db = db; _settings = settings; _ai = ai; _leave = leave; _push = push; _email = email;
        _dailyAiLimit = int.TryParse(config["Assistant:DailyLimitPerUser"], out var n) && n > 0 ? n : 30;
        _secret = config["Jwt:Key"] ?? "";
    }

    /// <summary>SecretBox purpose for the company's AI key.</summary>
    private const string KeyPurpose = "assistant-ai-key";
    private readonly string _secret;

    /// <summary>The company's own API key (decrypted), or null.</summary>
    private string? CompanyKey(CompanySettings s) => SecretBox.TryDecrypt(s.AssistantAiKeyEncrypted, _secret, KeyPurpose);

    /// <summary>AI answers are on: switched on and a key (company or server) is there.</summary>
    private bool AiOn(CompanySettings s) => s.AssistantAiEnabled && _ai.CanAnswer(CompanyKey(s));

    // ── Chat (every login) ──

    /// <summary>GET /api/assistant/start — greeting, topics with their answers, and quick links.</summary>
    [HttpGet("start")]
    public async Task<IActionResult> Start()
    {
        var me = await MeAsync();
        if (me == null) return Forbid();
        var settings = await _settings.GetAsync();

        var faqs = await Visible(me).OrderBy(f => f.Category).ThenBy(f => f.SortOrder).ThenBy(f => f.Id).ToListAsync();
        var company = CompanyName(settings);
        var firstName = me.Name.Split(' ', StringSplitOptions.RemoveEmptyEntries).FirstOrDefault() ?? me.Name;

        return Ok(new
        {
            greeting = $"Hi {firstName}! I'm the {company} assistant. Pick a topic below or type your question.",
            topics = faqs
                .GroupBy(f => f.Category)
                .Select(g => new { category = g.Key, items = g.Select(f => ToDto(f, me, settings)).ToList() })
                .ToList(),
            actions = ActionsFor(me).Select(a => new { a.Key, a.Label }),
            canMessageSchool = me.IsParent && me.School,
            ai = AiOn(settings),
            // Shown at the top of the chat while AI answers are stopped (e.g. no Anthropic credit)
            aiNotice = await StoppedNoticeAsync(me, settings)
        });
    }

    /// <summary>
    /// POST /api/assistant/ask { text, history? } — answers a typed question.
    ///   1. A close match in the admins' questions and answers is returned as is (free).
    ///   2. With AI on (server API key + Company Settings switch), personal questions ("how much
    ///      do I owe?", "was Aisha absent?") and anything without a close match go to Claude,
    ///      which looks up this user's own data with read-only tools.
    ///   3. Otherwise / if the AI fails: the nearest FAQ answer, or "no answer" (saved for admins).
    /// <c>source</c> in the reply says which one answered: "faq", "ai" or "none".
    /// </summary>
    [HttpPost("ask")]
    public async Task<IActionResult> Ask([FromBody] AskRequest req)
    {
        var me = await MeAsync();
        if (me == null) return Forbid();
        var text = (req.Text ?? "").Trim();
        if (text.Length == 0) return BadRequest(new { message = "Type a question." });
        if (text.Length > BotUnanswered.MaxTextLength) text = text[..BotUnanswered.MaxTextLength];

        var settings = await _settings.GetAsync();
        var smallTalk = BotMatcher.SmallTalk(text);
        if (smallTalk != null)
        {
            return Ok(new
            {
                reply = smallTalk == "thanks" ? "You're welcome! Anything else I can help with?" : "Hello! What can I help you with?",
                answer = (object?)null, related = Array.Empty<object>(), unanswered = false, source = "faq"
            });
        }

        var ranked = BotMatcher.Rank(await Visible(me).ToListAsync(), text);
        var best = ranked.FirstOrDefault();
        var faqMatch = best.faq != null && best.score >= BotMatcher.MinScore;
        var aiOn = AiOn(settings);
        // Set when the AI is stopped or just failed: the chat shows it above the answer
        AiNotice? aiNotice = null;

        object FaqReply() => new
        {
            reply = (string?)null,
            answer = ToDto(best.faq!, me, settings),
            related = ranked.Skip(1).Where(r => r.score >= BotMatcher.MinScore).Take(RelatedCount)
                .Select(r => new { r.faq.Id, question = Fill(r.faq.Question, settings) }),
            unanswered = false,
            source = "faq",
            aiNotice
        };

        // A clear FAQ match for a general question needs no AI
        if (faqMatch && (!aiOn || (best.score >= StrongFaqScore && !await LooksPersonalAsync(me, text))))
            return Ok(FaqReply());

        // Stopped (no credit, bad key): don't call Anthropic again for a while, answer from the list
        var stopped = aiOn ? await BlockingFailureAsync(settings) : null;
        if (stopped != null && stopped.AskedAt > DateTime.UtcNow - AiPause)
            aiNotice = Notice(me, stopped.Error!, blocking: true);
        else if (aiOn && await UnderDailyAiLimitAsync(me))
        {
            var (ai, error) = await AskAiAsync(me, settings, text, req.History);
            if (error != null) aiNotice = Notice(me, error, AiErrors.IsBlocking(error));
            if (ai != null)
            {
                var page = ai.SuggestedPage == null ? null : ActionsFor(me).FirstOrDefault(a => a.Key == ai.SuggestedPage);
                return Ok(new
                {
                    reply = (string?)null,
                    answer = new
                    {
                        Id = 0, question = text, answer = ai.Text,
                        action = page == null ? null : new { page.Key, page.Label },
                        // A report or document to download (API path relative to /api, fetched with the login token)
                        download = ai.Download == null ? null : new { label = ai.Download.Value.Label, path = ai.Download.Value.Path }
                    },
                    related = Array.Empty<object>(),
                    unanswered = false,
                    source = "ai"
                });
            }
        }

        if (faqMatch) return Ok(FaqReply());

        await LogUnansweredAsync(me, text);
        return Ok(new
        {
            reply = me.IsParent && me.School
                ? "Sorry, I don't have an answer for that yet. I've noted your question for the school. You can also message the school office directly."
                : $"Sorry, I don't have an answer for that yet. I've noted your question for {CompanyName(settings)}.",
            answer = (object?)null,
            related = ranked.Take(RelatedCount).Select(r => new { r.faq.Id, question = Fill(r.faq.Question, settings) }),
            unanswered = true,
            source = "none",
            aiNotice
        });
    }

    // ── AI stopped: notice in the chat, pause, tell the admins ──

    /// <summary>
    /// The newest AI attempt, if it failed for a reason that won't fix itself (no credit, bad key)
    /// and no new key was connected since. Null = AI answers are working (or never tried).
    /// </summary>
    private async Task<BotAiUsage?> BlockingFailureAsync(CompanySettings s)
    {
        var last = await _db.BotAiUsageLog.AsNoTracking()
            .OrderByDescending(u => u.AskedAt).ThenByDescending(u => u.Id).FirstOrDefaultAsync();
        if (last == null || last.Succeeded || !AiErrors.IsBlocking(last.Error)) return null;
        // A key connected after the failure gets a fresh try
        if (s.AssistantAiKeySetAt != null && s.AssistantAiKeySetAt > last.AskedAt) return null;
        return last;
    }

    /// <summary>The notice for the top of the chat while AI answers are stopped, or null.</summary>
    private async Task<AiNotice?> StoppedNoticeAsync(Viewer me, CompanySettings s)
    {
        if (!AiOn(s)) return null;
        var stopped = await BlockingFailureAsync(s);
        return stopped == null ? null : Notice(me, stopped.Error!, blocking: true);
    }

    /// <summary>
    /// Admins see what's wrong and where to fix it; everyone else a calm note (never billing details).
    /// </summary>
    private static AiNotice Notice(Viewer me, string error, bool blocking)
    {
        if (me.IsAdmin)
            return blocking
                ? new AiNotice("error", $"AI answers stopped: {error} Until then, the chat answers from the help list.",
                    AiErrors.ConsoleUrl, "Open the Anthropic Console")
                : new AiNotice("warning", $"The AI couldn't answer just now: {error} This answer is from the help list.", null, null);
        if (!blocking)
            return new AiNotice("info", "Smart answers didn't work just now, so this answer is from the help list.", null, null);
        return new AiNotice("info", me.IsParent && me.School
            ? "Smart answers are paused for now. You'll get answers from the help list, and you can still message the school."
            : "Smart answers are paused for now. You'll get answers from the help list.", null, null);
    }

    /// <summary>
    /// Tells every admin (bell, phone, email) that AI answers stopped — once per problem, at most
    /// daily — or that they work again.
    /// </summary>
    private async Task AlertAdminsAsync(bool down, string? error)
    {
        try
        {
            var now = DateTime.UtcNow;
            if (down)
            {
                var lastWorked = await _db.BotAiUsageLog.Where(u => u.Succeeded).Select(u => (DateTime?)u.AskedAt).MaxAsync();
                var since = lastWorked > now - AiAlertEvery ? lastWorked.Value : now - AiAlertEvery;
                if (await _db.Notifications.AnyAsync(n => n.Type == AiDownType && n.CreatedAt > since)) return;
            }
            else
            {
                // Only after a "stopped" alert that hasn't been followed by "work again"
                var lastDown = await _db.Notifications.Where(n => n.Type == AiDownType).Select(n => (DateTime?)n.CreatedAt).MaxAsync();
                if (lastDown == null || await _db.Notifications.AnyAsync(n => n.Type == AiUpType && n.CreatedAt > lastDown)) return;
            }

            var admins = await _db.Users.AsNoTracking().Where(u => u.Role == UserAccess.Admin && u.IsActive)
                .Select(u => new { u.Id, u.Email, u.Username }).ToListAsync();
            if (admins.Count == 0) return;

            var title = down ? "Chatbot AI answers stopped" : "Chatbot AI answers work again";
            var message = down
                ? $"{error} Until then the chatbot answers from the help list. Anthropic Console: {AiErrors.ConsoleUrl}"
                : "The chatbot is answering with AI again.";
            foreach (var a in admins)
                _db.Notifications.Add(new Notification
                {
                    UserId = a.Id, Title = title, Message = message.Length > 500 ? message[..500] : message,
                    Type = down ? AiDownType : AiUpType, Link = ChatbotPage, CreatedAt = now
                });
            await _db.SaveChangesAsync();

            if (_push != null)
                await _push.SendToUsersAsync(_db, admins.Select(a => a.Id).ToList(), title,
                    message.Length > 200 ? message[..200] : message, down ? AiDownType : AiUpType, ChatbotPage);

            if (down && _email != null)
            {
                var html = $"""
                    <div style="font-family:Segoe UI,Arial,sans-serif;font-size:14px;color:#111827">
                      <h2 style="color:#b91c1c;margin:0 0 12px">Chatbot AI answers stopped</h2>
                      <p>{System.Net.WebUtility.HtmlEncode(error ?? "")}</p>
                      <p>Until this is fixed, the chatbot answers from your help list, and people see a short
                         "smart answers are paused" note.</p>
                      <p><a href="{AiErrors.ConsoleUrl}" style="background:#2563eb;color:#fff;padding:10px 16px;border-radius:8px;text-decoration:none">Open the Anthropic Console</a></p>
                      <p style="color:#6b7280;font-size:12px">AI answers start again by themselves within 10 minutes of the problem being fixed,
                         or straight away when you connect a new key on the Chatbot page.</p>
                    </div>
                    """;
                foreach (var a in admins.Where(a => !string.IsNullOrWhiteSpace(a.Email)))
                    _email.Enqueue(new EmailJob { ToEmail = a.Email, Subject = "Chatbot AI answers stopped", Body = html });
            }
        }
        catch
        {
            // Alerts are best effort: the chat answer must not fail because of them
        }
    }

    // ── Admin: AI answers ──

    /// <summary>GET /api/assistant/admin/ai — whether AI answers are available and on, and their usage.</summary>
    [HttpGet("admin/ai")]
    [Authorize(Roles = "Admin")]
    public async Task<IActionResult> AiStatus()
    {
        var settings = await _settings.GetAsync();
        var today = DateTime.UtcNow.Date;
        var since = today.AddDays(-30);
        var rows = await _db.BotAiUsageLog.AsNoTracking().Where(u => u.AskedAt >= since).ToListAsync();
        static object Sum(IEnumerable<BotAiUsage> r) => new
        {
            questions = r.Count(),
            answered = r.Count(x => x.Succeeded),
            inputTokens = r.Sum(x => x.InputTokens),
            outputTokens = r.Sum(x => x.OutputTokens)
        };
        var companyKey = CompanyKey(settings);
        return Ok(new
        {
            configured = _ai.CanAnswer(companyKey),
            // Whose key is used: "company" (connected on this page), "server" (the host's), or null (none)
            keySource = companyKey != null ? "company" : _ai.HasServerKey ? "server" : null,
            keyHint = companyKey != null ? settings.AssistantAiKeyHint : null,
            keySetAt = companyKey != null ? settings.AssistantAiKeySetAt : null,
            // A key is saved but can't be read any more (the server secret changed): connect it again
            keyUnreadable = settings.AssistantAiKeyEncrypted != null && companyKey == null,
            serverKeyAvailable = _ai.HasServerKey,
            enabled = settings.AssistantAiEnabled,
            model = _ai.Model,
            dailyLimitPerUser = _dailyAiLimit,
            today = Sum(rows.Where(r => r.AskedAt >= today)),
            last30Days = Sum(rows),
            // The latest AI failure with a reason, unless an AI answer worked after it
            problem = LatestProblem(rows)
        });
    }

    /// <summary>PUT /api/assistant/admin/ai { enabled } — switch AI answers on or off for this company.</summary>
    [HttpPut("admin/ai")]
    [Authorize(Roles = "Admin")]
    public async Task<IActionResult> SetAi([FromBody] AiSettingsRequest req)
    {
        var settings = await _db.CompanySettings.FirstOrDefaultAsync(c => c.Id == CompanySettings.SingletonId)
                       ?? throw new KeyNotFoundException("Company settings not found.");
        if (req.Enabled && !_ai.CanAnswer(CompanyKey(settings)))
            return BadRequest(new { message = "Connect an Anthropic API key first." });
        settings.AssistantAiEnabled = req.Enabled;
        settings.UpdatedAt = DateTime.UtcNow;
        await _db.SaveChangesAsync();
        return Ok(new { enabled = settings.AssistantAiEnabled });
    }

    /// <summary>
    /// PUT /api/assistant/admin/ai/key { apiKey } — connects the company's own Anthropic API key.
    /// The key is tested first (a free call), then stored encrypted; only its last characters are
    /// ever shown again. AI answers are switched on with it.
    /// </summary>
    [HttpPut("admin/ai/key")]
    [Authorize(Roles = "Admin")]
    public async Task<IActionResult> ConnectKey([FromBody] AiKeyRequest req)
    {
        var key = (req.ApiKey ?? "").Trim();
        if (key.Length < 20 || key.Length > 300 || !key.StartsWith("sk-ant-") || key.Any(char.IsWhiteSpace))
            return BadRequest(new { message = "Paste the whole API key; it starts with sk-ant-." });
        if (string.IsNullOrEmpty(_secret))
            return BadRequest(new { message = "The server can't store keys safely (no server secret configured)." });

        var problem = await _ai.CheckKeyAsync(key, HttpContext.RequestAborted);
        if (problem != null) return BadRequest(new { message = problem });

        var settings = await _db.CompanySettings.FirstOrDefaultAsync(c => c.Id == CompanySettings.SingletonId)
                       ?? throw new KeyNotFoundException("Company settings not found.");
        settings.AssistantAiKeyEncrypted = SecretBox.Encrypt(key, _secret, KeyPurpose);
        settings.AssistantAiKeyHint = "…" + key[^4..];
        settings.AssistantAiKeySetAt = DateTime.UtcNow;
        settings.AssistantAiEnabled = true;
        settings.UpdatedAt = DateTime.UtcNow;
        await _db.SaveChangesAsync();
        return Ok(new { connected = true, keyHint = settings.AssistantAiKeyHint, enabled = true });
    }

    /// <summary>DELETE /api/assistant/admin/ai/key — removes the company's key (AI goes off unless the server has one).</summary>
    [HttpDelete("admin/ai/key")]
    [Authorize(Roles = "Admin")]
    public async Task<IActionResult> DisconnectKey()
    {
        var settings = await _db.CompanySettings.FirstOrDefaultAsync(c => c.Id == CompanySettings.SingletonId)
                       ?? throw new KeyNotFoundException("Company settings not found.");
        settings.AssistantAiKeyEncrypted = null;
        settings.AssistantAiKeyHint = null;
        settings.AssistantAiKeySetAt = null;
        if (!_ai.HasServerKey) settings.AssistantAiEnabled = false;
        settings.UpdatedAt = DateTime.UtcNow;
        await _db.SaveChangesAsync();
        return Ok(new { enabled = settings.AssistantAiEnabled });
    }

    // ── Admin: manage the questions and answers ──

    /// <summary>GET /api/assistant/admin/faqs — every question (active or not) and the choices for the form.</summary>
    [HttpGet("admin/faqs")]
    [Authorize(Roles = "Admin")]
    public async Task<IActionResult> AdminList()
    {
        var settings = await _settings.GetAsync();
        var faqs = await _db.BotFaqs.AsNoTracking()
            .OrderBy(f => f.Category).ThenBy(f => f.SortOrder).ThenBy(f => f.Id).ToListAsync();
        return Ok(new
        {
            faqs = faqs.Select(f => new
            {
                f.Id, f.Category, f.Question, f.Answer, f.Keywords, f.Audience, f.Action, f.SortOrder, f.IsActive, f.UpdatedAt
            }),
            audiences = BotFaq.Audiences,
            actions = BotActions.All.Where(a => settings.SchoolFeaturesEnabled || !a.School)
                .Select(a => new { a.Key, a.Label, a.Audience }),
            schoolFeatures = settings.SchoolFeaturesEnabled,
            unansweredCount = await _db.BotUnansweredQuestions.CountAsync()
        });
    }

    [HttpPost("admin/faqs")]
    [Authorize(Roles = "Admin")]
    public async Task<IActionResult> Create([FromBody] BotFaqRequest req)
    {
        var error = Validate(req);
        if (error != null) return BadRequest(new { message = error });
        var faq = new BotFaq();
        Apply(faq, req);
        if (req.SortOrder == null)
            faq.SortOrder = (await _db.BotFaqs.Where(f => f.Category == faq.Category).MaxAsync(f => (int?)f.SortOrder) ?? 0) + 10;
        _db.BotFaqs.Add(faq);
        await _db.SaveChangesAsync();
        return Ok(new { faq.Id });
    }

    [HttpPut("admin/faqs/{id:int}")]
    [Authorize(Roles = "Admin")]
    public async Task<IActionResult> Update(int id, [FromBody] BotFaqRequest req)
    {
        var faq = await _db.BotFaqs.FirstOrDefaultAsync(f => f.Id == id) ?? throw new KeyNotFoundException("Question not found.");
        var error = Validate(req);
        if (error != null) return BadRequest(new { message = error });
        Apply(faq, req);
        faq.UpdatedAt = DateTime.UtcNow;
        await _db.SaveChangesAsync();
        return NoContent();
    }

    [HttpDelete("admin/faqs/{id:int}")]
    [Authorize(Roles = "Admin")]
    public async Task<IActionResult> Delete(int id)
    {
        var faq = await _db.BotFaqs.FirstOrDefaultAsync(f => f.Id == id) ?? throw new KeyNotFoundException("Question not found.");
        _db.BotFaqs.Remove(faq);
        await _db.SaveChangesAsync();
        return NoContent();
    }

    /// <summary>
    /// POST /api/assistant/admin/faqs/starter — adds the ready-made questions that aren't there yet
    /// (same question text), so it's safe to press twice.
    /// </summary>
    [HttpPost("admin/faqs/starter")]
    [Authorize(Roles = "Admin")]
    public async Task<IActionResult> AddStarter()
    {
        var settings = await _settings.GetAsync();
        var existing = (await _db.BotFaqs.Select(f => f.Question).ToListAsync())
            .Select(q => q.Trim().ToLowerInvariant()).ToHashSet();
        var added = 0;
        foreach (var f in BotStarterFaqs.For(settings.SchoolFeaturesEnabled))
        {
            if (existing.Contains(f.Question.Trim().ToLowerInvariant())) continue;
            _db.BotFaqs.Add(f);
            added++;
        }
        await _db.SaveChangesAsync();
        return Ok(new { added });
    }

    /// <summary>GET /api/assistant/admin/unanswered — questions the bot couldn't answer, newest first.</summary>
    [HttpGet("admin/unanswered")]
    [Authorize(Roles = "Admin")]
    public async Task<IActionResult> Unanswered()
    {
        var rows = await _db.BotUnansweredQuestions.AsNoTracking()
            .OrderByDescending(u => u.AskedAt).Take(300)
            .Select(u => new { u.Id, u.Text, u.Audience, u.AskedAt })
            .ToListAsync();
        return Ok(rows);
    }

    [HttpDelete("admin/unanswered/{id:int}")]
    [Authorize(Roles = "Admin")]
    public async Task<IActionResult> DeleteUnanswered(int id)
    {
        await _db.BotUnansweredQuestions.Where(u => u.Id == id).ExecuteDeleteAsync();
        return NoContent();
    }

    [HttpDelete("admin/unanswered")]
    [Authorize(Roles = "Admin")]
    public async Task<IActionResult> ClearUnanswered()
    {
        await _db.BotUnansweredQuestions.ExecuteDeleteAsync();
        return NoContent();
    }

    // ── helpers ──

    private sealed record Viewer(int UserId, string Name, bool IsAdmin, bool IsParent, bool School, bool IsTeacher = false)
    {
        /// <summary>Audience used for the unanswered log.</summary>
        public string Audience => IsParent ? BotFaq.ForParents : BotFaq.ForEmployees;
    }

    private async Task<Viewer?> MeAsync()
    {
        if (!int.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out var userId)) return null;
        var user = await _db.Users.AsNoTracking().Where(u => u.Id == userId && u.IsActive)
            .Select(u => new { u.Id, u.Username, u.Email, u.Role }).FirstOrDefaultAsync();
        if (user == null) return null;
        var settings = await _settings.GetAsync();

        string name;
        var isParent = user.Role == SchoolViewer.ParentRole;
        var isTeacher = false;
        if (isParent)
            name = await _db.Parents.Where(p => p.UserId == user.Id).Select(p => p.FullName).FirstOrDefaultAsync() ?? user.Username;
        else
        {
            var email = (user.Email ?? "").ToLower();
            var employee = email.Length == 0 ? null : await _db.Employees.Where(e => e.Email.ToLower() == email && e.IsActive)
                .Select(e => new { e.Id, e.Name }).FirstOrDefaultAsync();
            name = employee?.Name ?? user.Username;
            isTeacher = employee != null && settings.SchoolFeaturesEnabled
                        && await _db.SchoolClasses.AnyAsync(c => c.ClassTeacherId == employee.Id && c.IsActive);
        }
        return new Viewer(user.Id, name, user.Role == "Admin", isParent, settings.SchoolFeaturesEnabled, isTeacher);
    }

    /// <summary>Active answers this login may see. Parent answers only while the school features are on.</summary>
    private IQueryable<BotFaq> Visible(Viewer me)
    {
        var q = _db.BotFaqs.AsNoTracking().Where(f => f.IsActive);
        if (!me.School) q = q.Where(f => f.Audience != BotFaq.ForParents);
        if (me.IsAdmin) return q;
        var mine = me.IsParent ? BotFaq.ForParents : BotFaq.ForEmployees;
        return q.Where(f => f.Audience == BotFaq.ForAll || f.Audience == mine);
    }

    /// <summary>
    /// Page links this login can open. Admins have no self-service pages in the apps, so they only
    /// get the shared ones; parent pages need the school features.
    /// </summary>
    private static IEnumerable<BotActions.ActionInfo> ActionsFor(Viewer me) => BotActions.All.Where(a =>
        (!a.School || me.School) && (
            a.Audience == BotFaq.ForAll
            || (a.Audience == BotFaq.ForParents && me.IsParent)
            || (a.Audience == BotFaq.ForEmployees && !me.IsParent && !me.IsAdmin)
            || (a.Audience == BotActions.ForAdmins && me.IsAdmin)
            // Staff pages: admins, and class teachers (who don't get the admin-only "Children" list)
            || (a.Audience == BotActions.ForStaff && (me.IsAdmin || me.IsTeacher) && !(a.Key == "my-class" && me.IsAdmin && !me.IsTeacher))));

    private static object ToDto(BotFaq f, Viewer me, CompanySettings settings)
    {
        var action = f.Action == null ? null : ActionsFor(me).FirstOrDefault(a => a.Key == f.Action);
        return new
        {
            f.Id,
            question = Fill(f.Question, settings),
            answer = Fill(f.Answer, settings),
            action = action == null ? null : new { action.Key, action.Label }
        };
    }

    private static string CompanyName(CompanySettings s) =>
        !string.IsNullOrWhiteSpace(s.DisplayName) ? s.DisplayName
        : !string.IsNullOrWhiteSpace(s.LegalName) ? s.LegalName : "company";

    /// <summary>Fills {company}, {phone} and {feeDueDay} from Company Settings.</summary>
    private static string Fill(string text, CompanySettings s) => text
        .Replace("{company}", CompanyName(s), StringComparison.OrdinalIgnoreCase)
        .Replace("{phone}", string.IsNullOrWhiteSpace(s.Phone) ? "the office" : s.Phone, StringComparison.OrdinalIgnoreCase)
        .Replace("{feeDueDay}", s.FeeDueDay.ToString(), StringComparison.OrdinalIgnoreCase);

    /// <summary>
    /// Asks Claude, with tools limited to this user's own data, and logs the usage. Returns the
    /// answer, or why it failed (both null = no answer for another reason, e.g. a refusal).
    /// When AI answers stop or start working again, the admins are told.
    /// </summary>
    private async Task<(AiAnswer? answer, string? error)> AskAiAsync(Viewer me, CompanySettings settings, string text, List<ChatTurnDto>? history)
    {
        var sv = await SchoolViewer.LoadAsync(_db, User);
        if (sv == null) return (null, null);
        var user = new AssistantUser(me.UserId, me.Name, me.IsAdmin, me.IsParent && sv.IsParent, sv.ChildIds,
            sv.EmployeeId, sv.TeacherClassIds, me.School, me.Audience);
        var pages = ActionsFor(me).Select(a => (a.Key, a.Label)).ToList();
        var tools = new AssistantTools(_db, _leave, settings, user, pages);

        var turns = (history ?? new())
            .TakeLast(MaxHistoryTurns)
            .Select(h => new ChatTurn(h.FromUser, (h.Text ?? "").Length > 1000 ? h.Text![..1000] : h.Text ?? ""))
            .ToList();

        var answer = await _ai.AnswerAsync(CompanyKey(settings), tools, await SystemPromptAsync(user, settings), turns, text,
            HttpContext.RequestAborted);
        var previous = await _db.BotAiUsageLog.AsNoTracking()
            .OrderByDescending(u => u.AskedAt).ThenByDescending(u => u.Id).FirstOrDefaultAsync();
        _db.BotAiUsageLog.Add(new BotAiUsage
        {
            UserId = me.UserId, AskedAt = DateTime.UtcNow, Model = _ai.Model,
            InputTokens = answer?.InputTokens ?? 0, OutputTokens = answer?.OutputTokens ?? 0,
            ToolCalls = answer?.ToolCalls ?? 0, Succeeded = answer is { Failed: false },
            // Why it failed, for the admin's Chatbot page ("credit has run out" …)
            Error = answer?.Error
        });
        await _db.SaveChangesAsync();

        if (answer is { Failed: true } && AiErrors.IsBlocking(answer.Error))
            await AlertAdminsAsync(down: true, answer.Error);
        else if (answer is { Failed: false } && previous is { Succeeded: false } && AiErrors.IsBlocking(previous.Error))
            await AlertAdminsAsync(down: false, null);

        return answer is { Failed: false } ? (answer, null) : (null, answer?.Error);
    }

    /// <summary>"AI isn't working: …" for the admin: the newest failure that has no success after it.</summary>
    private static object? LatestProblem(IEnumerable<BotAiUsage> rows)
    {
        var newestFirst = rows.OrderByDescending(r => r.AskedAt).ThenByDescending(r => r.Id).ToList();
        var last = newestFirst.FirstOrDefault();
        if (last == null || last.Succeeded || last.Error == null) return null;
        // Failed questions in a row since the last AI answer that worked
        var failures = newestFirst.TakeWhile(r => !r.Succeeded).Count();
        return new { message = last.Error, at = DateTime.SpecifyKind(last.AskedAt, DateTimeKind.Utc), failures };
    }

    private async Task<bool> UnderDailyAiLimitAsync(Viewer me)
    {
        var since = DateTime.UtcNow.AddDays(-1);
        return await _db.BotAiUsageLog.CountAsync(u => u.UserId == me.UserId && u.AskedAt >= since) < _dailyAiLimit;
    }

    private static readonly string[] PersonalWords =
    {
        "my", "mine", "me", "our", "saya", "aku", "ku", "anak", "today", "yesterday", "tomorrow", "owe", "owing",
        "outstanding", "hari ini", "semalam", "esok"
    };

    /// <summary>Questions about the person's own data go to the AI even when an FAQ answer fits.</summary>
    private async Task<bool> LooksPersonalAsync(Viewer me, string text)
    {
        var words = $" {new string(text.ToLowerInvariant().Select(c => char.IsLetterOrDigit(c) ? c : ' ').ToArray())} ";
        if (PersonalWords.Any(w => words.Contains($" {w} "))) return true;
        if (!me.IsParent || !me.School) return false;
        var sv = await SchoolViewer.LoadAsync(_db, User);
        if (sv == null || sv.ChildIds.Count == 0) return false;
        var names = await _db.Students.Where(s => sv.ChildIds.Contains(s.Id)).Select(s => s.FullName).ToListAsync();
        return names.SelectMany(n => n.ToLowerInvariant().Split(' ', StringSplitOptions.RemoveEmptyEntries))
            .Where(n => n.Length >= 3 && n != "bin" && n != "binti" && n != "a/l" && n != "a/p")
            .Any(n => words.Contains($" {n} "));
    }

    /// <summary>Instructions for Claude: who is asking, today's date, and how to answer.</summary>
    private async Task<string> SystemPromptAsync(AssistantUser u, CompanySettings s)
    {
        var company = CompanyName(s);
        string role;
        if (u.IsParent)
        {
            var kids = await _db.Students.Where(x => u.ChildIds.Contains(x.Id)).Select(x => x.FullName).ToListAsync();
            role = kids.Count == 0 ? "a parent" : $"a parent of {string.Join(", ", kids)}";
        }
        else if (u.IsAdmin) role = "an administrator (school office / HR)";
        else if (u.TeacherClassIds.Count > 0 && u.School)
        {
            var classes = await _db.SchoolClasses.Where(c => u.TeacherClassIds.Contains(c.Id)).Select(c => c.Name).ToListAsync();
            role = $"a class teacher of {string.Join(", ", classes)}";
        }
        else role = "an employee";

        var contact = string.IsNullOrWhiteSpace(s.Phone) ? "the office" : $"the office at {s.Phone}";
        var human = u.IsParent && u.School
            ? $"suggest messaging the school office in the app (Messages) or calling {contact}"
            : $"suggest contacting {contact}";

        return $"""
            You are the help assistant inside the {company} app{(u.School ? ", for a preschool/school" : ", an HR and payroll app")}.
            You are talking to {u.Name}, {role}.
            Today is {SchoolClock.Today:dddd, d MMMM yyyy} (UTC+8, the app's working time zone).

            How to answer:
            - Use the tools to look things up. Never guess numbers, dates, amounts, names or policies; if the tools don't give the answer, say you don't know and {human}.
            - For general questions (hours, rules, how to do something in the app), search the help articles first.
            - Only help with {company} matters and this person's own information. Politely decline anything else.
            - Keep answers short and friendly: 1–4 sentences or a few "•" bullets, plain text, no headings or tables. Show money with the currency the tools give.
            - Reply in the language the person writes in.
            - You can only read information. You can't apply for leave, pay fees, approve, send messages or change anything; say where in the app to do it, and call suggest_page so a button opens that page.
            - When the person asks for a report, list, PDF, Excel or download, call offer_download; a download button appears under your answer. Summarise the key numbers in your reply too.
            - Long lists: give the totals and the first few items, then offer the page or the download for the rest.
            """;
    }

    private async Task LogUnansweredAsync(Viewer me, string text)
    {
        var since = DateTime.UtcNow.AddDays(-1);
        var recent = await _db.BotUnansweredQuestions.Where(u => u.UserId == me.UserId && u.AskedAt >= since)
            .Select(u => u.Text).ToListAsync();
        if (recent.Count >= MaxLoggedPerUserPerDay || recent.Any(t => string.Equals(t, text, StringComparison.OrdinalIgnoreCase))) return;
        _db.BotUnansweredQuestions.Add(new BotUnanswered { Text = text, Audience = me.Audience, UserId = me.UserId, AskedAt = DateTime.UtcNow });
        await _db.SaveChangesAsync();
    }

    private static string? Validate(BotFaqRequest r)
    {
        if (string.IsNullOrWhiteSpace(r.Question)) return "Enter the question.";
        if (string.IsNullOrWhiteSpace(r.Answer)) return "Enter the answer.";
        if (r.Question.Trim().Length > BotFaq.MaxQuestionLength) return $"The question is too long ({BotFaq.MaxQuestionLength} characters at most).";
        if (r.Answer.Trim().Length > BotFaq.MaxAnswerLength) return $"The answer is too long ({BotFaq.MaxAnswerLength} characters at most).";
        if ((r.Keywords ?? "").Trim().Length > BotFaq.MaxKeywordsLength) return $"Too many keywords ({BotFaq.MaxKeywordsLength} characters at most).";
        if ((r.Category ?? "").Trim().Length > BotFaq.MaxCategoryLength) return $"The topic name is too long ({BotFaq.MaxCategoryLength} characters at most).";
        if (!BotFaq.Audiences.Contains(r.Audience)) return "Choose who sees this answer.";
        if (!BotActions.IsValid(string.IsNullOrWhiteSpace(r.Action) ? null : r.Action)) return "Unknown page link.";
        return null;
    }

    private static void Apply(BotFaq f, BotFaqRequest r)
    {
        f.Category = string.IsNullOrWhiteSpace(r.Category) ? "General" : r.Category.Trim();
        f.Question = r.Question!.Trim();
        f.Answer = r.Answer!.Trim();
        f.Keywords = string.IsNullOrWhiteSpace(r.Keywords) ? null : r.Keywords.Trim();
        f.Audience = r.Audience;
        f.Action = string.IsNullOrWhiteSpace(r.Action) ? null : r.Action;
        if (r.SortOrder != null) f.SortOrder = r.SortOrder.Value;
        f.IsActive = r.IsActive;
    }
}

/// <summary>
/// A note for the top of the chat about AI answers. <c>level</c>: "error" (admins: stopped, with the
/// fix), "warning" (admins: one failed answer), "info" (everyone else: paused / list answer).
/// </summary>
public sealed record AiNotice(string Level, string Message, string? Link, string? LinkLabel);

public class AskRequest
{
    public string? Text { get; set; }
    /// <summary>Earlier turns of this chat (text only, oldest first), so the AI can follow up.</summary>
    public List<ChatTurnDto>? History { get; set; }
}

public class ChatTurnDto
{
    public bool FromUser { get; set; }
    public string? Text { get; set; }
}

public class AiSettingsRequest
{
    public bool Enabled { get; set; }
}

public class AiKeyRequest
{
    public string? ApiKey { get; set; }
}

public class BotFaqRequest
{
    public string? Category { get; set; }
    public string? Question { get; set; }
    public string? Answer { get; set; }
    public string? Keywords { get; set; }
    public string Audience { get; set; } = BotFaq.ForAll;
    public string? Action { get; set; }
    public int? SortOrder { get; set; }
    public bool IsActive { get; set; } = true;
}
