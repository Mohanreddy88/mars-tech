using System.Text;
using HrmsApi.Models;

namespace HrmsApi.Services;

/// <summary>
/// Finds the admin-written answer (<see cref="BotFaq"/>) that best fits what someone typed.
/// Plain word matching, no AI: words are lower-cased, common words dropped and simple plural /
/// "-ing" endings removed; a keyword phrase counts most, then question words, category, answer.
/// Words of 4+ letters also match by prefix ("pay" ≠ "payslip", but "payslip" ~ "payslips").
/// </summary>
public static class BotMatcher
{
    /// <summary>The lowest score that counts as an answer.</summary>
    public const double MinScore = 2.0;

    private static readonly HashSet<string> StopWords = new(StringComparer.Ordinal)
    {
        "a","an","the","i","me","my","mine","we","our","you","your","he","she","it","its","they","them","their",
        "is","am","are","was","were","be","been","being","do","does","did","doing","have","has","had",
        "can","could","will","would","shall","should","may","might","must",
        "what","which","who","whom","whose","when","where","why","how",
        "to","of","in","on","at","for","from","by","with","about","into","onto","up","down","out","off","over",
        "and","or","but","if","then","so","than","too","very","just","also","not","no",
        "this","that","these","those","there","here","any","some","all","get","got","please","pls","plz",
        "want","need","know","tell","help","hi","hello","hey","thanks","thank","ok","okay","much","many",
        "saya","nak","macam","mana","apa","bila","ke","di","dan","yang","untuk","boleh","tak","ada"
    };

    private static readonly string[] Greetings = { "hi", "hello", "hey", "hai", "helo", "good morning", "good afternoon", "good evening", "salam", "assalamualaikum" };
    private static readonly string[] Thanks = { "thanks", "thank you", "thank u", "thx", "tq", "terima kasih", "ok thanks", "okay thanks" };

    /// <summary>"greeting", "thanks" or null — short replies that need no answer from the list.</summary>
    public static string? SmallTalk(string text)
    {
        var t = new string(text.ToLowerInvariant().Where(c => char.IsLetter(c) || c == ' ').ToArray()).Trim();
        while (t.Contains("  ")) t = t.Replace("  ", " ");
        if (t.Length == 0) return null;
        if (Thanks.Contains(t)) return "thanks";
        if (Greetings.Contains(t)) return "greeting";
        return null;
    }

    /// <summary>The meaningful words of a text, normalised.</summary>
    public static List<string> Words(string? text)
    {
        var result = new List<string>();
        if (string.IsNullOrWhiteSpace(text)) return result;
        var sb = new StringBuilder();
        void Flush()
        {
            if (sb.Length == 0) return;
            var w = sb.ToString();
            sb.Clear();
            if (w.Length < 2 || StopWords.Contains(w)) return;
            result.Add(Stem(w));
        }
        foreach (var ch in text.ToLowerInvariant())
        {
            if (char.IsLetterOrDigit(ch)) sb.Append(ch);
            else if (ch is '\'' or '’') continue;            // "don't" → "dont"
            else Flush();
        }
        Flush();
        return result;
    }

    private static string Stem(string w)
    {
        if (w.Length > 4 && w.EndsWith("ies")) return w[..^3] + "y";
        if (w.Length > 5 && w.EndsWith("ing")) return w[..^3];
        if (w.Length > 3 && w.EndsWith('s') && !w.EndsWith("ss") && !w.EndsWith("us")) return w[..^1];
        return w;
    }

    private static bool Same(string a, string b) =>
        a == b || (a.Length >= 4 && b.Length >= 4 && (a.StartsWith(b) || b.StartsWith(a)));

    /// <summary>How well the typed words fit this answer (0 = not at all).</summary>
    public static double Score(BotFaq faq, IReadOnlyCollection<string> query)
    {
        if (query.Count == 0) return 0;
        double score = 0;

        // Keyword phrases: all words of the phrase must appear
        foreach (var phrase in (faq.Keywords ?? "").Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
        {
            var pw = Words(phrase);
            if (pw.Count > 0 && pw.All(p => query.Any(q => Same(p, q)))) score += 3 * pw.Count;
        }

        var question = Words(faq.Question).Distinct().ToList();
        var category = Words(faq.Category);
        var answer = Words(faq.Answer).Distinct().ToList();
        foreach (var q in query.Distinct())
        {
            if (question.Any(w => w == q)) score += 2;
            else if (question.Any(w => Same(w, q))) score += 1.5;
            if (category.Any(w => Same(w, q))) score += 1;
            if (answer.Any(w => w == q)) score += 0.5;
        }

        // Prefer answers whose question is mostly covered by what was typed
        if (question.Count > 0)
        {
            var covered = question.Count(w => query.Any(q => Same(w, q)));
            score += 2.0 * covered / question.Count;
        }
        return score;
    }

    /// <summary>The answers that fit best, best first (only those scoring above zero).</summary>
    public static List<(BotFaq faq, double score)> Rank(IEnumerable<BotFaq> faqs, string text)
    {
        var query = Words(text);
        return faqs
            .Select(f => (faq: f, score: Score(f, query)))
            .Where(x => x.score > 0)
            .OrderByDescending(x => x.score)
            .ThenBy(x => x.faq.SortOrder)
            .ToList();
    }
}
