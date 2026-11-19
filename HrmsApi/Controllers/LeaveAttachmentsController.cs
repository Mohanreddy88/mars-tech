using System.Security.Claims;
using HrmsApi.Data;
using HrmsApi.Models;
using HrmsApi.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Net.Http.Headers;

namespace HrmsApi.Controllers;

/// <summary>
/// Supporting documents for leave requests, e.g. the MC letter for medical leave.
/// The employee who owns the request uploads it; the employee and Admins can view it.
/// </summary>
[ApiController]
[Route("api/leave-attachments")]
[Authorize]
public class LeaveAttachmentsController : ControllerBase
{
    private readonly HrmsDbContext _db;
    private readonly IAuditService _audit;
    private readonly INotificationService _notif;

    public LeaveAttachmentsController(HrmsDbContext db, IAuditService audit, INotificationService notif)
    {
        _db    = db;
        _audit = audit;
        _notif = notif;
    }

    private bool IsAdmin => User.IsInRole("Admin");
    private int? CurrentUserId => int.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out var id) ? id : null;

    /// <summary>The employee record of the signed-in user (a login belongs to the employee with the same email).</summary>
    private async Task<int?> CurrentEmployeeIdAsync()
    {
        var userId = CurrentUserId;
        if (userId == null) return null;
        var email = await _db.Users.Where(u => u.Id == userId).Select(u => u.Email).FirstOrDefaultAsync();
        if (string.IsNullOrWhiteSpace(email)) return null;
        return await _db.Employees
            .Where(e => e.Email.ToLower() == email.ToLower())
            .Select(e => (int?)e.Id)
            .FirstOrDefaultAsync();
    }

    private async Task<bool> OwnsAsync(LeaveRequest lr) => lr.EmployeeId == await CurrentEmployeeIdAsync();

    /// <summary>POST /api/leave-attachments/{leaveRequestId} — upload (or replace) the document. PDF, JPG or PNG, max 5 MB.</summary>
    [HttpPost("{leaveRequestId:int}")]
    [RequestSizeLimit(LeaveAttachment.MaxBytes + 256 * 1024)]
    public async Task<IActionResult> Upload(int leaveRequestId, IFormFile? file)
    {
        var lr = await _db.LeaveRequests.Include(r => r.Employee).Include(r => r.LeaveType)
            .FirstOrDefaultAsync(r => r.Id == leaveRequestId);
        if (lr == null) return NotFound(new { message = "Leave request not found." });

        var owner = await OwnsAsync(lr);
        if (!owner && !IsAdmin) return Forbid();
        if (lr.Status is "Cancelled" or "Rejected")
            return BadRequest(new { message = $"This leave request is {lr.Status.ToLower()}, so a document can't be added." });

        if (file == null || file.Length == 0) return BadRequest(new { message = "Choose a file to upload." });
        if (file.Length > LeaveAttachment.MaxBytes) return BadRequest(new { message = "The file must be 5 MB or smaller." });

        byte[] bytes;
        using (var ms = new MemoryStream())
        {
            await file.CopyToAsync(ms);
            bytes = ms.ToArray();
        }
        var type = LeaveAttachment.DetectType(bytes);
        if (type == null) return BadRequest(new { message = "Upload a PDF, JPG or PNG file." });

        var name = Path.GetFileName(file.FileName ?? "document");
        if (string.IsNullOrWhiteSpace(name)) name = "document";
        if (name.Length > 200) name = name[^200..];

        var existing = await _db.LeaveAttachments.FirstOrDefaultAsync(a => a.LeaveRequestId == leaveRequestId);
        var att = existing ?? new LeaveAttachment { LeaveRequestId = leaveRequestId };
        att.FileName         = name;
        att.ContentType      = type;
        att.SizeBytes        = bytes.Length;
        att.Data             = bytes;
        att.UploadedAt       = DateTime.UtcNow;
        att.UploadedByUserId = CurrentUserId;
        if (existing == null) _db.LeaveAttachments.Add(att);
        await _db.SaveChangesAsync();

        var what = lr.LeaveType.Code == LeaveEntitlement.Medical ? "MC letter" : "supporting document";
        await _audit.LogAsync(existing == null ? "Uploaded" : "Replaced", "LeaveAttachment", leaveRequestId.ToString(),
            $"{(existing == null ? "Uploaded" : "Replaced")} {what} for {lr.Employee.Name}'s {lr.LeaveType.Name} ({lr.StartDate:dd MMM}–{lr.EndDate:dd MMM yyyy})",
            User.Identity?.Name ?? "unknown", CurrentUserId, ipAddress: HttpContext.Connection.RemoteIpAddress?.ToString());

        if (owner && !IsAdmin)
        {
            await _notif.NotifyAdminsAsync(
                title:   what == "MC letter" ? "MC Letter Uploaded" : "Leave Document Uploaded",
                message: $"{lr.Employee.Name} uploaded a {what} for {lr.LeaveType.Name} ({lr.StartDate:dd MMM} – {lr.EndDate:dd MMM yyyy}).",
                type:    "leave_document",
                link:    $"/leave/requests?employeeId={lr.EmployeeId}");
        }

        return Ok(new { att.FileName, att.ContentType, att.SizeBytes, att.UploadedAt });
    }

    /// <summary>GET /api/leave-attachments/{leaveRequestId} — the document itself (owner or Admin).</summary>
    [HttpGet("{leaveRequestId:int}")]
    public async Task<IActionResult> Download(int leaveRequestId)
    {
        var lr = await _db.LeaveRequests.FirstOrDefaultAsync(r => r.Id == leaveRequestId);
        if (lr == null) return NotFound(new { message = "Leave request not found." });
        if (!IsAdmin && !await OwnsAsync(lr)) return Forbid();

        var att = await _db.LeaveAttachments.AsNoTracking().FirstOrDefaultAsync(a => a.LeaveRequestId == leaveRequestId);
        if (att == null) return NotFound(new { message = "No document has been uploaded for this leave." });

        // Shown in the browser, never cached by shared caches
        Response.Headers[HeaderNames.CacheControl] = "private, no-store";
        Response.Headers["X-Content-Type-Options"] = "nosniff";
        var cd = new ContentDispositionHeaderValue("inline");
        cd.SetHttpFileName(att.FileName);
        Response.Headers[HeaderNames.ContentDisposition] = cd.ToString();
        return File(att.Data, att.ContentType);
    }

    /// <summary>DELETE /api/leave-attachments/{leaveRequestId} — remove it (owner while pending, or Admin).</summary>
    [HttpDelete("{leaveRequestId:int}")]
    public async Task<IActionResult> Delete(int leaveRequestId)
    {
        var lr = await _db.LeaveRequests.Include(r => r.Employee)
            .FirstOrDefaultAsync(r => r.Id == leaveRequestId);
        if (lr == null) return NotFound(new { message = "Leave request not found." });

        var owner = await OwnsAsync(lr);
        if (!IsAdmin && !(owner && lr.Status == "Pending"))
            return BadRequest(new { message = "The document can only be removed while the request is pending." });

        var att = await _db.LeaveAttachments.FirstOrDefaultAsync(a => a.LeaveRequestId == leaveRequestId);
        if (att == null) return NotFound(new { message = "No document to remove." });

        _db.LeaveAttachments.Remove(att);
        await _db.SaveChangesAsync();
        await _audit.LogAsync("Deleted", "LeaveAttachment", leaveRequestId.ToString(),
            $"Removed the document from {lr.Employee.Name}'s leave request #{leaveRequestId}",
            User.Identity?.Name ?? "unknown", CurrentUserId, ipAddress: HttpContext.Connection.RemoteIpAddress?.ToString());
        return Ok(new { message = "Document removed." });
    }
}
