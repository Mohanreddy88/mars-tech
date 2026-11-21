using FirebaseAdmin;
using FirebaseAdmin.Messaging;
using Google.Apis.Auth.OAuth2;
using HrmsApi.Data;
using Microsoft.EntityFrameworkCore;

namespace HrmsApi.Services;

/// <summary>
/// Push notifications to the mobile app through Firebase Cloud Messaging.
///
/// Off until the server has Firebase service-account credentials:
///   FIREBASE_CREDENTIALS_JSON  — the service-account JSON itself, or
///   FIREBASE_CREDENTIALS_FILE  — path to that JSON file.
/// One Firebase project serves every company; the device tokens live in each company's database.
/// </summary>
public interface IPushService
{
    bool Enabled { get; }

    /// <summary>Send to every registered device of these users (current company). Never throws.</summary>
    /// <param name="link">The page it is about (web path, e.g. "/parent/fees"); the app opens the matching screen.</param>
    Task SendToUsersAsync(HrmsDbContext db, IReadOnlyCollection<int> userIds, string title, string body, string type, string? link = null);
}

public class PushService : IPushService
{
    private readonly ILogger<PushService> _logger;
    private readonly FirebaseMessaging? _messaging;

    public PushService(IConfiguration config, ILogger<PushService> logger)
    {
        _logger = logger;
        try
        {
            var json = config["FIREBASE_CREDENTIALS_JSON"];
            var file = config["FIREBASE_CREDENTIALS_FILE"];
            GoogleCredential? credential =
                !string.IsNullOrWhiteSpace(json) ? GoogleCredential.FromJson(json) :
                !string.IsNullOrWhiteSpace(file) && File.Exists(file) ? GoogleCredential.FromFile(file) :
                null;
            if (credential == null)
            {
                _logger.LogInformation("Push notifications are off (no Firebase credentials configured).");
                return;
            }
            var app = FirebaseApp.DefaultInstance ?? FirebaseApp.Create(new AppOptions { Credential = credential });
            _messaging = FirebaseMessaging.GetMessaging(app);
            _logger.LogInformation("Push notifications are on (Firebase project {Project}).", app.Options.ProjectId);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Firebase credentials could not be loaded; push notifications are off.");
        }
    }

    public bool Enabled => _messaging != null;

    public async Task SendToUsersAsync(HrmsDbContext db, IReadOnlyCollection<int> userIds, string title, string body, string type, string? link = null)
    {
        if (_messaging == null || userIds.Count == 0) return;
        try
        {
            var devices = await db.DeviceTokens
                .Where(d => userIds.Contains(d.UserId))
                .Select(d => new { d.Id, d.Token })
                .ToListAsync();
            if (devices.Count == 0) return;

            // FCM accepts up to 500 tokens per call.
            foreach (var batch in devices.Chunk(500))
            {
                var message = new MulticastMessage
                {
                    Tokens       = batch.Select(d => d.Token).ToList(),
                    Notification = new FirebaseAdmin.Messaging.Notification { Title = title, Body = body },
                    // The app reads "type" to open the right screen (leave_*, attendance_*, payroll_*).
                    Data         = link == null
                        ? new Dictionary<string, string> { ["type"] = type }
                        : new Dictionary<string, string> { ["type"] = type, ["link"] = link },
                    Android      = new AndroidConfig { Priority = Priority.High },
                };
                var result = await _messaging.SendEachForMulticastAsync(message);

                // Phones that uninstalled the app (or reset their token) are removed.
                var stale = result.Responses
                    .Select((r, i) => (r, batch[i].Id))
                    .Where(x => !x.r.IsSuccess &&
                                x.r.Exception?.MessagingErrorCode is MessagingErrorCode.Unregistered
                                    or MessagingErrorCode.InvalidArgument or MessagingErrorCode.SenderIdMismatch)
                    .Select(x => x.Id)
                    .ToList();
                if (stale.Count > 0)
                    await db.DeviceTokens.Where(d => stale.Contains(d.Id)).ExecuteDeleteAsync();
                if (result.FailureCount > stale.Count)
                    _logger.LogWarning("Push: {Failed} of {Total} messages failed", result.FailureCount - stale.Count, batch.Length);
            }
        }
        catch (Exception ex)
        {
            // A failed push must never break the action that caused it.
            _logger.LogError(ex, "Push notification failed: {Title}", title);
        }
    }
}
