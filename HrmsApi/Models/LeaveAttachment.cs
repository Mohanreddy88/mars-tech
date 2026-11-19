namespace HrmsApi.Models;

/// <summary>
/// A supporting document for a leave request, e.g. the MC (medical certificate) letter for medical leave.
/// Stored in the company's own database (not the public uploads folder) because it holds health
/// information: only the employee who owns the request and Admins can read it. One per request;
/// uploading again replaces it.
/// </summary>
public class LeaveAttachment
{
    public const int MaxBytes = 5 * 1024 * 1024;

    public int      Id               { get; set; }
    public int      LeaveRequestId   { get; set; }
    public string   FileName         { get; set; } = string.Empty;
    public string   ContentType      { get; set; } = string.Empty;
    public int      SizeBytes        { get; set; }
    public byte[]   Data             { get; set; } = Array.Empty<byte>();
    public DateTime UploadedAt       { get; set; } = DateTime.UtcNow;
    public int?     UploadedByUserId { get; set; }

    public LeaveRequest LeaveRequest { get; set; } = null!;

    /// <summary>PDF, JPEG or PNG by file signature (the file name's extension is not trusted).</summary>
    public static string? DetectType(byte[] b)
    {
        if (b.Length >= 4 && b[0] == 0x25 && b[1] == 0x50 && b[2] == 0x44 && b[3] == 0x46) return "application/pdf";   // %PDF
        if (b.Length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) return "image/jpeg";
        if (b.Length >= 8 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) return "image/png";
        return null;
    }
}
