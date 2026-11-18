using System.Text.Json;

namespace HrmsApi.Models;

/// <summary>
/// Malaysian statutory contribution and tax rates (EPF, SOCSO, EIS, PCB) that apply from
/// <see cref="EffectiveFrom"/> until the next rate set starts. Kept per company database and
/// maintained by HR under Master → Statutory Rates, so a rate change needs no code change.
/// Payroll uses the latest set whose EffectiveFrom is on or before the first day of the payroll month.
/// Percentages are stored as percent values (2 = 2%).
/// </summary>
public class StatutoryRateSet
{
    public int      Id            { get; set; }
    public string   Name          { get; set; } = string.Empty;
    /// <summary>First day these rates apply (date only).</summary>
    public DateTime EffectiveFrom { get; set; }
    public string?  Notes         { get; set; }

    // ── EPF (KWSP) ──────────────────────────────────────────
    /// <summary>Employee share, % of wage.</summary>
    public decimal EpfEmployeeRate               { get; set; }
    /// <summary>Employer share, % of wage, for wages up to <see cref="EpfEmployerThreshold"/>.</summary>
    public decimal EpfEmployerRate               { get; set; }
    /// <summary>Employer share, % of wage, for wages above <see cref="EpfEmployerThreshold"/>.</summary>
    public decimal EpfEmployerRateAboveThreshold { get; set; }
    /// <summary>Monthly wage (RM) at which the employer rate switches.</summary>
    public decimal EpfEmployerThreshold          { get; set; }

    // ── SOCSO (PERKESO) — contribution table ────────────────
    /// <summary>JSON array of <see cref="SocsoBand"/>; ascending, last band open-ended (UpTo = null).</summary>
    public string SocsoBandsJson { get; set; } = "[]";

    // ── EIS (SIP) ───────────────────────────────────────────
    public decimal EisEmployeeRate { get; set; }
    public decimal EisEmployerRate { get; set; }
    /// <summary>Wages above this (RM) are treated as this amount for EIS.</summary>
    public decimal EisWageCeiling  { get; set; }

    // ── PCB / MTD (income tax) ──────────────────────────────
    /// <summary>Annual personal relief (RM) deducted before the tax bands are applied.</summary>
    public decimal TaxPersonalRelief { get; set; }
    /// <summary>JSON array of <see cref="TaxBand"/> on annual chargeable income; ascending, last band open-ended.</summary>
    public string  TaxBandsJson      { get; set; } = "[]";

    public DateTime  CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime? UpdatedAt { get; set; }

    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);

    public List<SocsoBand> GetSocsoBands() =>
        JsonSerializer.Deserialize<List<SocsoBand>>(SocsoBandsJson, Json) ?? new();
    public void SetSocsoBands(IEnumerable<SocsoBand> bands) =>
        SocsoBandsJson = JsonSerializer.Serialize(bands, Json);

    public List<TaxBand> GetTaxBands() =>
        JsonSerializer.Deserialize<List<TaxBand>>(TaxBandsJson, Json) ?? new();
    public void SetTaxBands(IEnumerable<TaxBand> bands) =>
        TaxBandsJson = JsonSerializer.Serialize(bands, Json);
}

/// <summary>SOCSO amounts (RM) for monthly wages up to <see cref="UpTo"/> (null = and above).</summary>
public class SocsoBand
{
    public decimal? UpTo     { get; set; }
    public decimal  Employee { get; set; }
    public decimal  Employer { get; set; }
}

/// <summary>Tax rate (%) for annual chargeable income up to <see cref="UpTo"/> (null = and above).</summary>
public class TaxBand
{
    public decimal? UpTo { get; set; }
    public decimal  Rate { get; set; }
}

/// <summary>Create / update payload for a statutory rate set.</summary>
public class StatutoryRateSetRequest
{
    public string   Name          { get; set; } = string.Empty;
    public DateTime EffectiveFrom { get; set; }
    public string?  Notes         { get; set; }
    public decimal  EpfEmployeeRate               { get; set; }
    public decimal  EpfEmployerRate               { get; set; }
    public decimal  EpfEmployerRateAboveThreshold { get; set; }
    public decimal  EpfEmployerThreshold          { get; set; }
    public List<SocsoBand> SocsoBands { get; set; } = new();
    public decimal  EisEmployeeRate { get; set; }
    public decimal  EisEmployerRate { get; set; }
    public decimal  EisWageCeiling  { get; set; }
    public decimal  TaxPersonalRelief { get; set; }
    public List<TaxBand> TaxBands { get; set; } = new();
}

/// <summary>
/// The rates that were in force when the payroll system first stored them — identical to the
/// values previously hard-coded in PayrollCalculationService / PdfService, so existing payroll
/// results do not change. HR should review them under Master → Statutory Rates.
/// </summary>
public static class StatutoryRateDefaults
{
    public static readonly DateTime EffectiveFrom = new(2000, 1, 1);

    /// <summary>Employee amounts from the previous PERKESO table; employer amounts approximate the
    /// previous 1.75%-of-salary employer figure at each band's upper wage.</summary>
    public static readonly (decimal? UpTo, decimal Employee)[] SocsoEmployee =
    [
        (30m, 0.10m), (50m, 0.20m), (70m, 0.25m), (100m, 0.35m),
        (150m, 0.50m), (200m, 0.65m), (300m, 1.00m), (400m, 1.35m),
        (500m, 1.70m), (600m, 2.05m), (700m, 2.40m), (800m, 2.75m),
        (900m, 3.10m), (1000m, 3.45m), (1100m, 3.80m), (1200m, 4.15m),
        (1300m, 4.50m), (1400m, 4.85m), (1500m, 5.20m), (1600m, 5.55m),
        (1700m, 5.90m), (1800m, 6.25m), (1900m, 6.60m), (2000m, 6.95m),
        (2100m, 7.30m), (2200m, 7.65m), (2300m, 8.00m), (2400m, 8.35m),
        (2500m, 8.70m), (2600m, 9.05m), (2700m, 9.40m), (2800m, 9.75m),
        (2900m, 10.10m), (3000m, 10.45m), (3100m, 10.80m), (3200m, 11.15m),
        (3300m, 11.50m), (3400m, 11.85m), (3500m, 12.20m), (3600m, 12.55m),
        (3700m, 12.90m), (3800m, 13.25m), (3900m, 13.60m), (4000m, 13.95m),
        (4500m, 14.75m), (5000m, 16.60m), (null, 19.75m),
    ];

    public static List<SocsoBand> SocsoBands() => SocsoEmployee
        .Select(b => new SocsoBand
        {
            UpTo     = b.UpTo,
            Employee = b.Employee,
            Employer = Math.Round((b.UpTo ?? 5000m) * 0.0175m, 2, MidpointRounding.AwayFromZero),
        })
        .ToList();

    public static List<TaxBand> TaxBands() =>
    [
        new() { UpTo = 5000m,    Rate = 0m },
        new() { UpTo = 20000m,   Rate = 1m },
        new() { UpTo = 35000m,   Rate = 3m },
        new() { UpTo = 50000m,   Rate = 8m },
        new() { UpTo = 70000m,   Rate = 13m },
        new() { UpTo = 100000m,  Rate = 21m },
        new() { UpTo = 400000m,  Rate = 24m },
        new() { UpTo = 600000m,  Rate = 24.5m },
        new() { UpTo = 2000000m, Rate = 25m },
        new() { UpTo = null,     Rate = 26m },
    ];

    public static StatutoryRateSet Create(int id = 1)
    {
        var set = new StatutoryRateSet
        {
            Id                            = id,
            Name                          = "Initial rates",
            EffectiveFrom                 = EffectiveFrom,
            Notes                         = "Rates the system used before Statutory Rates could be edited. Review and add a new rate set for current official rates.",
            EpfEmployeeRate               = 2m,
            EpfEmployerRate               = 13m,
            EpfEmployerRateAboveThreshold = 13m,
            EpfEmployerThreshold          = 5000m,
            EisEmployeeRate               = 0m,
            EisEmployerRate               = 0m,
            EisWageCeiling                = 6000m,
            TaxPersonalRelief             = 9000m,
            CreatedAt                     = new DateTime(2026, 11, 18, 0, 0, 0, DateTimeKind.Utc),
        };
        set.SetSocsoBands(SocsoBands());
        set.SetTaxBands(TaxBands());
        return set;
    }
}
