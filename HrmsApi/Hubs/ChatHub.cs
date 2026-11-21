using System.Security.Claims;
using HrmsApi.Platform;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.SignalR;

namespace HrmsApi.Hubs;

/// <summary>
/// Live updates for school messages and announcements (/api/hubs/chat).
/// Browsers only listen here; they send through the REST endpoints, which check access.
/// Each connection joins its own login's group. Group names include the company, because
/// user ids repeat across companies (one database each).
/// </summary>
[Authorize]
public class ChatHub : Hub
{
    public override async Task OnConnectedAsync()
    {
        // Hub calls run outside the HTTP request, so the company comes from the token's "tenant"
        // claim (checked against the web address when the connection was authenticated).
        // Single-company setups have no claim: the empty scope, like ITenantContext.TokenScope.
        var scope = Context.User?.FindFirstValue(HrmsApi.Services.TokenService.TenantClaim) ?? "";
        if (int.TryParse(Context.User?.FindFirstValue(ClaimTypes.NameIdentifier), out var userId))
            await Groups.AddToGroupAsync(Context.ConnectionId, UserGroup(scope, userId));
        await base.OnConnectedAsync();
    }

    public static string UserGroup(string tenantScope, int userId) => $"{tenantScope}:u:{userId}";
}

/// <summary>Sends live events to logins of the current company.</summary>
public interface IChatNotifier
{
    Task SendAsync(IEnumerable<int> userIds, string eventName, object payload);
}

public class ChatNotifier : IChatNotifier
{
    private readonly IHubContext<ChatHub> _hub;
    private readonly ITenantContext _tenant;
    private readonly ILogger<ChatNotifier> _logger;

    public ChatNotifier(IHubContext<ChatHub> hub, ITenantContext tenant, ILogger<ChatNotifier> logger)
    {
        _hub = hub; _tenant = tenant; _logger = logger;
    }

    public async Task SendAsync(IEnumerable<int> userIds, string eventName, object payload)
    {
        var groups = userIds.Distinct().Select(id => ChatHub.UserGroup(_tenant.TokenScope, id)).ToList();
        if (groups.Count == 0) return;
        try
        {
            await _hub.Clients.Groups(groups).SendAsync(eventName, payload);
        }
        catch (Exception ex)
        {
            // Live delivery is a convenience: the message is saved and shows on the next refresh.
            _logger.LogWarning(ex, "Live update {Event} failed", eventName);
        }
    }
}
