using HrmsApi.Data;
using HrmsApi.Models;
using Microsoft.EntityFrameworkCore;

namespace HrmsApi.Services;

/// <summary>
/// The price list in force on a day (the latest that started on or before it), and how its
/// charges apply to a child's invoice:
///   • the monthly fee of the child's session;
///   • first invoice: every one-time charge (registration, uniform, bedding…) and twice-a-year charge (supplies);
///   • second invoice: the refundable deposit;
///   • in the twice-a-year months: the twice-a-year charges, unless the child joined in the last 3 months.
/// Charges for one session only (Bedding — Full day) apply to children of that session.
/// </summary>
public static class FeePrices
{
    /// <summary>A child who joined this recently isn't charged the twice-a-year items again.</summary>
    public const int TwiceAYearGraceMonths = 3;

    public static Task<FeePriceList?> ForDateAsync(HrmsDbContext db, DateTime day) =>
        db.FeePriceLists.AsNoTracking().Include(p => p.Sessions).Include(p => p.Charges)
            .Where(p => p.EffectiveFrom <= day.Date)
            .OrderByDescending(p => p.EffectiveFrom)
            .FirstOrDefaultAsync();

    /// <summary>"1,7" → [1, 7]</summary>
    public static int[] Months(string? s) =>
        (s ?? "").Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Select(x => int.TryParse(x, out var m) ? m : 0).Where(m => m is >= 1 and <= 12).Distinct().OrderBy(m => m).ToArray();

    /// <summary>The charge applies to a child of this session.</summary>
    public static bool AppliesTo(FeePriceCharge c, string? sessionType) =>
        string.IsNullOrEmpty(c.SessionType) || c.SessionType == sessionType;

    /// <summary>
    /// Charges (besides the monthly fee and add-ons) on a child's invoice for a month.
    /// <paramref name="earlierInvoices"/>: the child's invoices before this month (not void);
    /// <paramref name="firstInvoiceMonth"/>: year*12+month of the first of them.
    /// </summary>
    public static List<FeePriceCharge> ExtraCharges(FeePriceList list, string? sessionType, int year, int month,
        int earlierInvoices, int? firstInvoiceMonth)
    {
        var mine = list.Charges.Where(c => AppliesTo(c, sessionType)).OrderBy(c => c.SortOrder).ThenBy(c => c.Id).ToList();
        var result = new List<FeePriceCharge>();
        if (earlierInvoices == 0)
        {
            // Registration: one-time and twice-a-year charges
            result.AddRange(mine.Where(c => c.Kind is FeePriceCharge.OneTime or FeePriceCharge.TwiceAYear));
            return result;
        }
        if (earlierInvoices == 1) result.AddRange(mine.Where(c => c.Kind == FeePriceCharge.Deposit));

        var thisMonth = year * 12 + month;
        var joinedRecently = firstInvoiceMonth != null && thisMonth - firstInvoiceMonth.Value < TwiceAYearGraceMonths;
        if (Months(list.TwiceAYearMonths).Contains(month) && !joinedRecently)
            result.AddRange(mine.Where(c => c.Kind == FeePriceCharge.TwiceAYear));
        return result;
    }
}
