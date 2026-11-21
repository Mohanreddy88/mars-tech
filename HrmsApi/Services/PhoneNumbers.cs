namespace HrmsApi.Services;

/// <summary>
/// Phone numbers are stored in one standard form (E.164, e.g. +60123456789) so duplicates can be
/// found and numbers can later be used for SMS / WhatsApp. Numbers without a country code are
/// Malaysian (012-345 6789, 03-1234 5678); other countries are typed with their "+" code.
/// </summary>
public static class PhoneNumbers
{
    public const string Malaysia = "60";

    public const string MalaysianHint =
        "Enter a Malaysian number like 012-345 6789 (mobile) or 03-1234 5678, or a foreign number starting with +.";

    /// <summary>
    /// Cleans and checks a typed number. Empty → (null, null). Valid → (+E.164, null).
    /// Invalid → (null, message for the user).
    /// </summary>
    public static (string? Value, string? Error) Normalize(string? input)
    {
        if (string.IsNullOrWhiteSpace(input)) return (null, null);
        var text = input.Trim();
        if (text.Any(c => !char.IsDigit(c) && " -().+".IndexOf(c) < 0))
            return (null, "A phone number can only contain digits, spaces, dashes and a leading +.");

        var digits = new string(text.Where(char.IsDigit).ToArray());
        var international = text.StartsWith('+') || text.StartsWith("00");
        if (text.StartsWith("00")) digits = digits[2..];

        string national;
        if (international)
        {
            if (!digits.StartsWith(Malaysia))
            {
                // Another country: only the length can be checked (E.164 allows up to 15 digits)
                return digits.Length is >= 8 and <= 15
                    ? ("+" + digits, null)
                    : (null, "Enter the full number with its country code, e.g. +65 8123 4567.");
            }
            national = digits[Malaysia.Length..];
        }
        else
        {
            // 012-345 6789 (usual), 12-345 6789, or 60 12-345 6789 typed without the +
            national = digits.StartsWith('0') ? digits[1..] : digits;
            if (!IsMalaysian(national) && digits.StartsWith(Malaysia)) national = digits[Malaysia.Length..];
        }

        // People often write "+60 012-…": the trunk 0 is not part of the number
        if (national.StartsWith('0')) national = national[1..];
        return IsMalaysian(national) ? ("+" + Malaysia + national, null) : (null, MalaysianHint);
    }

    /// <summary>
    /// Malaysian number without the leading 0: mobiles 1x + 7 digits (011 / 015: 8 digits),
    /// Klang Valley landlines 3 + 8 digits, other states 4–9 + 7 digits (Sabah/Sarawak 8x + 6).
    /// </summary>
    private static bool IsMalaysian(string n)
    {
        if (n.Length == 0 || n.Any(c => !char.IsDigit(c))) return false;
        return n[0] switch
        {
            '1' => n.Length == (n.StartsWith("11") || n.StartsWith("15") ? 10 : 9),
            '3' => n.Length is 9,
            >= '4' and <= '9' => n.Length is 8,
            _ => false
        };
    }

    /// <summary>
    /// Employees keep the code and the number apart ("+60" and "123456789"). Checks them with the
    /// same rules and returns them in that form; the number may also be typed in full ("+60 12-345 6789").
    /// </summary>
    public static (string? Code, string? Number, string? Error) Split(string? countryCode, string? number)
    {
        var code = string.IsNullOrWhiteSpace(countryCode) ? "+" + Malaysia : countryCode.Trim();
        if (!code.StartsWith('+')) code = "+" + code;
        if (code.Length < 2 || code.Length > 5 || code[1..].Any(c => !char.IsDigit(c)))
            return (null, null, "Select a valid country code.");
        if (string.IsNullOrWhiteSpace(number)) return (null, null, "Mobile number is required.");

        var typed = number.Trim();
        var (full, error) = Normalize(typed.StartsWith('+') ? typed : code + " " + typed);
        if (error != null) return (null, null, error);
        // Typed in full with another country code: that code wins
        var actual = typed.StartsWith('+') && !full!.StartsWith(code) ? LongestCode(full) : code;
        return (actual, full![actual.Length..], null);
    }

    private static string LongestCode(string full)
    {
        // E.164 country codes are 1–3 digits and prefix-free; Malaysia is the usual one
        if (full.StartsWith("+" + Malaysia)) return "+" + Malaysia;
        foreach (var len in new[] { 3, 2, 1 })
            if (full.Length > len + 6 && KnownCodes.Contains(full[1..(len + 1)])) return full[..(len + 1)];
        return full[..3];
    }

    private static readonly HashSet<string> KnownCodes = new()
    {
        "1","7","20","27","30","31","32","33","34","36","39","40","41","43","44","45","46","47","48","49","51","52","53","54",
        "55","56","57","58","60","61","62","63","64","65","66","81","82","84","86","90","91","92","93","94","95","98",
        "211","212","213","216","218","220","221","222","223","224","225","226","227","228","229","230","231","232","233",
        "234","235","236","237","238","239","240","241","242","243","244","245","246","248","249","250","251","252","253",
        "254","255","256","257","258","260","261","262","263","264","265","266","267","268","269","290","291","297","298",
        "299","350","351","352","353","354","355","356","357","358","359","370","371","372","373","374","375","376","377",
        "378","380","381","382","383","385","386","387","389","420","421","423","500","501","502","503","504","505","506",
        "507","508","509","590","591","592","593","594","595","596","597","598","599","670","672","673","674","675","676",
        "677","678","679","680","681","682","683","685","686","687","688","689","690","691","692","850","852","853","855",
        "856","880","886","960","961","962","963","964","965","966","967","968","970","971","972","973","974","975","976",
        "977","992","993","994","995","996","998"
    };

    /// <summary>
    /// Comparison key for duplicate checks: the standard form, or (for old free-text values that
    /// don't pass the check) just their digits.
    /// </summary>
    public static string? Key(string? stored)
    {
        if (string.IsNullOrWhiteSpace(stored)) return null;
        var (value, _) = Normalize(stored);
        return value ?? new string(stored.Where(char.IsDigit).ToArray());
    }
}
