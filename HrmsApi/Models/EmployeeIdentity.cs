using System.Text.RegularExpressions;

namespace HrmsApi.Models;

/// <summary>
/// Rules for an employee's identification and mobile number (same rules as the employee form):
///   NRIC     → exactly 12 digits (dashes/spaces are removed first), country is always Malaysia
///   Passport → 8–10 letters or digits (stored in capitals), issuing country required
///   Mobile   → country code like "+60" and 7–12 digits
/// </summary>
public static class EmployeeIdentity
{
    private static readonly Regex Nric       = new(@"^\d{12}$", RegexOptions.Compiled);
    private static readonly Regex Passport   = new(@"^[A-Z0-9]{8,10}$", RegexOptions.Compiled);
    private static readonly Regex DialCode   = new(@"^\+\d{1,4}$", RegexOptions.Compiled);
    private static readonly Regex MobileNo   = new(@"^\d{7,12}$", RegexOptions.Compiled);

    public record Result(string IdType, string IdNumber, string IdCountry, string PhoneCountryCode, string Phone);

    /// <summary>Normalised values, or the first problem as (field, message).</summary>
    public static (Result? value, string? field, string? error) Check(EmployeeRequest req)
    {
        var idType = string.Equals(req.IdType, IdTypes.Passport, StringComparison.OrdinalIgnoreCase)
            ? IdTypes.Passport
            : IdTypes.Nric;

        var raw = (req.IcPassport ?? "").Trim();
        string idNumber, country;
        if (idType == IdTypes.Nric)
        {
            idNumber = raw.Replace("-", "").Replace(" ", "");
            if (idNumber.Length == 0) return (null, "icPassport", "NRIC number is required.");
            if (!Nric.IsMatch(idNumber)) return (null, "icPassport", "NRIC must be exactly 12 digits (numbers only).");
            country = "Malaysia";
        }
        else
        {
            idNumber = raw.ToUpperInvariant();
            if (idNumber.Length == 0) return (null, "icPassport", "Passport number is required.");
            if (!Passport.IsMatch(idNumber)) return (null, "icPassport", "Passport number must be 8–10 letters or numbers.");
            country = (req.IdCountry ?? "").Trim();
            if (country.Length == 0) return (null, "idCountry", "Select the passport's country.");
            if (country.Length > 60) return (null, "idCountry", "Country name is too long.");
        }

        var code = string.IsNullOrWhiteSpace(req.PhoneCountryCode) ? "+60" : req.PhoneCountryCode.Trim();
        if (!DialCode.IsMatch(code)) return (null, "phoneCountryCode", "Select a valid country code.");
        var phone = Regex.Replace(req.Phone ?? "", @"[\s\-()]", "");
        if (phone.StartsWith(code)) phone = phone[code.Length..];        // "+60123456789" typed in full
        if (!MobileNo.IsMatch(phone)) return (null, "phone", "Mobile number must be 7–12 digits (numbers only).");

        return (new Result(idType, idNumber, country, code, phone), null, null);
    }

    /// <summary>Label for documents: "NRIC No." or "Passport No."</summary>
    public static string Label(string? idType) =>
        string.Equals(idType, IdTypes.Passport, StringComparison.OrdinalIgnoreCase) ? "Passport No." : "NRIC No.";
}
