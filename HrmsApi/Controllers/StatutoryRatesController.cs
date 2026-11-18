using System.Security.Claims;
using System.Text.Json;
using HrmsApi.Data;
using HrmsApi.Models;
using HrmsApi.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace HrmsApi.Controllers;

/// <summary>
/// Master → Statutory Rates: EPF, SOCSO, EIS and PCB rates by effective date, per company.
/// Payroll uses the latest set starting on or before the payroll month; each payroll keeps
/// a snapshot of what it used, so changing or adding rates never alters past payrolls.
/// </summary>
[ApiController]
[Route("api/[controller]")]
[Authorize]
public class StatutoryRatesController : ControllerBase
{
    private readonly HrmsDbContext _db;
    private readonly IAuditService _audit;

    public StatutoryRatesController(HrmsDbContext db, IAuditService audit)
    {
        _db    = db;
        _audit = audit;
    }

    /// <summary>GET /api/statutoryrates — all rate sets, newest first.</summary>
    [HttpGet]
    public async Task<IActionResult> GetAll()
    {
        await StatutoryRates.EnsureDefaultAsync(_db);
        var sets = await _db.StatutoryRateSets.OrderByDescending(r => r.EffectiveFrom).ToListAsync();
        var usage = await _db.Payrolls
            .Where(p => p.StatutoryRateSetId != null)
            .GroupBy(p => p.StatutoryRateSetId)
            .Select(g => new { Id = g.Key, Count = g.Count() })
            .ToDictionaryAsync(x => x.Id!.Value, x => x.Count);

        var today = DateTime.Today;
        var currentId = sets.FirstOrDefault(s => s.EffectiveFrom <= today)?.Id;

        return Ok(sets.Select(s => ToDto(s, usage.GetValueOrDefault(s.Id), s.Id == currentId)));
    }

    /// <summary>GET /api/statutoryrates/{id}</summary>
    [HttpGet("{id:int}")]
    public async Task<IActionResult> GetById(int id)
    {
        var set = await _db.StatutoryRateSets.FindAsync(id);
        if (set is null) return NotFound(new { message = "Rate set not found." });
        var used = await _db.Payrolls.CountAsync(p => p.StatutoryRateSetId == id);
        return Ok(ToDto(set, used, false));
    }

    /// <summary>GET /api/statutoryrates/for-month?month=11&amp;year=2026 — the rate set payroll would use.</summary>
    [HttpGet("for-month")]
    public async Task<IActionResult> ForMonth([FromQuery] int month, [FromQuery] int year)
    {
        if (month is < 1 or > 12 || year < 1990) return BadRequest(new { message = "Invalid month or year." });
        var set = await StatutoryRates.ForMonthAsync(_db, month, year);
        if (set is null) return NotFound(new { message = "No statutory rates apply to this month." });
        return Ok(ToDto(set, 0, false));
    }

    /// <summary>POST /api/statutoryrates/preview — try the rates on a monthly wage without saving.</summary>
    [HttpPost("preview")]
    [Authorize(Roles = "Admin")]
    public IActionResult Preview([FromBody] StatutoryPreviewRequest request)
    {
        var errors = StatutoryCalculator.Validate(request.Rates);
        if (errors.Count > 0) return BadRequest(new { message = errors[0], errors });

        var set = FromRequest(new StatutoryRateSet(), request.Rates);
        var r = StatutoryCalculator.Calculate(set, request.Wage);
        return Ok(new
        {
            wage = request.Wage,
            r.EpfEmployeeRate, r.EpfEmployerRate,
            epfEmployee = r.EpfEmployee, epfEmployer = r.EpfEmployer,
            socsoEmployee = r.SocsoEmployee, socsoEmployer = r.SocsoEmployer,
            eisEmployee = r.EisEmployee, eisEmployer = r.EisEmployer,
            pcb = r.Pcb,
            totalEmployeeDeductions = r.EpfEmployee + r.SocsoEmployee + r.EisEmployee + r.Pcb,
            netPay = request.Wage - (r.EpfEmployee + r.SocsoEmployee + r.EisEmployee + r.Pcb),
            totalEmployerCost = r.EpfEmployer + r.SocsoEmployer + r.EisEmployer,
        });
    }

    /// <summary>POST /api/statutoryrates — add a rate set (Admin).</summary>
    [HttpPost]
    [Authorize(Roles = "Admin")]
    public async Task<IActionResult> Create([FromBody] StatutoryRateSetRequest request)
    {
        var errors = StatutoryCalculator.Validate(request);
        if (errors.Count > 0) return BadRequest(new { message = errors[0], errors });

        var from = request.EffectiveFrom.Date;
        if (await _db.StatutoryRateSets.AnyAsync(r => r.EffectiveFrom == from))
            return BadRequest(new { message = $"A rate set already starts on {from:dd MMM yyyy}. Edit it instead." });

        var set = FromRequest(new StatutoryRateSet { CreatedAt = DateTime.UtcNow }, request);
        _db.StatutoryRateSets.Add(set);
        await _db.SaveChangesAsync();

        await Audit("Created", set.Id, $"Added statutory rates \"{set.Name}\" effective {set.EffectiveFrom:dd MMM yyyy}",
            null, Snapshot(set));
        return CreatedAtAction(nameof(GetById), new { id = set.Id }, ToDto(set, 0, false));
    }

    /// <summary>PUT /api/statutoryrates/{id} — update a rate set (Admin). Existing payrolls keep the rates they used.</summary>
    [HttpPut("{id:int}")]
    [Authorize(Roles = "Admin")]
    public async Task<IActionResult> Update(int id, [FromBody] StatutoryRateSetRequest request)
    {
        var set = await _db.StatutoryRateSets.FindAsync(id);
        if (set is null) return NotFound(new { message = "Rate set not found." });

        var errors = StatutoryCalculator.Validate(request);
        if (errors.Count > 0) return BadRequest(new { message = errors[0], errors });

        var from = request.EffectiveFrom.Date;
        if (await _db.StatutoryRateSets.AnyAsync(r => r.Id != id && r.EffectiveFrom == from))
            return BadRequest(new { message = $"Another rate set already starts on {from:dd MMM yyyy}." });

        var before = Snapshot(set);
        FromRequest(set, request);
        set.UpdatedAt = DateTime.UtcNow;
        await _db.SaveChangesAsync();

        await Audit("Updated", set.Id, $"Updated statutory rates \"{set.Name}\" effective {set.EffectiveFrom:dd MMM yyyy}",
            before, Snapshot(set));
        var used = await _db.Payrolls.CountAsync(p => p.StatutoryRateSetId == id);
        return Ok(ToDto(set, used, false));
    }

    /// <summary>DELETE /api/statutoryrates/{id} — remove a rate set (Admin). The last one cannot be removed.</summary>
    [HttpDelete("{id:int}")]
    [Authorize(Roles = "Admin")]
    public async Task<IActionResult> Delete(int id)
    {
        var set = await _db.StatutoryRateSets.FindAsync(id);
        if (set is null) return NotFound(new { message = "Rate set not found." });

        if (await _db.StatutoryRateSets.CountAsync() <= 1)
            return BadRequest(new { message = "At least one rate set is needed for payroll. Edit this one instead." });

        var before = Snapshot(set);
        _db.StatutoryRateSets.Remove(set);
        await _db.SaveChangesAsync();

        await Audit("Deleted", id, $"Deleted statutory rates \"{set.Name}\" effective {set.EffectiveFrom:dd MMM yyyy}",
            before, null);
        return Ok(new { message = "Rate set deleted." });
    }

    // ── helpers ──────────────────────────────────────────────

    private static StatutoryRateSet FromRequest(StatutoryRateSet set, StatutoryRateSetRequest r)
    {
        set.Name                          = r.Name.Trim();
        set.EffectiveFrom                 = r.EffectiveFrom.Date;
        set.Notes                         = string.IsNullOrWhiteSpace(r.Notes) ? null : r.Notes.Trim();
        set.EpfEmployeeRate               = r.EpfEmployeeRate;
        set.EpfEmployerRate               = r.EpfEmployerRate;
        set.EpfEmployerRateAboveThreshold = r.EpfEmployerRateAboveThreshold;
        set.EpfEmployerThreshold          = r.EpfEmployerThreshold;
        set.EisEmployeeRate               = r.EisEmployeeRate;
        set.EisEmployerRate               = r.EisEmployerRate;
        set.EisWageCeiling                = r.EisWageCeiling;
        set.TaxPersonalRelief             = r.TaxPersonalRelief;
        set.SetSocsoBands(r.SocsoBands);
        set.SetTaxBands(r.TaxBands);
        return set;
    }

    private static object ToDto(StatutoryRateSet s, int payrollsUsing, bool isCurrent) => new
    {
        s.Id, s.Name, s.EffectiveFrom, s.Notes,
        s.EpfEmployeeRate, s.EpfEmployerRate, s.EpfEmployerRateAboveThreshold, s.EpfEmployerThreshold,
        socsoBands = s.GetSocsoBands(),
        s.EisEmployeeRate, s.EisEmployerRate, s.EisWageCeiling,
        s.TaxPersonalRelief,
        taxBands = s.GetTaxBands(),
        s.CreatedAt, s.UpdatedAt,
        payrollsUsing,
        isCurrent,
    };

    private static string Snapshot(StatutoryRateSet s) => JsonSerializer.Serialize(new
    {
        s.Name, s.EffectiveFrom, s.EpfEmployeeRate, s.EpfEmployerRate, s.EpfEmployerRateAboveThreshold,
        s.EpfEmployerThreshold, s.EisEmployeeRate, s.EisEmployerRate, s.EisWageCeiling, s.TaxPersonalRelief,
        s.SocsoBandsJson, s.TaxBandsJson,
    });

    private Task Audit(string action, int id, string description, string? oldValues, string? newValues)
    {
        var userId = int.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out var uid) ? uid : (int?)null;
        return _audit.LogAsync(action, "StatutoryRates", id.ToString(), description,
            User.Identity?.Name ?? "unknown", userId, oldValues, newValues,
            HttpContext.Connection.RemoteIpAddress?.ToString());
    }
}

public class StatutoryPreviewRequest
{
    public StatutoryRateSetRequest Rates { get; set; } = new();
    public decimal Wage { get; set; }
}
