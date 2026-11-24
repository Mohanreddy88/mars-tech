using HrmsApi.Data;
using HrmsApi.Models;
using HrmsApi.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Net.Http.Headers;

namespace HrmsApi.Controllers;

/// <summary>
/// School → Banners: advert-style slides at the top of the parent home (website and app).
///   Admins: list, add, change, switch off, reorder and delete banners.
///   Parents: the banners live today for the whole school or their children's classes.
/// </summary>
[ApiController]
[Route("api/school/banners")]
[Authorize]
[RequiresSchoolFeatures]
public class BannersController : ControllerBase
{
    private readonly HrmsDbContext _db;
    private readonly IAuditService _audit;
    private readonly ICompanySettingsService _settings;

    public BannersController(HrmsDbContext db, IAuditService audit, ICompanySettingsService settings)
    {
        _db = db; _audit = audit; _settings = settings;
    }

    /// <summary>Largest picture accepted.</summary>
    public const int MaxImageBytes = 3 * 1024 * 1024;

    /// <summary>GET /api/school/banners — every banner in slide order, with its status (admins).</summary>
    [HttpGet]
    public async Task<IActionResult> GetAll()
    {
        var me = await SchoolViewer.LoadAsync(_db, User);
        if (me is not { IsAdmin: true }) return Forbid();
        var today = SchoolClock.Today;
        var list = await _db.SchoolBanners.AsNoTracking().OrderBy(b => b.SortOrder).ThenBy(b => b.Id)
            .Select(b => new
            {
                b.Id, b.Title, b.Text, b.ButtonText, b.Link, b.Theme, b.ClassId, b.StartsOn, b.EndsOn, b.IsActive,
                b.SortOrder, b.CreatedByName, b.UpdatedAt,
                className    = b.Class != null ? b.Class.Name : null,
                imageVersion = b.ImageData != null ? b.ImageVersion : (int?)null
            }).ToListAsync();
        return Ok(list.Select(b => new
        {
            b.Id, b.Title, b.Text, b.ButtonText, b.Link, b.Theme, b.ClassId, b.className,
            b.StartsOn, b.EndsOn, b.IsActive, b.SortOrder, b.CreatedByName, b.UpdatedAt, b.imageVersion,
            status = Status(b.IsActive, b.StartsOn, b.EndsOn, today)
        }));
    }

    /// <summary>GET /api/school/banners/current — the banners a parent sees today, in slide order.</summary>
    [HttpGet("current")]
    public async Task<IActionResult> Current()
    {
        var me = await SchoolViewer.LoadAsync(_db, User);
        if (me == null) return Forbid();
        if (!me.IsParent) return Ok(Array.Empty<object>());
        var today = SchoolClock.Today;
        var list = await ForParent(me)
            .Where(b => b.IsActive && (b.StartsOn == null || b.StartsOn <= today) && (b.EndsOn == null || b.EndsOn >= today))
            .OrderBy(b => b.SortOrder).ThenBy(b => b.Id)
            .Select(b => new ParentSlide(b.Id, b.Title, b.Text, b.ButtonText, b.Link, b.Theme,
                b.ImageData != null ? b.ImageVersion : null, false))
            .ToListAsync();
        list.AddRange(await AutomaticSlidesAsync(me, today, schoolBanners: list.Count));
        return Ok(list);
    }

    /// <summary>
    /// Slides made from the parent's own data, after the school's banners: fees due, new
    /// announcements, the next public holiday — or a welcome card when there's nothing else.
    /// Negative ids (they have no picture and can't be edited).
    /// </summary>
    private async Task<List<ParentSlide>> AutomaticSlidesAsync(SchoolViewer me, DateTime today, int schoolBanners)
    {
        var slides = new List<ParentSlide>();

        var due = (await _db.FeeInvoices.AsNoTracking()
                .Where(i => me.ChildIds.Contains(i.StudentId) && i.SentAt != null && i.Status != FeeInvoice.Void && i.Status != FeeInvoice.Paid)
                .Select(i => new { i.Total, i.AmountPaid, i.DueDate }).ToListAsync())
            .Where(i => i.Total > i.AmountPaid).ToList();
        if (due.Count > 0)
        {
            var amount = due.Sum(i => i.Total - i.AmountPaid);
            var overdue = due.Any(i => i.DueDate.Date < today);
            slides.Add(new(-1, $"RM {amount:#,##0.00} school fees {(overdue ? "overdue" : "due")}",
                overdue ? "Please settle the overdue fees — tap to see the invoices and pay."
                        : $"Due by {due.Min(i => i.DueDate):d MMM}. Tap to see the invoice and tell us when you've paid.",
                "Pay now", "fees", overdue ? "pink" : "orange", null, true));
        }

        var classIds = _db.Students.Where(s => me.ChildIds.Contains(s.Id) && s.ClassId != null).Select(s => s.ClassId!.Value);
        var news = await _db.Announcements.AsNoTracking()
            .Where(a => (a.ClassId == null || classIds.Contains(a.ClassId.Value))
                && !_db.AnnouncementReads.Any(r => r.AnnouncementId == a.Id && r.UserId == me.UserId))
            .OrderByDescending(a => a.CreatedAt).Select(a => a.Title).ToListAsync();
        if (news.Count > 0)
            slides.Add(new(-2, news.Count == 1 ? "New from the school" : $"{news.Count} new announcements",
                news.Count == 1 ? news[0] : $"Latest: {news[0]}", "Read", "announcements", "blue", null, true));

        var holiday = await _db.PublicHolidays.AsNoTracking()
            .Where(h => h.Date >= today && h.Date <= today.AddDays(30)).OrderBy(h => h.Date).FirstOrDefaultAsync();
        if (holiday != null)
        {
            var days = (holiday.Date.Date - today).Days;
            slides.Add(new(-3, $"School closed: {holiday.Name}",
                $"{holiday.Date:dddd d MMMM}" + (days == 0 ? " · today" : days == 1 ? " · tomorrow" : $" · in {days} days"),
                null, null, "green", null, true));
        }

        // ── Each child: today at school, and their class teacher ──
        var children = await _db.Students.AsNoTracking().Where(s => me.ChildIds.Contains(s.Id) && s.IsActive)
            .OrderBy(s => s.FullName)
            .Select(s => new
            {
                s.Id, s.FullName,
                className = s.Class != null ? s.Class.Name : null,
                teacher = s.Class != null && s.Class.ClassTeacher != null ? s.Class.ClassTeacher.Name : null,
                att = _db.StudentAttendance.Where(a => a.StudentId == s.Id && a.Date == today)
                    .Select(a => new { a.Status, a.CheckInAt, a.CheckOutAt, a.PickedUpBy }).FirstOrDefault()
            }).ToListAsync();
        var n = 0;
        foreach (var c in children.Take(3))
        {
            var first = c.FullName.Split(' ', StringSplitOptions.RemoveEmptyEntries).FirstOrDefault() ?? c.FullName;
            if (c.att is { CheckOutAt: not null })
                slides.Add(new(-20 - n, $"{first} went home at {SchoolClock.LocalTime(c.att.CheckOutAt.Value)}",
                    c.att.PickedUpBy != null ? $"Picked up by {c.att.PickedUpBy}. See today's report — meals, nap and photos." : "See today's report — meals, nap and photos.",
                    null, null, "green", null, true));
            else if (c.att is { Status: StudentAttendance.Present, CheckInAt: not null })
                slides.Add(new(-20 - n, $"{first} is at school today",
                    $"Checked in at {SchoolClock.LocalTime(c.att.CheckInAt.Value)}. Look out for the daily report and photos.",
                    null, null, "green", null, true));
            if (c.teacher != null)
                slides.Add(new(-30 - n, $"Meet {c.teacher}",
                    $"{first}'s class teacher{(c.className != null ? $" in {c.className}" : "")}. Questions about the day? Just ask.",
                    "Message the teacher", "new-message", "purple", null, true));
            n++;
        }

        // ── The school: price list and (until the school makes its own banners) what a day looks like ──
        var prices = await FeePrices.ForDateAsync(_db, today);
        var offered = prices?.Sessions.Where(s => s.Offered && s.MonthlyFee > 0).OrderBy(s => s.MonthlyFee).ToList() ?? new();
        if (prices != null && offered.Count > 0)
            slides.Add(new(-5, $"Price & Terms {prices.Name}",
                string.Join(" · ", offered.Select(s => $"{s.SessionType} RM {s.MonthlyFee:#,##0} a month")) + ". Meals included.",
                "See prices", "fees", "teal", null, true));

        if (schoolBanners == 0)
        {
            var meals = offered.Select(s => s.MealsIncluded).LastOrDefault(m => !string.IsNullOrWhiteSpace(m));
            slides.AddRange(SchoolShowcase(meals).Select((s, i) => s with { Id = -40 - i }));
        }

        if (slides.Count == 0 && schoolBanners == 0)
        {
            var school = (await _settings.GetAsync()).NameForDisplay;
            slides.Add(new(-4, $"Welcome to {school}", "Your child's day, messages and fees — all in one place.",
                "Message the school", "new-message", "purple", null, true));
        }
        return slides;
    }

    /// <summary>
    /// General cards about life at the school: shown to parents until the school adds its own
    /// banners, and the "sample banners" an admin can add and then change (and add photos to).
    /// </summary>
    public static List<ParentSlide> SchoolShowcase(string? meals) => new()
    {
        new(0, "A day full of learning", "Circle time, hands-on activities, art, music and story time — every day.",
            null, null, "orange", null, true),
        new(0, "Safe, happy play areas", "Indoor and outdoor play spaces where children explore, climb and make friends.",
            null, null, "pink", null, true),
        new(0, "Healthy meals every day", string.IsNullOrWhiteSpace(meals)
                ? "Freshly prepared, balanced meals and snacks."
                : $"Freshly prepared {meals} — balanced and child-friendly.",
            null, null, "blue", null, true),
        new(0, "Caring, qualified teachers", "Small classes and teachers who know every child by name.",
            "Message the school", "new-message", "purple", null, true),
    };

    /// <summary>POST /api/school/banners/samples — adds the general school cards as banners to edit (admins).</summary>
    [HttpPost("samples")]
    public async Task<IActionResult> AddSamples()
    {
        var me = await SchoolViewer.LoadAsync(_db, User);
        if (me is not { IsAdmin: true }) return Forbid();
        var prices = await FeePrices.ForDateAsync(_db, SchoolClock.Today);
        var meals = prices?.Sessions.Where(s => s.Offered && !string.IsNullOrWhiteSpace(s.MealsIncluded))
            .OrderBy(s => s.MonthlyFee).Select(s => s.MealsIncluded).LastOrDefault();
        var existing = await _db.SchoolBanners.Select(b => b.Title).ToListAsync();
        var order = await _db.SchoolBanners.MaxAsync(b => (int?)b.SortOrder) ?? 0;
        var added = 0;
        foreach (var s in SchoolShowcase(meals).Where(s => !existing.Contains(s.Title)))
        {
            _db.SchoolBanners.Add(new SchoolBanner
            {
                Title = s.Title, Text = s.Text, ButtonText = s.ButtonText, Link = s.Link, Theme = s.Theme,
                SortOrder = ++order, CreatedByName = me.Name
            });
            added++;
        }
        await _db.SaveChangesAsync();
        if (added > 0) await LogAsync(me, "Created", 0, $"Added {added} sample banners");
        return Ok(new { added });
    }

    /// <summary>GET /api/school/banners/{id}/image?v= — the picture (admins, and parents the banner is for).</summary>
    [HttpGet("{id:int}/image")]
    public async Task<IActionResult> Image(int id)
    {
        var me = await SchoolViewer.LoadAsync(_db, User);
        if (me == null || !(me.IsAdmin || me.IsParent)) return Forbid();
        var q = me.IsAdmin ? _db.SchoolBanners.AsNoTracking() : ForParent(me);
        var img = await q.Where(b => b.Id == id).Select(b => new { b.ImageContentType, b.ImageData }).FirstOrDefaultAsync();
        if (img?.ImageData == null) throw new KeyNotFoundException("No picture.");
        // The address carries the picture's version, so it may be kept by the browser / app
        Response.Headers[HeaderNames.CacheControl] = "private, max-age=86400";
        Response.Headers["X-Content-Type-Options"] = "nosniff";
        return File(img.ImageData, img.ImageContentType ?? "image/jpeg");
    }

    /// <summary>POST /api/school/banners (multipart) — a new banner, shown last (admins).</summary>
    [HttpPost]
    [RequestSizeLimit(MaxImageBytes + 256 * 1024)]
    public async Task<IActionResult> Create([FromForm] BannerForm form)
    {
        var me = await SchoolViewer.LoadAsync(_db, User);
        if (me is not { IsAdmin: true }) return Forbid();
        var b = new SchoolBanner { CreatedByName = me.Name, CreatedAt = DateTime.UtcNow };
        var error = await ApplyAsync(b, form);
        if (error != null) return error;
        b.SortOrder = (await _db.SchoolBanners.MaxAsync(x => (int?)x.SortOrder) ?? 0) + 1;
        _db.SchoolBanners.Add(b);
        await _db.SaveChangesAsync();
        await LogAsync(me, "Created", b.Id, $"Added banner \"{b.Title}\"");
        return Ok(new { b.Id });
    }

    /// <summary>PUT /api/school/banners/{id} (multipart) — change a banner; removeImage drops the picture (admins).</summary>
    [HttpPut("{id:int}")]
    [RequestSizeLimit(MaxImageBytes + 256 * 1024)]
    public async Task<IActionResult> Update(int id, [FromForm] BannerForm form)
    {
        var me = await SchoolViewer.LoadAsync(_db, User);
        if (me is not { IsAdmin: true }) return Forbid();
        var b = await _db.SchoolBanners.FindAsync(id) ?? throw new KeyNotFoundException("Banner not found.");
        var error = await ApplyAsync(b, form);
        if (error != null) return error;
        await _db.SaveChangesAsync();
        await LogAsync(me, "Updated", b.Id, $"Changed banner \"{b.Title}\"");
        return NoContent();
    }

    /// <summary>POST /api/school/banners/{id}/move?up=true — one place earlier (up) or later in the slides (admins).</summary>
    [HttpPost("{id:int}/move")]
    public async Task<IActionResult> Move(int id, [FromQuery] bool up)
    {
        var me = await SchoolViewer.LoadAsync(_db, User);
        if (me is not { IsAdmin: true }) return Forbid();
        var all = await _db.SchoolBanners.OrderBy(b => b.SortOrder).ThenBy(b => b.Id).ToListAsync();
        var i = all.FindIndex(b => b.Id == id);
        if (i < 0) throw new KeyNotFoundException("Banner not found.");
        var j = up ? i - 1 : i + 1;
        if (j < 0 || j >= all.Count) return NoContent();
        (all[i], all[j]) = (all[j], all[i]);
        for (var k = 0; k < all.Count; k++) all[k].SortOrder = k + 1;
        await _db.SaveChangesAsync();
        return NoContent();
    }

    /// <summary>DELETE /api/school/banners/{id} (admins).</summary>
    [HttpDelete("{id:int}")]
    public async Task<IActionResult> Delete(int id)
    {
        var me = await SchoolViewer.LoadAsync(_db, User);
        if (me is not { IsAdmin: true }) return Forbid();
        var b = await _db.SchoolBanners.FindAsync(id) ?? throw new KeyNotFoundException("Banner not found.");
        _db.SchoolBanners.Remove(b);
        await _db.SaveChangesAsync();
        await LogAsync(me, "Deleted", id, $"Deleted banner \"{b.Title}\"");
        return NoContent();
    }

    // ── helpers ──

    /// <summary>"Live", "Scheduled" (starts later), "Ended" or "Off".</summary>
    public static string Status(bool active, DateTime? starts, DateTime? ends, DateTime today) =>
        !active ? "Off" : starts != null && starts.Value.Date > today ? "Scheduled" : ends != null && ends.Value.Date < today ? "Ended" : "Live";

    /// <summary>Whole-school banners and the ones for the parent's children's classes.</summary>
    private IQueryable<SchoolBanner> ForParent(SchoolViewer me)
    {
        var classIds = _db.Students.Where(s => me.ChildIds.Contains(s.Id) && s.ClassId != null).Select(s => s.ClassId!.Value);
        return _db.SchoolBanners.AsNoTracking().Where(b => b.ClassId == null || classIds.Contains(b.ClassId.Value));
    }

    /// <summary>Checks the form and copies it onto the banner; a 400 result when something is wrong.</summary>
    private async Task<IActionResult?> ApplyAsync(SchoolBanner b, BannerForm f)
    {
        IActionResult Bad(string message, string field) => BadRequest(new { message, field });

        var title = (f.Title ?? "").Trim();
        var text = string.IsNullOrWhiteSpace(f.Text) ? null : f.Text.Trim();
        var button = string.IsNullOrWhiteSpace(f.ButtonText) ? null : f.ButtonText.Trim();
        var link = string.IsNullOrWhiteSpace(f.Link) ? null : f.Link.Trim();
        var theme = string.IsNullOrWhiteSpace(f.Theme) ? "purple" : f.Theme.Trim().ToLowerInvariant();

        if (title.Length == 0) return Bad("Enter a headline.", "title");
        if (title.Length > SchoolBanner.MaxTitle) return Bad($"Keep the headline under {SchoolBanner.MaxTitle} characters.", "title");
        if (text?.Length > SchoolBanner.MaxText) return Bad($"Keep the text under {SchoolBanner.MaxText} characters.", "text");
        if (button?.Length > SchoolBanner.MaxButton) return Bad($"Keep the button under {SchoolBanner.MaxButton} characters.", "buttonText");
        if (link != null && (link.Length > SchoolBanner.MaxLink || !SchoolBanner.IsValidLink(link)))
            return Bad("The button must open a parent page or a web address starting with https://.", "link");
        if (button != null && link == null) return Bad("Choose what the button opens.", "link");
        if (!SchoolBanner.Themes.Contains(theme)) return Bad("Choose a colour.", "theme");
        if (f.StartsOn != null && f.EndsOn != null && f.EndsOn.Value.Date < f.StartsOn.Value.Date)
            return Bad("The end date is before the start date.", "endsOn");
        if (f.ClassId != null && !await _db.SchoolClasses.AnyAsync(c => c.Id == f.ClassId))
            return Bad("Choose a class.", "classId");

        if (f.Image is { Length: > 0 })
        {
            if (f.Image.Length > MaxImageBytes) return Bad("The picture must be 3 MB or smaller.", "image");
            using var ms = new MemoryStream();
            await f.Image.CopyToAsync(ms);
            var bytes = ms.ToArray();
            var type = LeaveAttachment.DetectType(bytes);
            if (type is not ("image/jpeg" or "image/png")) return Bad("The picture must be a JPG or PNG.", "image");
            b.ImageData = bytes;
            b.ImageContentType = type;
            b.ImageVersion++;
        }
        else if (f.RemoveImage)
        {
            b.ImageData = null;
            b.ImageContentType = null;
        }

        b.Title = title;
        b.Text = text;
        b.ButtonText = link == null ? null : button ?? "Find out more";
        b.Link = link;
        b.Theme = theme;
        b.ClassId = f.ClassId;
        b.StartsOn = f.StartsOn?.Date;
        b.EndsOn = f.EndsOn?.Date;
        b.IsActive = f.IsActive;
        b.UpdatedAt = DateTime.UtcNow;
        return null;
    }

    private Task LogAsync(SchoolViewer me, string action, int id, string text) =>
        _audit.LogAsync(action, "SchoolBanner", id.ToString(), text, User.Identity?.Name ?? "unknown", me.UserId,
            null, null, HttpContext.Connection.RemoteIpAddress?.ToString());
}

/// <summary>A slide on the parent home: a school banner, or (<c>Automatic</c>) one made from the parent's data.</summary>
public sealed record ParentSlide(int Id, string Title, string? Text, string? ButtonText, string? Link, string Theme,
    int? ImageVersion, bool Automatic);

public class BannerForm
{
    public string? Title { get; set; }
    public string? Text { get; set; }
    public string? ButtonText { get; set; }
    public string? Link { get; set; }
    public string? Theme { get; set; }
    public int? ClassId { get; set; }
    public DateTime? StartsOn { get; set; }
    public DateTime? EndsOn { get; set; }
    public bool IsActive { get; set; } = true;
    public IFormFile? Image { get; set; }
    public bool RemoveImage { get; set; }
}
