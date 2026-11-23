namespace HrmsApi.Models;

/// <summary>
/// A question and answer for the help chatbot (the "Assistant"), written by the company's admins.
/// The bot shows them as topics and matches what users type against the question and keywords.
/// </summary>
public class BotFaq
{
    /// <summary>Who sees the answer: everyone, parent logins only, or staff (employees and admins) only.</summary>
    public const string ForAll = "All", ForParents = "Parent", ForEmployees = "Employee";
    public static readonly string[] Audiences = { ForAll, ForParents, ForEmployees };

    public const int MaxQuestionLength = 300, MaxAnswerLength = 4000, MaxKeywordsLength = 500, MaxCategoryLength = 60;

    public int      Id        { get; set; }
    public string   Category  { get; set; } = "General";
    public string   Question  { get; set; } = string.Empty;
    public string   Answer    { get; set; } = string.Empty;
    /// <summary>Extra words people might type, comma separated ("mc, sick, unwell").</summary>
    public string?  Keywords  { get; set; }
    public string   Audience  { get; set; } = ForAll;
    /// <summary>Optional button under the answer that opens an app page (see <see cref="BotActions"/>).</summary>
    public string?  Action    { get; set; }
    public int      SortOrder { get; set; }
    public bool     IsActive  { get; set; } = true;
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;
}

/// <summary>A question the bot had no answer for, so admins can add one.</summary>
public class BotUnanswered
{
    public const int MaxTextLength = 500;

    public int      Id       { get; set; }
    public string   Text     { get; set; } = string.Empty;
    /// <summary>"Parent" or "Employee": who asked.</summary>
    public string   Audience { get; set; } = BotFaq.ForEmployees;
    public int      UserId   { get; set; }
    public DateTime AskedAt  { get; set; } = DateTime.UtcNow;
}

/// <summary>One AI answer: who asked, when, and the tokens it used (for the daily limit and cost).</summary>
public class BotAiUsage
{
    public int      Id           { get; set; }
    public int      UserId       { get; set; }
    public DateTime AskedAt      { get; set; } = DateTime.UtcNow;
    public string   Model        { get; set; } = string.Empty;
    public int      InputTokens  { get; set; }
    public int      OutputTokens { get; set; }
    public int      ToolCalls    { get; set; }
    /// <summary>False when the AI failed and the FAQ answer was used instead.</summary>
    public bool     Succeeded    { get; set; }
    /// <summary>Why the AI failed, for the admin ("Your Anthropic credit has run out…"); null if it worked.</summary>
    public string?  Error        { get; set; }
}

/// <summary>
/// App pages an answer can link to. The web and mobile apps map each key to their own screen;
/// the key list is shared so admins pick from the same choices.
/// </summary>
public static class BotActions
{
    /// <summary>Page audiences beyond <see cref="BotFaq"/>'s: admins only, and school staff (admins + class teachers).</summary>
    public const string ForAdmins = "Admin", ForStaff = "Staff";

    public record ActionInfo(string Key, string Label, string Audience, bool School);

    public static readonly ActionInfo[] All =
    {
        new("apply-leave",     "Apply for leave",       BotFaq.ForEmployees, false),
        new("my-leave",        "My leave",              BotFaq.ForEmployees, false),
        new("payslips",        "My payslips",           BotFaq.ForEmployees, false),
        new("attendance",      "My attendance",         BotFaq.ForEmployees, false),
        new("profile",         "My profile",            BotFaq.ForEmployees, false),
        new("fees",            "Fees",                  BotFaq.ForParents,   true),
        new("messages",        "Messages",              BotFaq.ForParents,   true),
        new("new-message",     "Message the school",    BotFaq.ForParents,   true),
        new("announcements",   "Announcements",         BotFaq.ForParents,   true),
        new("notifications",   "Notifications",         BotFaq.ForAll,       false),
        new("change-password", "Change password",       BotFaq.ForAll,       false),
        // Staff pages (offered by the AI assistant)
        new("school-attendance", "Attendance & reports", ForStaff,           true),
        new("school-messages",   "Parent messages",      ForStaff,           true),
        new("my-class",          "My class",             ForStaff,           true),
        new("school-fees",       "School fees",          ForAdmins,          true),
        new("school-children",   "Children",             ForAdmins,          true),
        new("approvals",         "Approvals",            ForAdmins,          false),
        new("payroll",           "Payroll",              ForAdmins,          false),
        new("employees",         "Employees",            ForAdmins,          false),
    };

    public static bool IsValid(string? key) => key == null || All.Any(a => a.Key == key);
}
