using HrmsApi.Data;
using HrmsApi.Hubs;
using HrmsApi.Models;

namespace HrmsApi.Services;

/// <summary>
/// The school's calendar: dates are Malaysian dates (UTC+8, no daylight saving), whatever time
/// zone the server runs in. "Today" at 7 am in Kuala Lumpur is still yesterday in UTC.
/// </summary>
public static class SchoolClock
{
    public static readonly TimeSpan Offset = TimeSpan.FromHours(8);

    public static DateTime Today => (DateTime.UtcNow + Offset).Date;

    /// <summary>"08:05" — a stored UTC time as the school's local time.</summary>
    public static string LocalTime(DateTime utc) => (DateTime.SpecifyKind(utc, DateTimeKind.Utc) + Offset).ToString("HH:mm");
}

/// <summary>
/// Tells logins about something that happened: a bell notification, a phone push (when push is
/// set up) and a live event for open pages. Never throws — the action itself has already succeeded.
/// </summary>
public static class SchoolAlerts
{
    public static async Task SendAsync(HrmsDbContext db, IPushService push, IChatNotifier live,
        IReadOnlyCollection<int> userIds, string title, string message, string type, string link,
        string liveEvent, object payload)
    {
        var ids = userIds.Distinct().ToList();
        if (ids.Count == 0) return;
        try
        {
            foreach (var uid in ids)
                db.Notifications.Add(new Notification
                {
                    UserId = uid, Title = Trim(title, 100), Message = Trim(message, 500),
                    Type = type, Link = link, CreatedAt = DateTime.UtcNow
                });
            await db.SaveChangesAsync();
            await push.SendToUsersAsync(db, ids, Trim(title, 100), Trim(message, 200), type, link);
        }
        catch
        {
            // Alerts are best effort
        }
        await live.SendAsync(ids, liveEvent, payload);
    }

    private static string Trim(string s, int max) => s.Length <= max ? s : s[..(max - 1)] + "…";
}
