using HrmsApi.Data;
using HrmsApi.Models;
using Microsoft.EntityFrameworkCore;

namespace HrmsApi.Services;

/// <summary>Statutory amounts for one employee for one month, with the rates that produced them.</summary>
public record StatutoryResult(
    decimal EpfEmployeeRate,
    decimal EpfEmployerRate,
    decimal EpfEmployee,
    decimal EpfEmployer,
    decimal SocsoEmployee,
    decimal SocsoEmployer,
    decimal EisEmployee,
    decimal EisEmployer,
    decimal Pcb);

/// <summary>
/// Calculates EPF, SOCSO, EIS and PCB from a <see cref="StatutoryRateSet"/>.
/// Pure functions — no database access — so the rules are easy to test.
/// </summary>
public static class StatutoryCalculator
{
    public static StatutoryResult Calculate(
        StatutoryRateSet rates, decimal monthlyWage,
        decimal? epfEmployeeRateOverride = null, decimal? epfEmployerRateOverride = null)
    {
        var wage = Math.Max(0m, monthlyWage);

        var epfEmployeeRate = epfEmployeeRateOverride ?? rates.EpfEmployeeRate;
        var epfEmployerRate = epfEmployerRateOverride
            ?? (wage <= rates.EpfEmployerThreshold ? rates.EpfEmployerRate : rates.EpfEmployerRateAboveThreshold);

        var epfEmployee = Percent(wage, epfEmployeeRate);
        var epfEmployer = Percent(wage, epfEmployerRate);

        var (socsoEmployee, socsoEmployer) = Socso(rates.GetSocsoBands(), wage);

        var eisWage     = rates.EisWageCeiling > 0 ? Math.Min(wage, rates.EisWageCeiling) : wage;
        var eisEmployee = Percent(eisWage, rates.EisEmployeeRate);
        var eisEmployer = Percent(eisWage, rates.EisEmployerRate);

        var pcb = Pcb(rates, wage, epfEmployee);

        return new StatutoryResult(epfEmployeeRate, epfEmployerRate, epfEmployee, epfEmployer,
                                   socsoEmployee, socsoEmployer, eisEmployee, eisEmployer, pcb);
    }

    private static decimal Percent(decimal amount, decimal percent) =>
        Math.Round(amount * percent / 100m, 2);

    /// <summary>Looks up the band for the wage; wages above the last bounded band use the open-ended band.</summary>
    public static (decimal Employee, decimal Employer) Socso(IReadOnlyList<SocsoBand> bands, decimal wage)
    {
        if (wage <= 0 || bands.Count == 0) return (0m, 0m);
        foreach (var band in bands)
            if (band.UpTo is null || wage <= band.UpTo.Value)
                return (band.Employee, band.Employer);
        var last = bands[^1];
        return (last.Employee, last.Employer);
    }

    /// <summary>
    /// Monthly PCB = annual tax ÷ 12, where annual chargeable income =
    /// (wage × 12) − (employee EPF × 12) − personal relief, taxed band by band.
    /// </summary>
    public static decimal Pcb(StatutoryRateSet rates, decimal monthlyWage, decimal monthlyEpf)
    {
        if (monthlyWage <= 0) return 0m;
        var chargeable = monthlyWage * 12m - monthlyEpf * 12m - rates.TaxPersonalRelief;
        return Math.Round(AnnualTax(rates.GetTaxBands(), chargeable) / 12m, 2);
    }

    public static decimal AnnualTax(IReadOnlyList<TaxBand> bands, decimal chargeable)
    {
        if (chargeable <= 0) return 0m;
        decimal tax = 0m, lower = 0m;
        foreach (var band in bands)
        {
            var upper = band.UpTo ?? decimal.MaxValue;
            if (chargeable > lower)
                tax += (Math.Min(chargeable, upper) - lower) * band.Rate / 100m;
            if (chargeable <= upper) break;
            lower = upper;
        }
        return tax;
    }

    /// <summary>Checks a rate set request; returns a list of problems (empty when valid).</summary>
    public static List<string> Validate(StatutoryRateSetRequest r)
    {
        var errors = new List<string>();
        if (string.IsNullOrWhiteSpace(r.Name)) errors.Add("Name is required.");
        if (r.EffectiveFrom.Year < 1990) errors.Add("Effective-from date is required.");

        void Pct(string label, decimal v) { if (v < 0 || v > 100) errors.Add($"{label} must be between 0 and 100%."); }
        Pct("EPF employee rate", r.EpfEmployeeRate);
        Pct("EPF employer rate", r.EpfEmployerRate);
        Pct("EPF employer rate above threshold", r.EpfEmployerRateAboveThreshold);
        Pct("EIS employee rate", r.EisEmployeeRate);
        Pct("EIS employer rate", r.EisEmployerRate);
        if (r.EpfEmployerThreshold < 0) errors.Add("EPF employer threshold cannot be negative.");
        if (r.EisWageCeiling < 0) errors.Add("EIS wage ceiling cannot be negative.");
        if (r.TaxPersonalRelief < 0) errors.Add("Personal relief cannot be negative.");

        CheckBands("SOCSO", r.SocsoBands.Select(b => b.UpTo).ToList(), errors);
        if (r.SocsoBands.Any(b => b.Employee < 0 || b.Employer < 0))
            errors.Add("SOCSO amounts cannot be negative.");

        CheckBands("Tax", r.TaxBands.Select(b => b.UpTo).ToList(), errors);
        foreach (var b in r.TaxBands) Pct("Tax band rate", b.Rate);

        return errors.Distinct().ToList();
    }

    private static void CheckBands(string label, List<decimal?> upTos, List<string> errors)
    {
        if (upTos.Count == 0) { errors.Add($"{label} table needs at least one row."); return; }
        if (upTos[^1] is not null) errors.Add($"The last {label} row must be open-ended (leave 'Up to' empty).");
        if (upTos.Take(upTos.Count - 1).Any(u => u is null))
            errors.Add($"Only the last {label} row can be open-ended.");
        var bounded = upTos.Where(u => u is not null).Select(u => u!.Value).ToList();
        for (int i = 1; i < bounded.Count; i++)
            if (bounded[i] <= bounded[i - 1]) { errors.Add($"{label} 'Up to' values must increase row by row."); break; }
        if (bounded.Any(u => u <= 0)) errors.Add($"{label} 'Up to' values must be above zero.");
    }
}

/// <summary>Finds the statutory rate set in force for a payroll month.</summary>
public static class StatutoryRates
{
    /// <summary>
    /// Latest rate set starting on or before the first day of the month. If the company has
    /// none at all (local dev databases, tests), the initial defaults are created first.
    /// </summary>
    public static async Task<StatutoryRateSet?> ForMonthAsync(HrmsDbContext db, int month, int year)
    {
        await EnsureDefaultAsync(db);
        var monthStart = new DateTime(year, month, 1);
        return await db.StatutoryRateSets
            .Where(r => r.EffectiveFrom <= monthStart)
            .OrderByDescending(r => r.EffectiveFrom)
            .FirstOrDefaultAsync();
    }

    public static async Task EnsureDefaultAsync(HrmsDbContext db)
    {
        if (await db.StatutoryRateSets.AnyAsync()) return;
        var set = StatutoryRateDefaults.Create();
        set.Id = 0; // let the database assign the key
        db.StatutoryRateSets.Add(set);
        await db.SaveChangesAsync();
    }
}
