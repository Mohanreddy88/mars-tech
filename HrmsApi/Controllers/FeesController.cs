using System.ComponentModel.DataAnnotations;
using System.Globalization;
using HrmsApi.Data;
using HrmsApi.Hubs;
using HrmsApi.Models;
using HrmsApi.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace HrmsApi.Controllers;

/// <summary>
/// School phase 4 — monthly fees.
///   Admins: fee items (session fees, add-ons), which children take which add-on, fee settings,
///   generate a month's invoices (session fee + add-ons − sibling discount), edit / void, send to
///   parents, record payments (receipts), reminders, PDFs.
///   Parents: their children's invoices once sent, and the PDFs.
/// </summary>
[ApiController]
[Route("api/school/fees")]
[Authorize]
[RequiresSchoolFeatures]
public class FeesController : ControllerBase
{
    private readonly HrmsDbContext _db;
    private readonly ICompanySettingsService _settings;
    private readonly IChatNotifier _live;
    private readonly IPushService _push;
    private readonly IAuditService _audit;

    private static readonly CultureInfo Money = CultureInfo.InvariantCulture;

    private readonly IEmailQueue? _email;

    public FeesController(HrmsDbContext db, ICompanySettingsService settings, IChatNotifier live, IPushService push,
        IAuditService audit, IEmailQueue? email = null)
    {
        _db = db; _settings = settings; _live = live; _push = push; _audit = audit; _email = email;
    }

    // ════════════════════════════ Fee items ════════════════════════════

    [HttpGet("items")]
    [Authorize(Roles = UserAccess.Admin)]
    public async Task<IActionResult> GetItems() =>
        Ok(await _db.FeeItems.AsNoTracking().OrderBy(i => i.Kind).ThenBy(i => i.SortOrder).ThenBy(i => i.Name)
            .Select(i => new
            {
                i.Id, i.Name, i.Kind, i.SessionType, i.Amount, i.SortOrder, i.IsActive,
                children = i.Kind == FeeItem.AddOn
                    ? _db.StudentFeeAddOns.Count(a => a.FeeItemId == i.Id && a.Student.IsActive)
                    : _db.Students.Count(s => s.IsActive && s.SessionType == i.SessionType)
            }).ToListAsync());

    [HttpPost("items")]
    [Authorize(Roles = UserAccess.Admin)]
    public async Task<IActionResult> CreateItem([FromBody] FeeItemRequest req)
    {
        var error = await ValidateItemAsync(req, null);
        if (error != null) return BadRequest(error);
        var item = new FeeItem();
        ApplyItem(item, req);
        _db.FeeItems.Add(item);
        await _db.SaveChangesAsync();
        await Audit("Created", "FeeItem", item.Id, $"Added fee item {item.Name} ({Rm(item.Amount)})");
        return Ok(new { item.Id });
    }

    [HttpPut("items/{id:int}")]
    [Authorize(Roles = UserAccess.Admin)]
    public async Task<IActionResult> UpdateItem(int id, [FromBody] FeeItemRequest req)
    {
        var item = await _db.FeeItems.FindAsync(id) ?? throw new KeyNotFoundException("Fee item not found.");
        var error = await ValidateItemAsync(req, id);
        if (error != null) return BadRequest(error);
        var old = Rm(item.Amount);
        ApplyItem(item, req);
        await _db.SaveChangesAsync();
        await Audit("Updated", "FeeItem", item.Id, $"Updated fee item {item.Name} ({old} → {Rm(item.Amount)})");
        return Ok(new { item.Id });
    }

    /// <summary>DELETE /api/school/fees/items/{id} — invoices already made keep their lines.</summary>
    [HttpDelete("items/{id:int}")]
    [Authorize(Roles = UserAccess.Admin)]
    public async Task<IActionResult> DeleteItem(int id)
    {
        var item = await _db.FeeItems.FindAsync(id) ?? throw new KeyNotFoundException("Fee item not found.");
        _db.FeeItems.Remove(item);
        await _db.SaveChangesAsync();
        await Audit("Deleted", "FeeItem", id, $"Deleted fee item {item.Name}");
        return NoContent();
    }

    // ════════════════════════════ Add-ons per child ════════════════════════════

    /// <summary>GET /api/school/fees/addons — active children and the add-ons they take.</summary>
    [HttpGet("addons")]
    [Authorize(Roles = UserAccess.Admin)]
    public async Task<IActionResult> GetAddOns()
    {
        var items = await _db.FeeItems.AsNoTracking().Where(i => i.Kind == FeeItem.AddOn)
            .OrderBy(i => i.SortOrder).ThenBy(i => i.Name)
            .Select(i => new { i.Id, i.Name, i.Amount, i.IsActive }).ToListAsync();
        var children = await _db.Students.AsNoTracking().Where(s => s.IsActive)
            .OrderBy(s => s.Class != null ? s.Class.SortOrder : int.MaxValue).ThenBy(s => s.FullName)
            .Select(s => new
            {
                s.Id, s.FullName, s.SessionType,
                className = s.Class != null ? s.Class.Name : null,
                addOnIds = _db.StudentFeeAddOns.Where(a => a.StudentId == s.Id).Select(a => a.FeeItemId).ToList()
            }).ToListAsync();
        return Ok(new { items, children });
    }

    /// <summary>PUT /api/school/fees/addons/{studentId} — exactly these add-ons for the child (from next invoice).</summary>
    [HttpPut("addons/{studentId:int}")]
    [Authorize(Roles = UserAccess.Admin)]
    public async Task<IActionResult> SetAddOns(int studentId, [FromBody] AddOnsRequest req)
    {
        if (!await _db.Students.AnyAsync(s => s.Id == studentId)) throw new KeyNotFoundException("Child not found.");
        var wanted = req.FeeItemIds?.Distinct().ToHashSet() ?? new();
        if (wanted.Count > 0 && await _db.FeeItems.CountAsync(i => wanted.Contains(i.Id) && i.Kind == FeeItem.AddOn) != wanted.Count)
            return BadRequest(new { message = "One of the add-ons no longer exists. Reload the page." });
        var links = await _db.StudentFeeAddOns.Where(a => a.StudentId == studentId).ToListAsync();
        _db.StudentFeeAddOns.RemoveRange(links.Where(l => !wanted.Contains(l.FeeItemId)));
        foreach (var id in wanted.Where(w => links.All(l => l.FeeItemId != w)))
            _db.StudentFeeAddOns.Add(new StudentFeeAddOn { StudentId = studentId, FeeItemId = id });
        await _db.SaveChangesAsync();
        return NoContent();
    }

    // ════════════════════════════ Settings ════════════════════════════

    [HttpGet("settings")]
    [Authorize(Roles = UserAccess.Admin)]
    public async Task<IActionResult> GetSettings()
    {
        var s = await _settings.GetAsync();
        return Ok(new { s.SiblingDiscountPercent, s.FeeDueDay, s.FeePaymentInstructions });
    }

    [HttpPut("settings")]
    [Authorize(Roles = UserAccess.Admin)]
    public async Task<IActionResult> SaveSettings([FromBody] FeeSettingsRequest req)
    {
        if (req.SiblingDiscountPercent is < 0 or > 100) return BadRequest(new { message = "The sibling discount must be between 0 and 100%.", field = "siblingDiscountPercent" });
        if (req.FeeDueDay is < 1 or > 28) return BadRequest(new { message = "The due day must be between 1 and 28.", field = "feeDueDay" });
        var s = await _db.CompanySettings.FirstOrDefaultAsync(x => x.Id == CompanySettings.SingletonId)
                ?? throw new KeyNotFoundException("Company settings not found.");
        s.SiblingDiscountPercent = Math.Round(req.SiblingDiscountPercent, 2);
        s.FeeDueDay = req.FeeDueDay;
        s.FeePaymentInstructions = string.IsNullOrWhiteSpace(req.FeePaymentInstructions) ? null : req.FeePaymentInstructions.Trim();
        s.UpdatedAt = DateTime.UtcNow;
        await _db.SaveChangesAsync();
        await Audit("Updated", "FeeSettings", 1, $"Fee settings: sibling discount {s.SiblingDiscountPercent}%, due day {s.FeeDueDay}");
        return NoContent();
    }

    // ════════════════════════════ Invoices ════════════════════════════

    /// <summary>GET /api/school/fees/invoices?year=&amp;month=&amp;status=&amp;classId= — a month's invoices with totals.</summary>
    [HttpGet("invoices")]
    [Authorize(Roles = UserAccess.Admin)]
    public async Task<IActionResult> GetInvoices([FromQuery] int year, [FromQuery] int month, [FromQuery] string? status, [FromQuery] int? classId)
    {
        var today = SchoolClock.Today;
        var q = _db.FeeInvoices.AsNoTracking().Where(i => i.Year == year && i.Month == month);
        if (classId != null) q = q.Where(i => i.Student.ClassId == classId);
        var all = await q.OrderBy(i => i.Student.FullName)
            .Select(i => new
            {
                i.Id, i.InvoiceNo, i.StudentId, studentName = i.Student.FullName,
                className = i.Student.Class != null ? i.Student.Class.Name : null,
                i.IssueDate, i.DueDate, i.Subtotal, i.Discount, i.Total, i.AmountPaid, i.Status, i.SentAt,
                i.SendCount, i.LastSentAt,
                pendingClaim = i.Claims.Any(c => c.Status == FeePaymentClaim.Pending),
                parents = i.Student.Parents.Where(p => p.Parent.IsActive).Select(p => p.Parent.FullName).ToList()
            }).ToListAsync();

        var rows = all.Select(i => new
        {
            i.Id, i.InvoiceNo, i.StudentId, i.studentName, i.className, i.parents,
            issueDate = i.IssueDate.ToString("yyyy-MM-dd"), dueDate = i.DueDate.ToString("yyyy-MM-dd"),
            i.Subtotal, i.Discount, i.Total, i.AmountPaid,
            balance = i.Status == FeeInvoice.Void ? 0 : Math.Max(0, i.Total - i.AmountPaid),
            i.Status, i.SentAt, i.SendCount, i.LastSentAt, i.pendingClaim,
            overdue = i.Status is FeeInvoice.Unpaid or FeeInvoice.Partial && i.DueDate < today
        }).ToList();
        var shown = string.IsNullOrEmpty(status) ? rows
            : status == "Overdue" ? rows.Where(r => r.overdue).ToList()
            : status == "ToConfirm" ? rows.Where(r => r.pendingClaim).ToList()
            : rows.Where(r => r.Status == status).ToList();

        var live = rows.Where(r => r.Status != FeeInvoice.Void).ToList();
        var activeChildren = await _db.Students.CountAsync(s => s.IsActive && (classId == null || s.ClassId == classId));
        // Payments parents reported, any month (shown as a tab with a count)
        var claimsPending = await _db.FeePaymentClaims.CountAsync(c => c.Status == FeePaymentClaim.Pending);
        return Ok(new
        {
            invoices = shown,
            summary = new
            {
                count       = live.Count,
                billed      = live.Sum(r => r.Total),
                collected   = live.Sum(r => r.AmountPaid),
                outstanding = live.Sum(r => r.balance),
                paid        = live.Count(r => r.Status == FeeInvoice.Paid),
                overdue     = live.Count(r => r.overdue),
                notSent     = live.Count(r => r.SentAt == null),
                childrenWithoutInvoice = Math.Max(0, activeChildren - live.Select(r => r.StudentId).Distinct().Count()),
                claimsPending
            }
        });
    }

    /// <summary>GET /api/school/fees/invoices/{id} — lines and payments.</summary>
    [HttpGet("invoices/{id:int}")]
    public async Task<IActionResult> GetInvoice(int id)
    {
        var inv = await LoadInvoiceAsync(id);
        if (!await CanSeeInvoiceAsync(inv)) return Forbid();
        return Ok(InvoiceDetail(inv, await ClaimsForAsync(new List<int> { inv.Id })));
    }

    /// <summary>
    /// POST /api/school/fees/invoices/generate — invoices for every active child who has none for
    /// the month: their session fee + add-ons, minus the sibling discount for the 2nd and later
    /// child of a family. Not sent to parents yet.
    /// </summary>
    [HttpPost("invoices/generate")]
    [Authorize(Roles = UserAccess.Admin)]
    public async Task<IActionResult> Generate([FromBody] GenerateInvoicesRequest req)
    {
        if (req.Month is < 1 or > 12 || req.Year is < 2020 or > 2100) return BadRequest(new { message = "Choose a valid month." });
        var settings = await _settings.GetAsync();
        var items = await _db.FeeItems.AsNoTracking().Where(i => i.IsActive).ToListAsync();
        // This year's price list (monthly fee per session, one-time / twice-a-year / deposit charges);
        // without one, the session fees under Fee items are used as before
        var prices = await FeePrices.ForDateAsync(_db, new DateTime(req.Year, req.Month, 1));
        if (prices == null && !items.Any(i => i.Kind == FeeItem.Session))
            return BadRequest(new { message = "Add this year's price list first (Fees → Price lists)." });

        // Each child's earlier invoices: how many, and the month of the first (registration / deposit / supplies)
        var thisMonthKey = req.Year * 12 + req.Month;
        var history = (await _db.FeeInvoices.AsNoTracking()
                .Where(i => i.Status != FeeInvoice.Void && (i.Year * 12 + i.Month) < thisMonthKey)
                .Select(i => new { i.StudentId, key = i.Year * 12 + i.Month }).ToListAsync())
            .GroupBy(x => x.StudentId)
            .ToDictionary(g => g.Key, g => (count: g.Count(), first: g.Min(x => x.key)));
        var depositLines = new List<(FeeInvoice inv, int studentId, string name, decimal amount)>();

        var children = await _db.Students.AsNoTracking().Where(s => s.IsActive)
            .Select(s => new
            {
                s.Id, s.FullName, s.SessionType, s.DateOfBirth,
                parentIds = s.Parents.Select(p => p.ParentId).ToList(),
                addOnIds = _db.StudentFeeAddOns.Where(a => a.StudentId == s.Id).Select(a => a.FeeItemId).ToList()
            }).ToListAsync();
        var already = await _db.FeeInvoices
            .Where(i => i.Year == req.Year && i.Month == req.Month && i.Status != FeeInvoice.Void)
            .Select(i => i.StudentId).ToListAsync();

        // Families: children who share a parent (also through a brother or sister)
        var family = new Dictionary<int, int>();
        int Find(int x) { while (family[x] != x) x = family[x] = family[family[x]]; return x; }
        foreach (var c in children) family[c.Id] = c.Id;
        foreach (var group in children.SelectMany(c => c.parentIds.Select(p => (p, c.Id))).GroupBy(x => x.p))
        {
            var first = group.First().Id;
            foreach (var (_, id) in group.Skip(1)) family[Find(id)] = Find(first);
        }
        // The eldest child of a family pays in full; younger brothers and sisters get the discount
        var rank = children
            .GroupBy(c => Find(c.Id))
            .SelectMany(g => g.OrderBy(c => c.DateOfBirth ?? DateTime.MaxValue).ThenBy(c => c.Id).Select((c, i) => (c.Id, i)))
            .ToDictionary(x => x.Id, x => x.i);

        var monthName = new DateTime(req.Year, req.Month, 1).ToString("MMMM yyyy", Money);
        var issue = SchoolClock.Today;
        var due = new DateTime(req.Year, req.Month, Math.Min(settings.FeeDueDay, DateTime.DaysInMonth(req.Year, req.Month)));
        if (due < issue) due = issue.AddDays(7);
        var prefix = $"INV-{req.Year}{req.Month:00}-";
        var next = await NextNumberAsync(prefix, _db.FeeInvoices.Select(i => i.InvoiceNo));

        var staffName = await StaffNameAsync();
        var created = new List<FeeInvoice>();
        var skipped = new List<object>();
        foreach (var c in children.Where(c => !already.Contains(c.Id)).OrderBy(c => c.FullName))
        {
            var priceSession = prices?.Sessions.FirstOrDefault(s => s.SessionType == c.SessionType && s.Offered);
            var session = priceSession == null ? items.FirstOrDefault(i => i.Kind == FeeItem.Session && i.SessionType == c.SessionType) : null;
            if (priceSession == null && session == null)
            {
                skipped.Add(new { c.FullName, reason = $"no fee set for {c.SessionType}" + (prices != null ? $" in the {prices.Name} price list" : "") });
                continue;
            }

            var inv = new FeeInvoice
            {
                InvoiceNo = prefix + (next++).ToString("0000"), StudentId = c.Id, Year = req.Year, Month = req.Month,
                IssueDate = issue, DueDate = due, CreatedByName = staffName
            };
            var order = 0;
            if (priceSession != null)
                inv.Lines.Add(new FeeInvoiceLine { Description = $"{priceSession.SessionType} school fees — {monthName}", Amount = priceSession.MonthlyFee, SortOrder = order++ });
            else
                inv.Lines.Add(new FeeInvoiceLine { Description = $"{session!.Name} — {monthName}", Amount = session.Amount, FeeItemId = session.Id, SortOrder = order++ });
            foreach (var addOn in items.Where(i => i.Kind == FeeItem.AddOn && c.addOnIds.Contains(i.Id)).OrderBy(i => i.SortOrder).ThenBy(i => i.Name))
                inv.Lines.Add(new FeeInvoiceLine { Description = addOn.Name, Amount = addOn.Amount, FeeItemId = addOn.Id, SortOrder = order++ });
            if (rank[c.Id] > 0 && settings.SiblingDiscountPercent > 0)
            {
                var subtotal = inv.Lines.Sum(l => l.Amount);
                var off = Math.Round(subtotal * settings.SiblingDiscountPercent / 100m, 2, MidpointRounding.AwayFromZero);
                if (off > 0)
                    inv.Lines.Add(new FeeInvoiceLine { Description = $"Sibling discount ({settings.SiblingDiscountPercent:0.##}%)", Amount = -off, SortOrder = order++ });
            }

            // Registration, supplies and deposit from the price list (no sibling discount on these)
            if (prices != null)
            {
                var h = history.TryGetValue(c.Id, out var x) ? x : (count: 0, first: 0);
                foreach (var charge in FeePrices.ExtraCharges(prices, c.SessionType, req.Year, req.Month, h.count, h.count == 0 ? null : h.first))
                {
                    var label = charge.Kind switch
                    {
                        FeePriceCharge.Deposit => $"{charge.Name} (refundable)",
                        FeePriceCharge.TwiceAYear => $"{charge.Name} (twice a year)",
                        _ => charge.Name
                    };
                    inv.Lines.Add(new FeeInvoiceLine { Description = label, Amount = charge.Amount, SortOrder = order++ });
                    if (charge.Kind == FeePriceCharge.Deposit) depositLines.Add((inv, c.Id, charge.Name, charge.Amount));
                }
            }
            inv.Recalculate();
            created.Add(inv);
        }
        _db.FeeInvoices.AddRange(created);
        await _db.SaveChangesAsync();

        // Deposits billed now are held for the child until refunded
        foreach (var (inv, studentId, name, amount) in depositLines)
            _db.StudentDeposits.Add(new StudentDeposit { StudentId = studentId, Description = name, Amount = amount, InvoiceId = inv.Id });
        if (depositLines.Count > 0) await _db.SaveChangesAsync();

        await Audit("Created", "FeeInvoice", 0, $"Generated {created.Count} invoice(s) for {monthName}" +
            (skipped.Count > 0 ? $"; {skipped.Count} skipped" : ""));
        return Ok(new { created = created.Count, alreadyHad = already.Distinct().Count(), skipped });
    }

    /// <summary>PUT /api/school/fees/invoices/{id} — change the lines, due date or notes (not a void invoice).</summary>
    [HttpPut("invoices/{id:int}")]
    [Authorize(Roles = UserAccess.Admin)]
    public async Task<IActionResult> UpdateInvoice(int id, [FromBody] UpdateInvoiceRequest req)
    {
        var inv = await _db.FeeInvoices.Include(i => i.Lines).Include(i => i.Payments).FirstOrDefaultAsync(i => i.Id == id)
                  ?? throw new KeyNotFoundException("Invoice not found.");
        if (inv.Status == FeeInvoice.Void) return BadRequest(new { message = "This invoice is void." });
        var lines = (req.Lines ?? new()).Where(l => !string.IsNullOrWhiteSpace(l.Description) || l.Amount != 0).ToList();
        if (lines.Count == 0) return BadRequest(new { message = "An invoice needs at least one line." });
        if (lines.Any(l => string.IsNullOrWhiteSpace(l.Description))) return BadRequest(new { message = "Every line needs a description." });
        if (lines.Any(l => Math.Abs(l.Amount) > 1_000_000)) return BadRequest(new { message = "Check the amounts." });
        if (req.DueDate != null && req.DueDate.Value.Date < inv.IssueDate)
            return BadRequest(new { message = "The due date can't be before the invoice date." });

        _db.FeeInvoiceLines.RemoveRange(inv.Lines);
        inv.Lines = lines.Select((l, i) => new FeeInvoiceLine
        {
            Description = l.Description!.Trim().Length > 150 ? l.Description.Trim()[..150] : l.Description.Trim(),
            Amount = Math.Round(l.Amount, 2), FeeItemId = l.FeeItemId, SortOrder = i
        }).ToList();
        if (req.DueDate != null) inv.DueDate = req.DueDate.Value.Date;
        inv.Notes = string.IsNullOrWhiteSpace(req.Notes) ? null : req.Notes.Trim();
        inv.Recalculate();
        if (inv.Total < inv.AmountPaid)
            return BadRequest(new { message = $"The new total ({Rm(inv.Total)}) is less than what was already paid ({Rm(inv.AmountPaid)}). Remove a payment first." });
        await _db.SaveChangesAsync();
        await Audit("Updated", "FeeInvoice", inv.Id, $"Changed invoice {inv.InvoiceNo}: total {Rm(inv.Total)}");
        return Ok(await DetailAsync(id));
    }

    /// <summary>POST /api/school/fees/invoices/{id}/void — cancel an invoice (no payments on it).</summary>
    [HttpPost("invoices/{id:int}/void")]
    [Authorize(Roles = UserAccess.Admin)]
    public async Task<IActionResult> VoidInvoice(int id, [FromBody] VoidInvoiceRequest req)
    {
        var inv = await _db.FeeInvoices.Include(i => i.Payments).FirstOrDefaultAsync(i => i.Id == id)
                  ?? throw new KeyNotFoundException("Invoice not found.");
        if (inv.Status == FeeInvoice.Void) return NoContent();
        if (inv.Payments.Count > 0) return BadRequest(new { message = "This invoice has payments. Remove them first, or change the lines instead." });
        if (string.IsNullOrWhiteSpace(req.Reason)) return BadRequest(new { message = "Give a reason, e.g. \"Child left the school\".", field = "reason" });
        inv.Status = FeeInvoice.Void;
        inv.VoidReason = req.Reason.Trim().Length > 300 ? req.Reason.Trim()[..300] : req.Reason.Trim();
        // A deposit billed on this invoice is no longer held (unless already refunded / deducted)
        _db.StudentDeposits.RemoveRange(await _db.StudentDeposits.Where(d => d.InvoiceId == inv.Id && d.Status == StudentDeposit.Held).ToListAsync());
        await _db.SaveChangesAsync();
        await Audit("Updated", "FeeInvoice", inv.Id, $"Voided invoice {inv.InvoiceNo}: {inv.VoidReason}");
        return NoContent();
    }

    /// <summary>
    /// POST /api/school/fees/invoices/send — tell the parents (app/web notification, phone alert and an
    /// email with the invoice PDF). Chosen invoices (InvoiceIds), else the month's unsent ones (optionally
    /// one class). Resend = also send again ones that were already sent (a parent asks for it again).
    /// </summary>
    [HttpPost("invoices/send")]
    [Authorize(Roles = UserAccess.Admin)]
    public async Task<IActionResult> Send([FromBody] SendInvoicesRequest req)
    {
        var q = _db.FeeInvoices.Include(i => i.Lines).Include(i => i.Payments).Include(i => i.Student).ThenInclude(s => s.Class)
            .Where(i => i.Status != FeeInvoice.Void);
        if (req.InvoiceIds is { Count: > 0 })
        {
            q = q.Where(i => req.InvoiceIds.Contains(i.Id));
            if (!req.Resend) q = q.Where(i => i.SentAt == null);
        }
        else
        {
            q = q.Where(i => i.Year == req.Year && i.Month == req.Month && i.SentAt == null);
            if (req.ClassId != null) q = q.Where(i => i.Student.ClassId == req.ClassId);
        }
        var invoices = await q.ToListAsync();
        var now = DateTime.UtcNow;
        foreach (var inv in invoices)
        {
            inv.SentAt ??= now;
            inv.LastSentAt = now;
            inv.SendCount++;
        }
        await _db.SaveChangesAsync();

        var company = await _settings.GetAsync();
        var emailed = 0;
        foreach (var inv in invoices)
        {
            await TellParentsAsync(inv.StudentId, $"Fees for {MonthName(inv)}: {inv.Student.FullName}",
                inv.Status == FeeInvoice.Paid
                    ? $"Invoice {inv.InvoiceNo}: {Rm(inv.Total)}, already paid."
                    : $"Invoice {inv.InvoiceNo}: {Rm(inv.Balance)} due by {inv.DueDate:d MMM yyyy}.");
            emailed += await EmailInvoiceAsync(company, inv);
        }
        if (invoices.Count > 0)
            await Audit("Updated", "FeeInvoice", invoices.Count == 1 ? invoices[0].Id : 0,
                $"Sent {invoices.Count} invoice(s) to parents ({emailed} email(s))" +
                (invoices.Count == 1 ? $": {invoices[0].InvoiceNo}, time {invoices[0].SendCount}" : ""));
        return Ok(new { sent = invoices.Count, emailed });
    }

    /// <summary>Emails the invoice PDF to each active parent with an email address. Returns how many were queued.</summary>
    private async Task<int> EmailInvoiceAsync(CompanySettings company, FeeInvoice inv)
    {
        if (_email == null) return 0;
        var parents = await _db.StudentParents
            .Where(sp => sp.StudentId == inv.StudentId && sp.Parent.IsActive && sp.Parent.Email != null)
            .Select(sp => new { sp.Parent.FullName, sp.Parent.Email }).ToListAsync();
        if (parents.Count == 0) return 0;

        var pdf = FeePdf.Invoice(company, inv, parents.Select(p => p.FullName).ToList());
        string E(string? s) => System.Net.WebUtility.HtmlEncode(s ?? "");
        foreach (var p in parents)
        {
            var body = $"""
                <p>Dear {E(p.FullName)},</p>
                <p>Please find attached the school fees invoice for <b>{E(inv.Student.FullName)}</b> for <b>{E(MonthName(inv))}</b>.</p>
                <table cellpadding="4" style="border-collapse:collapse">
                  <tr><td>Invoice</td><td><b>{E(inv.InvoiceNo)}</b></td></tr>
                  <tr><td>Total</td><td><b>{E(Rm(inv.Total))}</b></td></tr>
                  {(inv.AmountPaid > 0 ? $"<tr><td>Paid</td><td>{E(Rm(inv.AmountPaid))}</td></tr>" : "")}
                  <tr><td>Balance due</td><td><b>{E(Rm(inv.Balance))}</b> by {inv.DueDate:d MMM yyyy}</td></tr>
                </table>
                {(string.IsNullOrWhiteSpace(company.FeePaymentInstructions) || inv.Balance <= 0 ? "" :
                    $"<p><b>How to pay</b><br>{E(company.FeePaymentInstructions).Replace("\n", "<br>")}</p>")}
                <p>After paying, you can tell us in the parent portal (Fees → I've paid) so we can send your receipt.</p>
                <p>Thank you,<br>{E(company.NameForDisplay)}</p>
                """;
            _email.Enqueue(new EmailJob
            {
                ToEmail = p.Email!,
                Subject = $"{company.NameForDisplay}: school fees for {MonthName(inv)} ({inv.Student.FullName})",
                Body = body,
                AttachmentData = pdf,
                AttachmentName = $"{inv.InvoiceNo}.pdf"
            });
        }
        return parents.Count;
    }

    /// <summary>POST /api/school/fees/invoices/remind — remind parents of overdue invoices (sent, not fully paid, past due).</summary>
    [HttpPost("invoices/remind")]
    [Authorize(Roles = UserAccess.Admin)]
    public async Task<IActionResult> Remind([FromBody] SendInvoicesRequest req)
    {
        var today = SchoolClock.Today;
        var q = _db.FeeInvoices.Include(i => i.Student)
            .Where(i => i.SentAt != null && (i.Status == FeeInvoice.Unpaid || i.Status == FeeInvoice.Partial) && i.DueDate < today);
        q = req.InvoiceIds is { Count: > 0 }
            ? q.Where(i => req.InvoiceIds.Contains(i.Id))
            : q.Where(i => i.Year == req.Year && i.Month == req.Month && (req.ClassId == null || i.Student.ClassId == req.ClassId));
        var invoices = await q.ToListAsync();
        foreach (var inv in invoices)
            await TellParentsAsync(inv.StudentId, $"Reminder: fees for {inv.Student.FullName}",
                $"Invoice {inv.InvoiceNo} ({MonthName(inv)}): {Rm(inv.Balance)} was due on {inv.DueDate:d MMM yyyy}. Please pay soon, or contact the office.");
        if (invoices.Count > 0) await Audit("Updated", "FeeInvoice", 0, $"Sent {invoices.Count} fee reminder(s)");
        return Ok(new { reminded = invoices.Count });
    }

    // ════════════════════════════ Payments ════════════════════════════

    /// <summary>POST /api/school/fees/invoices/{id}/payments — money received; issues a receipt number.</summary>
    [HttpPost("invoices/{id:int}/payments")]
    [Authorize(Roles = UserAccess.Admin)]
    public async Task<IActionResult> AddPayment(int id, [FromBody] PaymentRequest req)
    {
        var inv = await _db.FeeInvoices.Include(i => i.Lines).Include(i => i.Payments).Include(i => i.Student)
                      .FirstOrDefaultAsync(i => i.Id == id) ?? throw new KeyNotFoundException("Invoice not found.");
        var (payment, error) = await RecordPaymentAsync(inv, req.Amount, req.PaidOn, req.Method, req.Reference);
        if (error != null) return BadRequest(error);
        await TellPaymentAsync(inv, payment!);
        return Ok(await DetailAsync(id));
    }

    /// <summary>Checks and records a payment with the next receipt number (saved). Returns the error to show otherwise.</summary>
    private async Task<(FeePayment? payment, object? error)> RecordPaymentAsync(
        FeeInvoice inv, decimal rawAmount, DateTime? paidOnRaw, string method, string? reference)
    {
        if (inv.Status == FeeInvoice.Void) return (null, new { message = "This invoice is void." });
        var amount = Math.Round(rawAmount, 2);
        if (amount <= 0) return (null, new { message = "Enter the amount received.", field = "amount" });
        if (amount > inv.Balance) return (null, new { message = $"That's more than the balance ({Rm(inv.Balance)}).", field = "amount" });
        if (!FeePayment.Methods.Contains(method)) return (null, new { message = "Choose how it was paid.", field = "method" });
        var paidOn = (paidOnRaw ?? SchoolClock.Today).Date;
        if (paidOn > SchoolClock.Today) return (null, new { message = "The payment date can't be in the future.", field = "paidOn" });

        var prefix = $"RCP-{paidOn:yyyyMM}-";
        var payment = new FeePayment
        {
            ReceiptNo = prefix + (await NextNumberAsync(prefix, _db.FeePayments.Select(p => p.ReceiptNo))).ToString("0000"),
            Amount = amount, PaidOn = paidOn, Method = method,
            Reference = string.IsNullOrWhiteSpace(reference) ? null : reference.Trim(),
            RecordedByName = await StaffNameAsync()
        };
        inv.Payments.Add(payment);
        inv.Recalculate();
        await _db.SaveChangesAsync();
        await Audit("Created", "FeePayment", payment.Id, $"Payment {payment.ReceiptNo}: {Rm(amount)} for {inv.InvoiceNo} ({payment.Method})");
        return (payment, null);
    }

    private Task TellPaymentAsync(FeeInvoice inv, FeePayment payment) =>
        inv.SentAt == null ? Task.CompletedTask :
        TellParentsAsync(inv.StudentId, $"Payment received: {inv.Student.FullName}",
            $"{Rm(payment.Amount)} for invoice {inv.InvoiceNo}, receipt {payment.ReceiptNo}." +
            (inv.Balance > 0 ? $" Balance {Rm(inv.Balance)}." : " Fully paid — thank you!"));

    // ════════════════════════════ "I've paid" (parents) → office confirms ════════════════════════════

    /// <summary>
    /// POST /api/school/fees/invoices/{id}/claims (multipart: amount, paidOn, method, reference, note, file?) —
    /// a parent reports a payment, usually with a photo of the transfer slip. The office is told.
    /// </summary>
    [HttpPost("invoices/{id:int}/claims")]
    [RequestSizeLimit(ChatMessage.MaxAttachmentBytes + 256 * 1024)]
    public async Task<IActionResult> CreateClaim(int id, [FromForm] PaymentClaimForm form)
    {
        var me = await SchoolViewer.LoadAsync(_db, User);
        var inv = await _db.FeeInvoices.Include(i => i.Lines).Include(i => i.Payments).Include(i => i.Student)
                      .FirstOrDefaultAsync(i => i.Id == id) ?? throw new KeyNotFoundException("Invoice not found.");
        if (me == null || !me.IsParent || !me.ChildIds.Contains(inv.StudentId) || inv.SentAt == null || inv.Status == FeeInvoice.Void)
            return Forbid();
        if (inv.Balance <= 0) return BadRequest(new { message = "This invoice is already paid." });
        if (await _db.FeePaymentClaims.AnyAsync(c => c.InvoiceId == id && c.Status == FeePaymentClaim.Pending))
            return BadRequest(new { message = "Your earlier payment for this invoice is still waiting for the school to confirm it." });

        var amount = Math.Round(form.Amount, 2);
        if (amount <= 0) return BadRequest(new { message = "Enter the amount you paid.", field = "amount" });
        if (amount > inv.Balance) return BadRequest(new { message = $"That's more than the balance ({Rm(inv.Balance)}).", field = "amount" });
        if (!FeePayment.Methods.Contains(form.Method ?? "")) return BadRequest(new { message = "Choose how you paid.", field = "method" });
        var paidOn = (form.PaidOn ?? SchoolClock.Today).Date;
        if (paidOn > SchoolClock.Today) return BadRequest(new { message = "The payment date can't be in the future.", field = "paidOn" });
        if (paidOn < SchoolClock.Today.AddDays(-120)) return BadRequest(new { message = "Check the payment date.", field = "paidOn" });

        var claim = new FeePaymentClaim
        {
            InvoiceId = id, Amount = amount, PaidOn = paidOn, Method = form.Method!,
            Reference = Clean(form.Reference, 100), Note = Clean(form.Note, 500),
            CreatedByUserId = me.UserId, CreatedByName = me.Name
        };
        if (form.File != null && form.File.Length > 0)
        {
            var (file, error) = await ChatFiles.ReadAsync(form.File);
            if (error != null) return BadRequest(new { message = error });
            claim.SlipName = file!.Value.name;
            claim.SlipContentType = file.Value.type;
            claim.SlipData = file.Value.data;
        }
        _db.FeePaymentClaims.Add(claim);
        await _db.SaveChangesAsync();

        var admins = await _db.Users.Where(u => u.Role == UserAccess.Admin && u.IsActive).Select(u => u.Id).ToListAsync();
        await SchoolAlerts.SendAsync(_db, _push, _live, admins, $"Payment to confirm: {inv.Student.FullName}",
            $"{me.Name} says they paid {Rm(amount)} ({claim.Method}) for {inv.InvoiceNo}.", "school_fees_claim",
            "/school/fees?tab=claims", "fees", new { studentId = inv.StudentId });
        await Audit("Created", "FeePaymentClaim", claim.Id, $"{me.Name} reported paying {Rm(amount)} for {inv.InvoiceNo}");
        return Ok(await _db.FeePaymentClaims.Where(c => c.Id == claim.Id).Select(ClaimView.Projection).FirstAsync());
    }

    /// <summary>GET /api/school/fees/claims?status=Pending — payments parents reported (newest first).</summary>
    [HttpGet("claims")]
    [Authorize(Roles = UserAccess.Admin)]
    public async Task<IActionResult> GetClaims([FromQuery] string? status = FeePaymentClaim.Pending)
    {
        var q = _db.FeePaymentClaims.AsNoTracking();
        if (!string.IsNullOrEmpty(status)) q = q.Where(c => c.Status == status);
        return Ok(await q.OrderByDescending(c => c.CreatedAt).Take(200).Select(ClaimView.Projection).ToListAsync());
    }

    /// <summary>GET /api/school/fees/claims/{id}/slip — the transfer slip (admins, or the parent who sent it).</summary>
    [HttpGet("claims/{id:int}/slip")]
    public async Task<IActionResult> ClaimSlip(int id)
    {
        var c = await _db.FeePaymentClaims.AsNoTracking().Where(x => x.Id == id)
            .Select(x => new { x.SlipName, x.SlipContentType, x.SlipData, x.Invoice.StudentId })
            .FirstOrDefaultAsync() ?? throw new KeyNotFoundException("Not found.");
        if (!User.IsInRole(UserAccess.Admin))
        {
            var me = await SchoolViewer.LoadAsync(_db, User);
            if (me is not { IsParent: true } || !me.ChildIds.Contains(c.StudentId)) return Forbid();
        }
        if (c.SlipData == null) throw new KeyNotFoundException("No slip was attached.");
        return ChatFiles.Inline(Response, this, c.SlipName ?? "slip", c.SlipContentType ?? "application/octet-stream", c.SlipData);
    }

    /// <summary>
    /// POST /api/school/fees/claims/{id}/confirm — the money arrived: records the payment (the office may
    /// correct the amount, date, method or reference) and issues the receipt; the parent is told.
    /// </summary>
    [HttpPost("claims/{id:int}/confirm")]
    [Authorize(Roles = UserAccess.Admin)]
    public async Task<IActionResult> ConfirmClaim(int id, [FromBody] ConfirmClaimRequest? req)
    {
        var claim = await _db.FeePaymentClaims.FirstOrDefaultAsync(c => c.Id == id) ?? throw new KeyNotFoundException("Not found.");
        if (claim.Status != FeePaymentClaim.Pending) return BadRequest(new { message = $"This payment was already {claim.Status.ToLower()}." });
        var inv = await _db.FeeInvoices.Include(i => i.Lines).Include(i => i.Payments).Include(i => i.Student)
            .FirstAsync(i => i.Id == claim.InvoiceId);

        var (payment, error) = await RecordPaymentAsync(inv,
            req?.Amount ?? claim.Amount,
            req?.PaidOn ?? claim.PaidOn,
            string.IsNullOrEmpty(req?.Method) ? claim.Method : req.Method,
            req?.Reference ?? claim.Reference);
        if (error != null) return BadRequest(error);

        claim.Status = FeePaymentClaim.Confirmed;
        claim.PaymentId = payment!.Id;
        claim.ReviewedByName = payment.RecordedByName;
        claim.ReviewedAt = DateTime.UtcNow;
        await _db.SaveChangesAsync();
        await TellPaymentAsync(inv, payment);
        return Ok(await DetailAsync(inv.Id));
    }

    /// <summary>POST /api/school/fees/claims/{id}/reject { reason } — not received / wrong amount; the parent sees why.</summary>
    [HttpPost("claims/{id:int}/reject")]
    [Authorize(Roles = UserAccess.Admin)]
    public async Task<IActionResult> RejectClaim(int id, [FromBody] VoidInvoiceRequest req)
    {
        var claim = await _db.FeePaymentClaims.Include(c => c.Invoice).ThenInclude(i => i.Student)
            .FirstOrDefaultAsync(c => c.Id == id) ?? throw new KeyNotFoundException("Not found.");
        if (claim.Status != FeePaymentClaim.Pending) return BadRequest(new { message = $"This payment was already {claim.Status.ToLower()}." });
        if (string.IsNullOrWhiteSpace(req.Reason))
            return BadRequest(new { message = "Tell the parent why, e.g. \"Not received in our account yet\".", field = "reason" });
        claim.Status = FeePaymentClaim.Rejected;
        claim.RejectReason = Clean(req.Reason, 300);
        claim.ReviewedByName = await StaffNameAsync();
        claim.ReviewedAt = DateTime.UtcNow;
        await _db.SaveChangesAsync();
        await TellParentsAsync(claim.Invoice.StudentId, $"Payment not confirmed: {claim.Invoice.Student.FullName}",
            $"Your payment of {Rm(claim.Amount)} for {claim.Invoice.InvoiceNo} could not be confirmed: {claim.RejectReason}");
        await Audit("Updated", "FeePaymentClaim", claim.Id, $"Rejected payment report for {claim.Invoice.InvoiceNo}: {claim.RejectReason}");
        return NoContent();
    }

    private static string? Clean(string? v, int max)
    {
        if (string.IsNullOrWhiteSpace(v)) return null;
        v = v.Trim();
        return v.Length > max ? v[..max] : v;
    }

    /// <summary>DELETE /api/school/fees/payments/{id} — a payment recorded by mistake.</summary>
    [HttpDelete("payments/{id:int}")]
    [Authorize(Roles = UserAccess.Admin)]
    public async Task<IActionResult> DeletePayment(int id)
    {
        var p = await _db.FeePayments.FindAsync(id) ?? throw new KeyNotFoundException("Payment not found.");
        var inv = await _db.FeeInvoices.Include(i => i.Lines).Include(i => i.Payments).FirstAsync(i => i.Id == p.InvoiceId);
        inv.Payments.Remove(p);
        _db.FeePayments.Remove(p);
        inv.Recalculate();
        await _db.SaveChangesAsync();
        await Audit("Deleted", "FeePayment", id, $"Removed payment {p.ReceiptNo} ({Rm(p.Amount)}) from {inv.InvoiceNo}");
        return Ok(await DetailAsync(inv.Id));
    }

    /// <summary>
    /// GET /api/school/fees/export?year=&amp;month=&amp;unpaidOnly= — invoices as an Excel sheet (admins).
    /// No month: all months. unpaidOnly (default true): only invoices with a balance left.
    /// </summary>
    [HttpGet("export")]
    [Authorize(Roles = UserAccess.Admin)]
    public async Task<IActionResult> Export([FromQuery] int? year, [FromQuery] int? month, [FromQuery] bool unpaidOnly = true)
    {
        var q = _db.FeeInvoices.AsNoTracking().Include(i => i.Student).ThenInclude(s => s.Class)
            .Where(i => i.Status != FeeInvoice.Void);
        if (year != null) q = q.Where(i => i.Year == year);
        if (month != null) q = q.Where(i => i.Month == month);
        if (unpaidOnly) q = q.Where(i => i.Status != FeeInvoice.Paid);
        var rows = await q.OrderBy(i => i.Year).ThenBy(i => i.Month).ThenBy(i => i.Student.FullName).ToListAsync();

        using var book = new ClosedXML.Excel.XLWorkbook();
        var sheet = book.Worksheets.Add(unpaidOnly ? "Unpaid fees" : "Fee invoices");
        string[] headers = { "Invoice", "Child", "Class", "Month", "Due date", "Total (RM)", "Paid (RM)", "Balance (RM)", "Status", "Sent", "Overdue" };
        for (var c = 0; c < headers.Length; c++) sheet.Cell(1, c + 1).Value = headers[c];
        var header = sheet.Range(1, 1, 1, headers.Length);
        header.Style.Font.Bold = true;
        header.Style.Fill.BackgroundColor = ClosedXML.Excel.XLColor.LightBlue;

        var today = SchoolClock.Today;
        var r = 2;
        foreach (var i in rows)
        {
            sheet.Cell(r, 1).Value = i.InvoiceNo;
            sheet.Cell(r, 2).Value = i.Student.FullName;
            sheet.Cell(r, 3).Value = i.Student.Class?.Name ?? "";
            sheet.Cell(r, 4).Value = new DateTime(i.Year, i.Month, 1).ToString("MMM yyyy");
            sheet.Cell(r, 5).Value = i.DueDate;
            sheet.Cell(r, 5).Style.DateFormat.Format = "dd MMM yyyy";
            sheet.Cell(r, 6).Value = i.Total;
            sheet.Cell(r, 7).Value = i.AmountPaid;
            sheet.Cell(r, 8).Value = i.Balance;
            sheet.Cell(r, 9).Value = i.Status;
            sheet.Cell(r, 10).Value = i.SentAt == null ? "Draft" : "Sent";
            sheet.Cell(r, 11).Value = i.Status != FeeInvoice.Paid && i.DueDate.Date < today ? "Yes" : "";
            r++;
        }
        sheet.Range(2, 6, Math.Max(2, r - 1), 8).Style.NumberFormat.Format = "#,##0.00";
        if (rows.Count > 0)
        {
            sheet.Cell(r, 5).Value = "Total";
            sheet.Cell(r, 5).Style.Font.Bold = true;
            sheet.Cell(r, 6).Value = rows.Sum(i => i.Total);
            sheet.Cell(r, 7).Value = rows.Sum(i => i.AmountPaid);
            sheet.Cell(r, 8).Value = rows.Sum(i => i.Balance);
            sheet.Range(r, 6, r, 8).Style.Font.Bold = true;
            sheet.Range(r, 6, r, 8).Style.NumberFormat.Format = "#,##0.00";
        }
        sheet.Columns().AdjustToContents();

        using var ms = new MemoryStream();
        book.SaveAs(ms);
        var period = month != null && year != null ? $"_{year}-{month:00}" : year != null ? $"_{year}" : "";
        return File(ms.ToArray(), "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            $"{(unpaidOnly ? "Unpaid_fees" : "Fee_invoices")}{period}.xlsx");
    }

    // ════════════════════════════ PDFs ════════════════════════════

    /// <summary>GET /api/school/fees/invoices/{id}/pdf — admins, or the child's parents once sent.</summary>
    [HttpGet("invoices/{id:int}/pdf")]
    public async Task<IActionResult> InvoicePdf(int id)
    {
        var inv = await LoadInvoiceAsync(id);
        if (!await CanSeeInvoiceAsync(inv)) return Forbid();
        var pdf = FeePdf.Invoice(await _settings.GetAsync(), inv, await ParentNamesAsync(inv.StudentId));
        return File(pdf, "application/pdf", $"{inv.InvoiceNo}.pdf");
    }

    /// <summary>GET /api/school/fees/payments/{id}/receipt — admins, or the child's parents.</summary>
    [HttpGet("payments/{id:int}/receipt")]
    public async Task<IActionResult> ReceiptPdf(int id)
    {
        var invoiceId = await _db.FeePayments.Where(p => p.Id == id).Select(p => (int?)p.InvoiceId).FirstOrDefaultAsync()
                        ?? throw new KeyNotFoundException("Payment not found.");
        var inv = await LoadInvoiceAsync(invoiceId);
        if (!await CanSeeInvoiceAsync(inv)) return Forbid();
        var payment = inv.Payments.First(p => p.Id == id);
        var pdf = FeePdf.Receipt(await _settings.GetAsync(), inv, payment, await ParentNamesAsync(inv.StudentId));
        return File(pdf, "application/pdf", $"{payment.ReceiptNo}.pdf");
    }

    // ════════════════════════════ Parents ════════════════════════════

    /// <summary>GET /api/school/fees/mine — a parent's children's invoices (sent, not void), newest first.</summary>
    [HttpGet("mine")]
    public async Task<IActionResult> Mine()
    {
        var me = await SchoolViewer.LoadAsync(_db, User);
        if (me == null || !me.IsParent) return Forbid();
        var settings = await _settings.GetAsync();
        var invoices = await _db.FeeInvoices.AsNoTracking()
            .Include(i => i.Lines).Include(i => i.Payments).Include(i => i.Student).ThenInclude(s => s.Class)
            .Where(i => me.ChildIds.Contains(i.StudentId) && i.SentAt != null && i.Status != FeeInvoice.Void)
            .OrderByDescending(i => i.Year).ThenByDescending(i => i.Month).ThenBy(i => i.Student.FullName)
            .Take(120).ToListAsync();
        var claims = await ClaimsForAsync(invoices.Select(i => i.Id).ToList());
        return Ok(new
        {
            paymentInstructions = settings.FeePaymentInstructions,
            outstanding = invoices.Sum(i => i.Balance),
            invoices = invoices.Select(i => InvoiceDetail(i, claims.Where(c => c.InvoiceId == i.Id)))
        });
    }

    // ════════════════════════════ helpers ════════════════════════════

    private async Task<FeeInvoice> LoadInvoiceAsync(int id) =>
        await _db.FeeInvoices.AsNoTracking()
            .Include(i => i.Lines).Include(i => i.Payments).Include(i => i.Student).ThenInclude(s => s.Class)
            .FirstOrDefaultAsync(i => i.Id == id) ?? throw new KeyNotFoundException("Invoice not found.");

    /// <summary>Admins: all. Parents: their children's, once sent and not void.</summary>
    private async Task<bool> CanSeeInvoiceAsync(FeeInvoice inv)
    {
        if (User.IsInRole(UserAccess.Admin)) return true;
        var me = await SchoolViewer.LoadAsync(_db, User);
        return me is { IsParent: true } && me.ChildIds.Contains(inv.StudentId) && inv.SentAt != null && inv.Status != FeeInvoice.Void;
    }

    /// <summary>The signed-in admin as people know them (employee name, else the login).</summary>
    private async Task<string> StaffNameAsync() =>
        (await SchoolViewer.LoadAsync(_db, User))?.Name ?? User.Identity?.Name ?? "Office";

    private Task<List<string>> ParentNamesAsync(int studentId) =>
        _db.StudentParents.Where(sp => sp.StudentId == studentId && sp.Parent.IsActive)
            .OrderBy(sp => sp.Parent.Relationship).Select(sp => sp.Parent.FullName).ToListAsync();

    private async Task<object> DetailAsync(int id) =>
        InvoiceDetail(await LoadInvoiceAsync(id), await ClaimsForAsync(new List<int> { id }));

    private Task<List<ClaimView>> ClaimsForAsync(List<int> invoiceIds) =>
        _db.FeePaymentClaims.AsNoTracking().Where(c => invoiceIds.Contains(c.InvoiceId))
            .OrderByDescending(c => c.CreatedAt).Select(ClaimView.Projection).ToListAsync();

    private static object InvoiceDetail(FeeInvoice i, IEnumerable<ClaimView>? claims = null) => new
    {
        i.SendCount, i.LastSentAt,
        claims = (claims ?? Enumerable.Empty<ClaimView>()).ToList(),
        i.Id, i.InvoiceNo, i.StudentId, studentName = i.Student.FullName, className = i.Student.Class?.Name,
        i.Year, i.Month, monthName = MonthName(i),
        issueDate = i.IssueDate.ToString("yyyy-MM-dd"), dueDate = i.DueDate.ToString("yyyy-MM-dd"),
        i.Subtotal, i.Discount, i.Total, i.AmountPaid, i.Balance, i.Status, i.Notes, i.SentAt, i.VoidReason,
        overdue = i.Status is FeeInvoice.Unpaid or FeeInvoice.Partial && i.DueDate < SchoolClock.Today,
        lines = i.Lines.OrderBy(l => l.SortOrder).Select(l => new { l.Id, l.Description, l.Amount, l.FeeItemId }),
        payments = i.Payments.OrderBy(p => p.PaidOn).ThenBy(p => p.Id).Select(p => new
        {
            p.Id, p.ReceiptNo, p.Amount, paidOn = p.PaidOn.ToString("yyyy-MM-dd"), p.Method, p.Reference, p.RecordedByName
        })
    };

    private async Task TellParentsAsync(int studentId, string title, string message)
    {
        var parents = await SchoolParticipants.ParentUserIdsAsync(_db, studentId);
        await SchoolAlerts.SendAsync(_db, _push, _live, parents, title, message, "school_fees", "/parent/fees", "fees", new { studentId });
    }

    /// <summary>The next running number after the highest "PREFIX0007" in use.</summary>
    private static async Task<int> NextNumberAsync(string prefix, IQueryable<string> numbers)
    {
        var last = await numbers.Where(n => n.StartsWith(prefix)).OrderByDescending(n => n).FirstOrDefaultAsync();
        return last != null && int.TryParse(last[prefix.Length..], out var n) ? n + 1 : 1;
    }

    private async Task<object?> ValidateItemAsync(FeeItemRequest req, int? id)
    {
        var name = req.Name?.Trim() ?? "";
        if (name.Length == 0) return new { message = "Enter a name, e.g. \"Full day tuition\" or \"Mandarin class\".", field = "name" };
        if (!FeeItem.Kinds.Contains(req.Kind)) return new { message = "Choose session fee or add-on.", field = "kind" };
        if (req.Amount < 0 || req.Amount > 1_000_000) return new { message = "Enter a valid amount.", field = "amount" };
        if (req.Kind == FeeItem.Session)
        {
            if (!Student.SessionTypes.Contains(req.SessionType ?? ""))
                return new { message = "Choose the session (half day, full day or daycare).", field = "sessionType" };
            if (req.IsActive && await _db.FeeItems.AnyAsync(i => i.Id != (id ?? 0) && i.IsActive && i.Kind == FeeItem.Session && i.SessionType == req.SessionType))
                return new { message = $"There is already a monthly fee for {req.SessionType}. Change that one, or switch it off first.", field = "sessionType" };
        }
        if (await _db.FeeItems.AnyAsync(i => i.Id != (id ?? 0) && i.Name.ToLower() == name.ToLower()))
            return new { message = $"There is already a fee item called {name}.", field = "name" };
        return null;
    }

    private static void ApplyItem(FeeItem item, FeeItemRequest req)
    {
        item.Name        = req.Name!.Trim();
        item.Kind        = req.Kind;
        item.SessionType = req.Kind == FeeItem.Session ? req.SessionType : null;
        item.Amount      = Math.Round(req.Amount, 2);
        item.SortOrder   = req.SortOrder;
        item.IsActive    = req.IsActive;
    }

    private static string MonthName(FeeInvoice i) => new DateTime(i.Year, i.Month, 1).ToString("MMMM yyyy", Money);
    internal static string Rm(decimal v) => "RM " + v.ToString("#,##0.00", Money);

    private Task Audit(string action, string entity, int id, string description) =>
        _audit.LogAsync(action, entity, id.ToString(), description, User.Identity?.Name ?? "unknown",
            int.TryParse(User.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value, out var uid) ? uid : null,
            null, null, HttpContext.Connection.RemoteIpAddress?.ToString());
}

public class FeeItemRequest
{
    [StringLength(100)] public string? Name { get; set; }
    public string Kind { get; set; } = FeeItem.Session;
    public string? SessionType { get; set; }
    public decimal Amount { get; set; }
    public int SortOrder { get; set; }
    public bool IsActive { get; set; } = true;
}

public class AddOnsRequest { public List<int>? FeeItemIds { get; set; } }

public class FeeSettingsRequest
{
    public decimal SiblingDiscountPercent { get; set; }
    public int FeeDueDay { get; set; } = 7;
    [StringLength(1000)] public string? FeePaymentInstructions { get; set; }
}

public class GenerateInvoicesRequest
{
    public int Year { get; set; }
    public int Month { get; set; }
}

public class InvoiceLineRequest
{
    [StringLength(150)] public string? Description { get; set; }
    public decimal Amount { get; set; }
    public int? FeeItemId { get; set; }
}

public class UpdateInvoiceRequest
{
    public List<InvoiceLineRequest>? Lines { get; set; }
    public DateTime? DueDate { get; set; }
    [StringLength(500)] public string? Notes { get; set; }
}

public class VoidInvoiceRequest { [StringLength(300)] public string? Reason { get; set; } }

public class SendInvoicesRequest
{
    public int Year { get; set; }
    public int Month { get; set; }
    /// <summary>Only this class (when sending a month's invoices).</summary>
    public int? ClassId { get; set; }
    public List<int>? InvoiceIds { get; set; }
    /// <summary>Also send again the chosen invoices that were sent before.</summary>
    public bool Resend { get; set; }
}

/// <summary>A parent's "I've paid" (multipart, with an optional slip photo or PDF).</summary>
public class PaymentClaimForm
{
    public decimal Amount { get; set; }
    public DateTime? PaidOn { get; set; }
    public string? Method { get; set; }
    [StringLength(100)] public string? Reference { get; set; }
    [StringLength(500)] public string? Note { get; set; }
    public IFormFile? File { get; set; }
}

/// <summary>Corrections the office may make when confirming (empty = as the parent reported).</summary>
public class ConfirmClaimRequest
{
    public decimal? Amount { get; set; }
    public DateTime? PaidOn { get; set; }
    public string? Method { get; set; }
    [StringLength(100)] public string? Reference { get; set; }
}

/// <summary>A reported payment as listed (without the slip itself).</summary>
public class ClaimView
{
    public int Id { get; set; }
    public int InvoiceId { get; set; }
    public string InvoiceNo { get; set; } = "";
    public string StudentName { get; set; } = "";
    public string? ClassName { get; set; }
    public int Year { get; set; }
    public int Month { get; set; }
    public decimal InvoiceBalance { get; set; }
    public decimal Amount { get; set; }
    public DateTime PaidOn { get; set; }
    public string Method { get; set; } = "";
    public string? Reference { get; set; }
    public string? Note { get; set; }
    public bool HasSlip { get; set; }
    public string? SlipName { get; set; }
    public bool SlipIsPdf { get; set; }
    public string Status { get; set; } = "";
    public string? RejectReason { get; set; }
    public string CreatedByName { get; set; } = "";
    public DateTime CreatedAt { get; set; }
    public string? ReviewedByName { get; set; }
    public DateTime? ReviewedAt { get; set; }

    public static readonly System.Linq.Expressions.Expression<Func<FeePaymentClaim, ClaimView>> Projection = c => new ClaimView
    {
        Id = c.Id, InvoiceId = c.InvoiceId, InvoiceNo = c.Invoice.InvoiceNo, StudentName = c.Invoice.Student.FullName,
        ClassName = c.Invoice.Student.Class != null ? c.Invoice.Student.Class.Name : null,
        Year = c.Invoice.Year, Month = c.Invoice.Month,
        InvoiceBalance = c.Invoice.Status == FeeInvoice.Void ? 0 : (c.Invoice.Total > c.Invoice.AmountPaid ? c.Invoice.Total - c.Invoice.AmountPaid : 0),
        Amount = c.Amount, PaidOn = c.PaidOn, Method = c.Method, Reference = c.Reference, Note = c.Note,
        HasSlip = c.SlipData != null, SlipName = c.SlipName, SlipIsPdf = c.SlipContentType == "application/pdf",
        Status = c.Status, RejectReason = c.RejectReason, CreatedByName = c.CreatedByName, CreatedAt = c.CreatedAt,
        ReviewedByName = c.ReviewedByName, ReviewedAt = c.ReviewedAt
    };
}

public class PaymentRequest
{
    public decimal Amount { get; set; }
    public DateTime? PaidOn { get; set; }
    public string Method { get; set; } = "Cash";
    [StringLength(100)] public string? Reference { get; set; }
}
