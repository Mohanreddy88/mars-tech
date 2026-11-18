using FluentAssertions;
using HrmsApi.Data;
using HrmsApi.Models;
using HrmsApi.Services;
using Microsoft.EntityFrameworkCore;

namespace HrmsApi.Tests;

/// <summary>
/// Statutory rates (EPF, SOCSO, EIS, PCB) come from editable, dated rate sets.
/// </summary>
public class StatutoryRatesTests
{
    private static HrmsDbContext NewDb() => new(new DbContextOptionsBuilder<HrmsDbContext>()
        .UseInMemoryDatabase(Guid.NewGuid().ToString()).Options);

    private static async Task<Employee> AddEmployeeWithApprovedMonth(HrmsDbContext db, int id, decimal salary, int month, int year)
    {
        var emp = new Employee { Id = id, Name = $"Emp {id}", EmployeeCode = $"E{id:000}", Salary = salary, Email = $"e{id}@test.com" };
        db.Employees.Add(emp);
        db.AttendancePeriods.Add(new AttendancePeriod
        {
            EmployeeId = id,
            StartDate  = new DateTime(year, month, 1),
            EndDate    = new DateTime(year, month, DateTime.DaysInMonth(year, month)),
            Status     = "Approved",
            Days       = new List<AttendancePeriodDay>(),
        });
        await db.SaveChangesAsync();
        return emp;
    }

    private static StatutoryRateSet RatesFrom(DateTime from, decimal epfEmployee, decimal eisRate = 0m)
    {
        var set = StatutoryRateDefaults.Create(0);
        set.Name = $"Rates {from:yyyy-MM}";
        set.EffectiveFrom = from;
        set.EpfEmployeeRate = epfEmployee;
        set.EisEmployeeRate = eisRate;
        set.EisEmployerRate = eisRate;
        return set;
    }

    // ── Old hard-coded PCB formula, kept here to prove the new band table gives identical tax ──
    private static decimal OldAnnualTax(decimal chargeable)
    {
        (decimal From, decimal To, decimal Rate, decimal Prev)[] b =
        [
            (0m, 5000m, 0m, 0m), (5001m, 20000m, 0.01m, 0m), (20001m, 35000m, 0.03m, 150m),
            (35001m, 50000m, 0.08m, 600m), (50001m, 70000m, 0.13m, 1800m), (70001m, 100000m, 0.21m, 4400m),
            (100001m, 400000m, 0.24m, 10700m), (400001m, 600000m, 0.245m, 82700m),
            (600001m, 2000000m, 0.25m, 131700m), (2000001m, decimal.MaxValue, 0.26m, 481700m),
        ];
        if (chargeable <= 0) return 0m;
        decimal tax = 0m;
        foreach (var (from, to, rate, prev) in b)
        {
            if (chargeable <= from - 1) break;
            tax = prev + (Math.Min(chargeable, to) - (from - 1)) * rate;
            if (chargeable <= to) break;
        }
        return tax;
    }

    [Theory]
    [InlineData(0)] [InlineData(4999.99)] [InlineData(5000)] [InlineData(5000.5)] [InlineData(12345.67)]
    [InlineData(35000)] [InlineData(49800)] [InlineData(88000)] [InlineData(250000)] [InlineData(3000000)]
    public void TaxBands_GiveSameTaxAsPreviousHardCodedBrackets(decimal chargeable)
    {
        StatutoryCalculator.AnnualTax(StatutoryRateDefaults.TaxBands(), chargeable)
            .Should().Be(OldAnnualTax(chargeable));
    }

    [Theory]
    [InlineData(0, 0)]
    [InlineData(30, 0.10)]
    [InlineData(31, 0.20)]
    [InlineData(5000, 16.60)]
    [InlineData(5000.01, 19.75)]
    [InlineData(12000, 19.75)]
    public void Socso_UsesTableBand_AndOpenEndedBandAboveTheTable(decimal wage, decimal expected)
    {
        StatutoryCalculator.Socso(StatutoryRateDefaults.SocsoBands(), wage).Employee.Should().Be(expected);
    }

    [Fact]
    public void Eis_IsCappedAtTheWageCeiling()
    {
        var rates = RatesFrom(new DateTime(2000, 1, 1), 2m, eisRate: 0.2m);
        rates.EisWageCeiling = 6000m;

        StatutoryCalculator.Calculate(rates, 4000m).EisEmployee.Should().Be(8m);    // 4000 × 0.2%
        StatutoryCalculator.Calculate(rates, 9000m).EisEmployee.Should().Be(12m);   // capped at 6000 × 0.2%
    }

    [Fact]
    public void EpfEmployerRate_SwitchesAboveThreshold()
    {
        var rates = RatesFrom(new DateTime(2000, 1, 1), 11m);
        rates.EpfEmployerRate = 13m;
        rates.EpfEmployerRateAboveThreshold = 12m;
        rates.EpfEmployerThreshold = 5000m;

        StatutoryCalculator.Calculate(rates, 5000m).EpfEmployer.Should().Be(650m);  // 13%
        StatutoryCalculator.Calculate(rates, 6000m).EpfEmployer.Should().Be(720m);  // 12%
    }

    [Fact]
    public async Task Payroll_UsesTheRateSetInForceForTheMonth()
    {
        using var db = NewDb();
        db.StatutoryRateSets.Add(StatutoryRateDefaults.Create(0));                    // from 2000: EPF 2%
        db.StatutoryRateSets.Add(RatesFrom(new DateTime(2026, 6, 1), 11m));           // from June 2026: EPF 11%
        await db.SaveChangesAsync();
        await AddEmployeeWithApprovedMonth(db, 1, 5000m, 5, 2026);
        var service = new PayrollCalculationService(db);

        var may  = await service.CalculatePayrollAsync(1, 5, 2026);
        var june = await service.CalculatePayrollAsync(1, 6, 2026);

        may.EpfAmount.Should().Be(100m);
        may.StatutoryRateSetName.Should().Be("Initial rates");
        june.EpfAmount.Should().Be(550m);
        june.StatutoryRateSetName.Should().Be("Rates 2026-06");
    }

    [Fact]
    public async Task EmployeeOverride_ReplacesCompanyEpfRate()
    {
        using var db = NewDb();
        var emp = await AddEmployeeWithApprovedMonth(db, 2, 4000m, 5, 2026);
        emp.EpfEmployeeRateOverride = 11m;
        await db.SaveChangesAsync();

        var result = await new PayrollCalculationService(db).CalculatePayrollAsync(2, 5, 2026);

        result.EpfEmployeeRate.Should().Be(11m);
        result.EpfAmount.Should().Be(440m);
    }

    [Fact]
    public async Task GeneratedPayroll_KeepsItsRates_WhenTheRateSetIsChangedLater()
    {
        using var db = NewDb();
        await AddEmployeeWithApprovedMonth(db, 3, 5000m, 5, 2026);
        var service = new PayrollCalculationService(db);

        var payroll = await service.GeneratePayrollAsync(3, 5, 2026, createdById: 1);
        payroll.EpfAmount.Should().Be(100m);
        payroll.EpfEmployeeRate.Should().Be(2m);
        payroll.StatutoryRateSetId.Should().NotBeNull();

        // HR later changes the rate set
        var set = await db.StatutoryRateSets.SingleAsync();
        set.EpfEmployeeRate = 11m;
        await db.SaveChangesAsync();

        var stored = await db.Payrolls.SingleAsync(p => p.Id == payroll.Id);
        stored.EpfAmount.Should().Be(100m);
        stored.EpfEmployeeRate.Should().Be(2m);
    }

    [Fact]
    public async Task EisDeduction_ReducesNetSalary()
    {
        using var db = NewDb();
        db.StatutoryRateSets.Add(RatesFrom(new DateTime(2000, 1, 1), 2m, eisRate: 0.2m));
        await db.SaveChangesAsync();
        await AddEmployeeWithApprovedMonth(db, 4, 5000m, 5, 2026);

        var r = await new PayrollCalculationService(db).CalculatePayrollAsync(4, 5, 2026);

        r.EisAmount.Should().Be(10m);
        r.NetSalary.Should().Be(r.GrossIncome - r.EpfAmount - r.SocsoAmount - r.EisAmount - r.TaxAmount);
    }

    [Fact]
    public async Task MonthBeforeAnyRateSet_IsNotEligible()
    {
        using var db = NewDb();
        db.StatutoryRateSets.Add(RatesFrom(new DateTime(2027, 1, 1), 2m));
        await db.SaveChangesAsync();
        await AddEmployeeWithApprovedMonth(db, 5, 5000m, 5, 2026);

        var eligibility = await new PayrollCalculationService(db).CheckEligibilityAsync(5, 5, 2026);

        eligibility.IsEligible.Should().BeFalse();
        eligibility.Errors.Should().Contain(e => e.Contains("Statutory Rates"));
    }

    [Fact]
    public void Validate_RejectsBadTables()
    {
        var ok = new StatutoryRateSetRequest
        {
            Name = "2027", EffectiveFrom = new DateTime(2027, 1, 1),
            EpfEmployeeRate = 11, EpfEmployerRate = 13, EpfEmployerRateAboveThreshold = 12, EpfEmployerThreshold = 5000,
            SocsoBands = StatutoryRateDefaults.SocsoBands(), TaxBands = StatutoryRateDefaults.TaxBands(),
            EisWageCeiling = 6000, TaxPersonalRelief = 9000,
        };
        StatutoryCalculator.Validate(ok).Should().BeEmpty();

        ok.TaxBands = [new() { UpTo = 5000, Rate = 0 }, new() { UpTo = 4000, Rate = 1 }];
        StatutoryCalculator.Validate(ok).Should().Contain(e => e.Contains("open-ended"))
            .And.Contain(e => e.Contains("increase"));

        ok.TaxBands = StatutoryRateDefaults.TaxBands();
        ok.EpfEmployeeRate = 120;
        StatutoryCalculator.Validate(ok).Should().Contain(e => e.Contains("EPF employee rate"));
    }
}
