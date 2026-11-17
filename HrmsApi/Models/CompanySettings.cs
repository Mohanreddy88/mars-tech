using System.ComponentModel.DataAnnotations;

namespace HrmsApi.Models;

/// <summary>
/// The employer's own details: one row (Id = 1) per database, so each client's
/// database carries its own name, logo and statutory numbers. Used on payslips,
/// EA forms, emails and the UI.
/// </summary>
public class CompanySettings
{
    public const int SingletonId = 1;

    public int Id { get; set; } = SingletonId;

    /// <summary>Registered name, e.g. "ABC TECHNOLOGIES SDN. BHD." (payslips, EA form)</summary>
    [MaxLength(200)] public string LegalName { get; set; } = "";

    /// <summary>Short name for the UI and email signatures, e.g. "ABC Technologies"</summary>
    [MaxLength(100)] public string DisplayName { get; set; } = "";

    /// <summary>SSM company registration number, e.g. "201901012345 (1234567-A)"</summary>
    [MaxLength(50)] public string? RegistrationNo { get; set; }

    /// <summary>LHDN employer tax number ("E" number), e.g. "E 1234567890" (EA form)</summary>
    [MaxLength(50)] public string? EmployerTaxNo { get; set; }

    /// <summary>LHDN branch the employer files with, e.g. "SELANGOR" (EA form)</summary>
    [MaxLength(100)] public string? TaxBranch { get; set; }

    [MaxLength(500)] public string? Address { get; set; }
    [MaxLength(50)]  public string? Phone { get; set; }
    [MaxLength(150)] public string? Website { get; set; }

    /// <summary>Officer named on the EA form (Part F)</summary>
    [MaxLength(100)] public string? HrOfficerName { get; set; }
    [MaxLength(100)] public string? HrOfficerPosition { get; set; }

    /// <summary>Hex colour for the company name on payslips and the UI accent, e.g. "#C62828"</summary>
    [MaxLength(7)] public string BrandColor { get; set; } = "#C62828";

    public byte[]? LogoData { get; set; }
    [MaxLength(50)] public string? LogoContentType { get; set; }

    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;

    /// <summary>True once an admin has entered at least the legal name.</summary>
    public bool IsConfigured => !string.IsNullOrWhiteSpace(LegalName);

    /// <summary>Name to print: the legal name, or a visible reminder that it's missing.</summary>
    public string NameForDocuments => IsConfigured ? LegalName : "COMPANY NAME NOT SET";

    /// <summary>Name for the UI and email signatures.</summary>
    public string NameForDisplay =>
        !string.IsNullOrWhiteSpace(DisplayName) ? DisplayName : IsConfigured ? LegalName : "HR & Payroll";
}
