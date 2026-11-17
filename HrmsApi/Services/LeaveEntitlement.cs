using HrmsApi.Models;

namespace HrmsApi.Services;

/// <summary>
/// Yearly leave entitlement under the Malaysian Employment Act 1955 (as amended 2022):
///
///   Annual (s60E)        under 2 years' service  8 days · 2–5 years 12 · 5+ years 16
///                        first (joining) year pro-rated by completed months of service
///   Sick / Medical (s60F) under 2 years 14 days · 2–5 years 18 · 5+ years 22
///   Hospitalisation       60 days
///   Maternity (s37)      98 days — female employees only
///   Paternity (s60FA)     7 days — male employees only
///
/// Years of service are counted as completed years on 1 January of the leave year.
/// A company may give more: the leave type's "default days" is used when it is higher than the law.
/// Other leave types use their configured default days.
/// </summary>
public static class LeaveEntitlement
{
    public const string Annual          = "AL";
    public const string Medical         = "ML";
    public const string Hospitalisation = "HPL";
    public const string Maternity       = "MTL";
    public const string Paternity       = "PTL";

    /// <summary>Days for this employee in this year, or null when the leave type doesn't apply to them.</summary>
    public static decimal? DaysFor(LeaveType type, Employee emp, int year)
    {
        if (emp.JoinDate.Year > year) return null;          // not employed yet that year

        var gender  = (emp.Gender ?? "").Trim().ToLowerInvariant();
        var years   = CompletedYears(emp.JoinDate, new DateTime(year, 1, 1));
        var company = (decimal)type.DefaultDaysPerYear;

        switch (type.Code)
        {
            case Annual:
                var annual = Math.Max(years < 2 ? 8 : years < 5 ? 12 : 16, company);
                return emp.JoinDate.Year == year ? ProRate(annual, emp.JoinDate) : annual;
            case Medical:
                return Math.Max(years < 2 ? 14 : years < 5 ? 18 : 22, company);
            case Hospitalisation:
                return Math.Max(60, company);
            case Maternity:
                return gender == "female" ? Math.Max(98, company) : null;
            case Paternity:
                return gender == "male" ? Math.Max(7, company) : null;
            default:
                return company;
        }
    }

    /// <summary>Whole years from join date to the given date.</summary>
    public static int CompletedYears(DateTime joinDate, DateTime at)
    {
        var years = at.Year - joinDate.Year;
        if (at.Month < joinDate.Month || (at.Month == joinDate.Month && at.Day < joinDate.Day)) years--;
        return Math.Max(0, years);
    }

    /// <summary>
    /// Joining year: days × completed months ÷ 12, half a day or more rounds up (Employment Act s60E(1A)).
    /// Joining on the 1st counts that month; joining later in the month starts from the next month.
    /// </summary>
    public static decimal ProRate(decimal fullYearDays, DateTime joinDate)
    {
        var months = 12 - joinDate.Month + (joinDate.Day == 1 ? 1 : 0);
        return Math.Round(fullYearDays * months / 12m, MidpointRounding.AwayFromZero);
    }
}
