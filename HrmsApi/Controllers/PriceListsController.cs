using System.Globalization;
using HrmsApi.Data;
using HrmsApi.Models;
using HrmsApi.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace HrmsApi.Controllers;

/// <summary>
/// School → Fees → Price lists (one per academic year, e.g. "Price &amp; Terms 2027") and deposits.
///   Admins: create a year's price list (copied from the last one), change its sessions (hours,
///   meals, monthly fee) and charges (one-time, twice a year, refundable deposit), print it.
///   Everyone in the school (staff and parents): the price list in force, and its PDF.
///   Deposits: the ones the school holds; refund, or deduct from an unpaid invoice.
/// Invoices use the price list in force for their month (FeesController.Generate); the session
/// hours also drive the school-day timings (late, automatic check-out).
/// </summary>
[ApiController]
[Route("api/school/fees")]
[Authorize]
[RequiresSchoolFeatures]
public class PriceListsController : ControllerBase
{
    private readonly HrmsDbContext _db;
    private readonly ICompanySettingsService _settings;
    private readonly IAuditService _audit;

    public PriceListsController(HrmsDbContext db, ICompanySettingsService settings, IAuditService audit)
    {
        _db = db; _settings = settings; _audit = audit;
    }

    private static readonly CultureInfo Inv = CultureInfo.InvariantCulture;

    // ── Price lists ──

    /// <summary>GET /api/school/fees/price-lists — every year's price list, newest first (admins).</summary>
    [HttpGet("price-lists")]
    [Authorize(Roles = UserAccess.Admin)]
    public async Task<IActionResult> List()
    {
        var current = await FeePrices.ForDateAsync(_db, SchoolClock.Today);
        var lists = await _db.FeePriceLists.AsNoTracking().Include(p => p.Sessions).Include(p => p.Charges)
            .OrderByDescending(p => p.EffectiveFrom).ToListAsync();
        return Ok(lists.Select(p => Dto(p, p.Id == current?.Id)));
    }

    /// <summary>GET /api/school/fees/price-lists/current — the price list in force today (anyone in the school, parents too).</summary>
    [HttpGet("price-lists/current")]
    public async Task<IActionResult> Current()
    {
        var me = await SchoolViewer.LoadAsync(_db, User);
        if (me == null || (!me.IsStaff && !me.IsParent)) return Forbid();
        var list = await FeePrices.ForDateAsync(_db, SchoolClock.Today);
        return list == null ? Ok(null) : Ok(Dto(list, true));
    }

    /// <summary>GET /api/school/fees/price-lists/{id}/pdf — "Price &amp; Terms" PDF (admins; parents: the current one).</summary>
    [HttpGet("price-lists/{id:int}/pdf")]
    public async Task<IActionResult> Pdf(int id)
    {
        var me = await SchoolViewer.LoadAsync(_db, User);
        if (me == null || (!me.IsStaff && !me.IsParent)) return Forbid();
        var list = await _db.FeePriceLists.AsNoTracking().Include(p => p.Sessions).Include(p => p.Charges).FirstOrDefaultAsync(p => p.Id == id)
                   ?? throw new KeyNotFoundException("Price list not found.");
        if (!me.IsAdmin && (await FeePrices.ForDateAsync(_db, SchoolClock.Today))?.Id != id) return Forbid();
        var pdf = FeePdf.PriceTerms(await _settings.GetAsync(), list);
        return File(pdf, "application/pdf", $"Price-and-Terms-{list.Name.Replace('/', '-').Replace(' ', '-')}.pdf");
    }

    /// <summary>
    /// POST /api/school/fees/price-lists { name, effectiveFrom, copyFromId? } — a new year's price list,
    /// copied from another (default: the newest) so only the changes need typing. Without any to copy,
    /// it starts with Half day 8:00–12:00, Full day 7:30–18:30 and (not offered) Daycare.
    /// </summary>
    [HttpPost("price-lists")]
    [Authorize(Roles = UserAccess.Admin)]
    public async Task<IActionResult> Create([FromBody] NewPriceListRequest req)
    {
        var name = (req.Name ?? "").Trim();
        if (name.Length == 0) return BadRequest(new { message = "Give the price list a name, e.g. \"2027\".", field = "name" });
        if (req.EffectiveFrom == null) return BadRequest(new { message = "Choose the date these prices start.", field = "effectiveFrom" });
        var from = req.EffectiveFrom.Value.Date;
        if (await _db.FeePriceLists.AnyAsync(p => p.EffectiveFrom == from))
            return BadRequest(new { message = $"Another price list already starts on {from:d MMM yyyy}.", field = "effectiveFrom" });

        var source = req.CopyFromId != null
            ? await _db.FeePriceLists.AsNoTracking().Include(p => p.Sessions).Include(p => p.Charges).FirstOrDefaultAsync(p => p.Id == req.CopyFromId)
            : await _db.FeePriceLists.AsNoTracking().Include(p => p.Sessions).Include(p => p.Charges).OrderByDescending(p => p.EffectiveFrom).FirstOrDefaultAsync();

        var list = new FeePriceList { Name = name, EffectiveFrom = from, TwiceAYearMonths = source?.TwiceAYearMonths ?? "1,7", Terms = source?.Terms };
        if (source != null)
        {
            list.Sessions.AddRange(source.Sessions.Select(s => new FeePriceSession
                { SessionType = s.SessionType, Offered = s.Offered, Start = s.Start, End = s.End, MealsIncluded = s.MealsIncluded, MonthlyFee = s.MonthlyFee }));
            list.Charges.AddRange(source.Charges.Select(c => new FeePriceCharge
                { Name = c.Name, Kind = c.Kind, Amount = c.Amount, SessionType = c.SessionType, SortOrder = c.SortOrder }));
        }
        // Every session type has a row (Daycare is optional: not offered until switched on)
        foreach (var t in Student.SessionTypes.Where(t => list.Sessions.All(s => s.SessionType != t)))
            list.Sessions.Add(t switch
            {
                Student.HalfDay => new FeePriceSession { SessionType = t, Start = "08:00", End = "12:00", MealsIncluded = "breakfast" },
                Student.FullDay => new FeePriceSession { SessionType = t, Start = "07:30", End = "18:30", MealsIncluded = "breakfast, lunch & tea-break" },
                _ => new FeePriceSession { SessionType = t, Offered = false, Start = "07:30", End = "18:30" }
            });

        _db.FeePriceLists.Add(list);
        await _db.SaveChangesAsync();
        await Audit("Created", list.Id, $"Created price list {list.Name} (from {list.EffectiveFrom:d MMM yyyy})" + (source != null ? $", copied from {source.Name}" : ""));
        return Ok(Dto(list, false));
    }

    /// <summary>PUT /api/school/fees/price-lists/{id} — the whole price list: name, start date, twice-a-year months, terms, sessions and charges.</summary>
    [HttpPut("price-lists/{id:int}")]
    [Authorize(Roles = UserAccess.Admin)]
    public async Task<IActionResult> Update(int id, [FromBody] PriceListRequest req)
    {
        var list = await _db.FeePriceLists.Include(p => p.Sessions).Include(p => p.Charges).FirstOrDefaultAsync(p => p.Id == id)
                   ?? throw new KeyNotFoundException("Price list not found.");
        var error = await ValidateAsync(req, id);
        if (error != null) return BadRequest(error);

        list.Name = req.Name!.Trim();
        list.EffectiveFrom = req.EffectiveFrom!.Value.Date;
        list.TwiceAYearMonths = string.Join(",", FeePrices.Months(req.TwiceAYearMonths));
        list.Terms = string.IsNullOrWhiteSpace(req.Terms) ? null : req.Terms.Trim();
        list.UpdatedAt = DateTime.UtcNow;

        _db.FeePriceSessions.RemoveRange(list.Sessions);
        _db.FeePriceCharges.RemoveRange(list.Charges);
        list.Sessions = req.Sessions!.Select(s => new FeePriceSession
        {
            SessionType = s.SessionType!, Offered = s.Offered, Start = s.Start!.Trim(), End = s.End!.Trim(),
            MealsIncluded = string.IsNullOrWhiteSpace(s.MealsIncluded) ? null : s.MealsIncluded.Trim(), MonthlyFee = s.MonthlyFee
        }).ToList();
        list.Charges = (req.Charges ?? new()).Select((c, i) => new FeePriceCharge
        {
            Name = c.Name!.Trim(), Kind = c.Kind!, Amount = c.Amount,
            SessionType = string.IsNullOrWhiteSpace(c.SessionType) ? null : c.SessionType, SortOrder = i
        }).ToList();
        await _db.SaveChangesAsync();
        await Audit("Updated", list.Id, $"Updated price list {list.Name}: " +
            string.Join(", ", list.Sessions.Where(s => s.Offered).Select(s => $"{s.SessionType} {s.Start}–{s.End} RM {s.MonthlyFee.ToString("0.00", Inv)}")));
        return Ok(Dto(list, (await FeePrices.ForDateAsync(_db, SchoolClock.Today))?.Id == list.Id));
    }

    /// <summary>DELETE /api/school/fees/price-lists/{id} — only one that hasn't started yet.</summary>
    [HttpDelete("price-lists/{id:int}")]
    [Authorize(Roles = UserAccess.Admin)]
    public async Task<IActionResult> Delete(int id)
    {
        var list = await _db.FeePriceLists.FindAsync(id) ?? throw new KeyNotFoundException("Price list not found.");
        if (list.EffectiveFrom <= SchoolClock.Today)
            return BadRequest(new { message = "This price list is already in use for invoices. Create a new one for the coming year instead." });
        _db.FeePriceLists.Remove(list);
        await _db.SaveChangesAsync();
        await Audit("Deleted", id, $"Deleted price list {list.Name}");
        return NoContent();
    }

    private async Task<object?> ValidateAsync(PriceListRequest req, int id)
    {
        if (string.IsNullOrWhiteSpace(req.Name)) return new { message = "Give the price list a name, e.g. \"2027\".", field = "name" };
        if (req.EffectiveFrom == null) return new { message = "Choose the date these prices start.", field = "effectiveFrom" };
        var from = req.EffectiveFrom.Value.Date;
        if (await _db.FeePriceLists.AnyAsync(p => p.Id != id && p.EffectiveFrom == from))
            return new { message = $"Another price list already starts on {from:d MMM yyyy}.", field = "effectiveFrom" };

        var sessions = req.Sessions ?? new();
        if (!sessions.Any(s => s.Offered)) return new { message = "Offer at least one session (half day, full day or daycare).", field = "sessions" };
        foreach (var s in sessions)
        {
            if (!Student.SessionTypes.Contains(s.SessionType)) return new { message = "Unknown session.", field = "sessions" };
            if (sessions.Count(x => x.SessionType == s.SessionType) > 1) return new { message = $"{s.SessionType} is listed twice.", field = "sessions" };
            if (!s.Offered) { s.Start ??= "07:30"; s.End ??= "18:30"; continue; }
            if (!SchoolTimes.IsValid(s.Start) || !SchoolTimes.IsValid(s.End))
                return new { message = $"{s.SessionType}: enter the hours like 08:00 and 12:00.", field = "sessions" };
            if (SchoolTimes.Parse(s.End, default) <= SchoolTimes.Parse(s.Start, default))
                return new { message = $"{s.SessionType}: the end time must be after the start time.", field = "sessions" };
            if (s.MonthlyFee <= 0) return new { message = $"{s.SessionType}: enter the monthly fee.", field = "sessions" };
        }
        foreach (var c in req.Charges ?? new())
        {
            if (string.IsNullOrWhiteSpace(c.Name)) return new { message = "Every charge needs a name.", field = "charges" };
            if (!FeePriceCharge.Kinds.Contains(c.Kind)) return new { message = $"{c.Name}: choose one-time, twice a year or deposit.", field = "charges" };
            if (c.Amount <= 0) return new { message = $"{c.Name}: enter the amount.", field = "charges" };
            if (!string.IsNullOrWhiteSpace(c.SessionType) && !Student.SessionTypes.Contains(c.SessionType))
                return new { message = $"{c.Name}: unknown session.", field = "charges" };
        }
        if ((req.Charges ?? new()).Any(c => c.Kind == FeePriceCharge.TwiceAYear) && FeePrices.Months(req.TwiceAYearMonths).Length == 0)
            return new { message = "Choose the months the twice-a-year charges are billed (e.g. January and July).", field = "twiceAYearMonths" };
        return null;
    }

    /// <summary>The price list, plus per session what a new child pays at registration and in the 2nd month.</summary>
    private static object Dto(FeePriceList p, bool current) => new
    {
        p.Id, p.Name, effectiveFrom = p.EffectiveFrom.ToString("yyyy-MM-dd"), p.TwiceAYearMonths, p.Terms, current,
        sessions = p.Sessions.OrderBy(s => Array.IndexOf(Student.SessionTypes, s.SessionType)).Select(s => new
        {
            s.SessionType, s.Offered, s.Start, s.End, s.MealsIncluded, s.MonthlyFee,
            uponRegistration = s.MonthlyFee + p.Charges.Where(c => c.Kind != FeePriceCharge.Deposit && FeePrices.AppliesTo(c, s.SessionType)).Sum(c => c.Amount),
            secondMonth = s.MonthlyFee + p.Charges.Where(c => c.Kind == FeePriceCharge.Deposit && FeePrices.AppliesTo(c, s.SessionType)).Sum(c => c.Amount)
        }),
        charges = p.Charges.OrderBy(c => c.SortOrder).ThenBy(c => c.Id).Select(c => new { c.Id, c.Name, c.Kind, c.Amount, c.SessionType })
    };

    // ── Deposits ──

    /// <summary>GET /api/school/fees/deposits?status=Held — deposits the school holds (default) or "all".</summary>
    [HttpGet("deposits")]
    [Authorize(Roles = UserAccess.Admin)]
    public async Task<IActionResult> Deposits([FromQuery] string? status)
    {
        var q = _db.StudentDeposits.AsNoTracking().AsQueryable();
        if (!string.Equals(status, "all", StringComparison.OrdinalIgnoreCase)) q = q.Where(d => d.Status == StudentDeposit.Held);
        return Ok(await q.OrderBy(d => d.Student.FullName).Select(d => new
        {
            d.Id, d.StudentId, childName = d.Student.FullName, className = d.Student.Class != null ? d.Student.Class.Name : null,
            childActive = d.Student.IsActive, d.Description, d.Amount, d.Status, d.CreatedAt, d.SettledAt, d.SettledByName, d.Note,
            invoiceNo = _db.FeeInvoices.Where(i => i.Id == d.InvoiceId).Select(i => i.InvoiceNo).FirstOrDefault(),
            invoicePaid = _db.FeeInvoices.Where(i => i.Id == d.InvoiceId).Select(i => i.Status == FeeInvoice.Paid).FirstOrDefault(),
            // The child's unpaid invoices, to deduct the deposit from
            openInvoices = _db.FeeInvoices
                .Where(i => i.StudentId == d.StudentId && (i.Status == FeeInvoice.Unpaid || i.Status == FeeInvoice.Partial))
                .OrderByDescending(i => i.Year).ThenByDescending(i => i.Month)
                .Select(i => new { i.Id, i.InvoiceNo, i.Year, i.Month, balance = i.Total - i.AmountPaid }).ToList()
        }).ToListAsync());
    }

    /// <summary>
    /// POST /api/school/fees/deposits/{id}/settle { how: "refund" | "deduct", invoiceId?, note? } —
    /// refunded (cash / transfer, with a note), or deducted from one of the child's unpaid invoices.
    /// </summary>
    [HttpPost("deposits/{id:int}/settle")]
    [Authorize(Roles = UserAccess.Admin)]
    public async Task<IActionResult> Settle(int id, [FromBody] SettleDepositRequest req)
    {
        var d = await _db.StudentDeposits.Include(x => x.Student).FirstOrDefaultAsync(x => x.Id == id)
                ?? throw new KeyNotFoundException("Deposit not found.");
        if (d.Status != StudentDeposit.Held) return BadRequest(new { message = "This deposit was already settled." });
        var me = (await SchoolViewer.LoadAsync(_db, User))?.Name ?? User.Identity?.Name ?? "Office";
        var note = string.IsNullOrWhiteSpace(req.Note) ? null : req.Note.Trim()[..Math.Min(req.Note.Trim().Length, 300)];

        if (req.How == "deduct")
        {
            var inv = await _db.FeeInvoices.Include(i => i.Lines).Include(i => i.Payments)
                .FirstOrDefaultAsync(i => i.Id == req.InvoiceId && i.StudentId == d.StudentId);
            if (inv == null) return BadRequest(new { message = $"Choose one of {d.Student.FullName}'s invoices.", field = "invoiceId" });
            if (inv.Status is FeeInvoice.Void or FeeInvoice.Paid) return BadRequest(new { message = $"Invoice {inv.InvoiceNo} is {inv.Status.ToLower()}. Choose an unpaid one.", field = "invoiceId" });
            inv.Lines.Add(new FeeInvoiceLine
            {
                Description = $"{d.Description} returned", Amount = -d.Amount,
                SortOrder = inv.Lines.Count == 0 ? 0 : inv.Lines.Max(l => l.SortOrder) + 1
            });
            inv.Recalculate();
            d.Status = StudentDeposit.Deducted;
            d.DeductedInvoiceId = inv.Id;
            d.Note = note ?? $"Deducted from invoice {inv.InvoiceNo}";
        }
        else if (req.How == "refund")
        {
            d.Status = StudentDeposit.Refunded;
            d.Note = note;
        }
        else return BadRequest(new { message = "Choose refund or deduct from an invoice." });

        d.SettledAt = DateTime.UtcNow;
        d.SettledByName = me;
        await _db.SaveChangesAsync();
        await Audit("Updated", d.Id, $"Deposit of {d.Student.FullName} (RM {d.Amount.ToString("0.00", Inv)}) {d.Status.ToLower()}" + (d.Note != null ? $": {d.Note}" : ""));
        return Ok(new { d.Id, d.Status, d.Note });
    }

    private Task Audit(string action, int id, string description) =>
        _audit.LogAsync(action, "FeePriceList", id.ToString(), description, User.Identity?.Name ?? "unknown",
            int.TryParse(User.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value, out var uid) ? uid : null,
            null, null, HttpContext.Connection.RemoteIpAddress?.ToString());
}

public class NewPriceListRequest
{
    public string? Name { get; set; }
    public DateTime? EffectiveFrom { get; set; }
    /// <summary>Copy sessions and charges from this price list (default: the newest).</summary>
    public int? CopyFromId { get; set; }
}

public class PriceListRequest
{
    public string? Name { get; set; }
    public DateTime? EffectiveFrom { get; set; }
    /// <summary>"1,7"</summary>
    public string? TwiceAYearMonths { get; set; }
    public string? Terms { get; set; }
    public List<PriceSessionRequest>? Sessions { get; set; }
    public List<PriceChargeRequest>? Charges { get; set; }
}

public class PriceSessionRequest
{
    public string? SessionType { get; set; }
    public bool Offered { get; set; } = true;
    public string? Start { get; set; }
    public string? End { get; set; }
    public string? MealsIncluded { get; set; }
    public decimal MonthlyFee { get; set; }
}

public class PriceChargeRequest
{
    public string? Name { get; set; }
    /// <summary>OneTime, TwiceAYear or Deposit.</summary>
    public string? Kind { get; set; }
    public decimal Amount { get; set; }
    /// <summary>Only for this session; null = every child.</summary>
    public string? SessionType { get; set; }
}

public class SettleDepositRequest
{
    /// <summary>"refund" or "deduct".</summary>
    public string? How { get; set; }
    public int? InvoiceId { get; set; }
    public string? Note { get; set; }
}
