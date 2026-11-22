using System.Net;
using System.Text.RegularExpressions;
using HrmsApi.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;

namespace HrmsApi.Controllers;

/// <summary>
/// Endpoints for the public Mars HRMS website (marshrms.com), no login needed.
/// </summary>
[ApiController]
[Route("api/public")]
[AllowAnonymous]
public class PublicController : ControllerBase
{
    private readonly IEmailQueue? _email;
    private readonly IConfiguration _config;
    private readonly ILogger<PublicController> _logger;

    public PublicController(IConfiguration config, ILogger<PublicController> logger, IEmailQueue? email = null)
    {
        _config = config; _logger = logger; _email = email;
    }

    private static readonly Regex EmailPattern = new(@"^[^@\s]+@[^@\s]+\.[^@\s]+$", RegexOptions.Compiled);

    /// <summary>
    /// POST /api/public/contact — "Book a demo" / "Contact us" form. Emailed to the support address
    /// (config Contact:Email, default support@marshrms.com). Spam: a hidden "website" field must stay
    /// empty, and each IP may send a few per hour.
    /// </summary>
    [HttpPost("contact")]
    [EnableRateLimiting("public-contact")]
    public IActionResult Contact([FromBody] ContactRequest req)
    {
        // Bots fill every field; people never see this one. Pretend it worked.
        if (!string.IsNullOrWhiteSpace(req.Website)) return Ok(new { sent = true });

        string Clean(string? s, int max) => (s ?? "").Trim() is var t && t.Length > max ? t[..max] : (s ?? "").Trim();
        var name = Clean(req.Name, 100);
        var organisation = Clean(req.Organisation, 150);
        var kind = Clean(req.Kind, 30);
        var phone = Clean(req.Phone, 30);
        var email = Clean(req.Email, 150);
        var size = Clean(req.Size, 30);
        var message = Clean(req.Message, 3000);

        if (name.Length < 2) return BadRequest(new { message = "Please enter your name." });
        if (email.Length == 0 && phone.Length == 0) return BadRequest(new { message = "Please enter your email or phone number." });
        if (email.Length > 0 && !EmailPattern.IsMatch(email)) return BadRequest(new { message = "Please check the email address." });
        if (_email == null) return StatusCode(503, new { message = "Sending isn't available right now. Please email or WhatsApp us instead." });

        var to = _config["Contact:Email"] ?? "support@marshrms.com";
        static string H(string s) => WebUtility.HtmlEncode(s);
        string Row(string label, string value) => value.Length == 0 ? "" :
            $"<tr><td style=\"padding:6px 12px 6px 0;color:#6b7280;vertical-align:top\">{label}</td><td style=\"padding:6px 0\">{H(value)}</td></tr>";

        var body = $"""
            <div style="font-family:Segoe UI,Arial,sans-serif;font-size:14px;color:#111827">
              <h2 style="color:#0b2c5f;margin:0 0 12px">New enquiry from the Mars HRMS website</h2>
              <table style="border-collapse:collapse">
                {Row("Name", name)}{Row("School / company", organisation)}{Row("Type", kind)}{Row("Size", size)}
                {Row("Email", email)}{Row("Phone", phone)}
              </table>
              <p style="white-space:pre-wrap;margin-top:16px;padding:12px;background:#f3f4f6;border-radius:8px">{H(message.Length == 0 ? "(no message)" : message)}</p>
              <p style="color:#9ca3af;font-size:12px">Sent {DateTime.UtcNow:yyyy-MM-dd HH:mm} UTC from marshrms.com</p>
            </div>
            """;

        _email.Enqueue(new EmailJob
        {
            ToEmail = to,
            Subject = $"Website enquiry: {name}{(organisation.Length > 0 ? " – " + organisation : "")}",
            Body = body
        });
        _logger.LogInformation("Website enquiry queued ({Kind})", kind.Length == 0 ? "unspecified" : kind);
        return Ok(new { sent = true });
    }
}

public class ContactRequest
{
    public string? Name { get; set; }
    public string? Organisation { get; set; }
    /// <summary>"School", "Company" or "Other".</summary>
    public string? Kind { get; set; }
    public string? Size { get; set; }
    public string? Phone { get; set; }
    public string? Email { get; set; }
    public string? Message { get; set; }
    /// <summary>Honeypot: hidden on the form, must stay empty.</summary>
    public string? Website { get; set; }
}
