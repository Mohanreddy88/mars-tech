namespace HrmsApi.Models;

/// <summary>
/// Core employee entity — maps to the Employees table.
/// </summary>
public class Employee
{
    public int      Id            { get; set; }
    public string   EmployeeCode  { get; set; } = string.Empty;
    public string   Name          { get; set; } = string.Empty;
    public string   Email         { get; set; } = string.Empty;
    public string   Phone         { get; set; } = string.Empty;
    
    /// <summary>Foreign key to Department — employee's department</summary>
    public int?     DepartmentId  { get; set; }
    
    public string   Designation   { get; set; } = string.Empty;
    public DateTime JoinDate      { get; set; }
    public decimal  Salary        { get; set; }
    public bool     IsActive      { get; set; } = true;
    public DateTime CreatedAt     { get; set; } = DateTime.UtcNow;
    
    /// <summary>Profile picture URL or path</summary>
    public string   ProfilePicture { get; set; } = string.Empty;

    /// <summary>Mobile country calling code, e.g. "+60". <see cref="Phone"/> holds the number without it.</summary>
    public string   PhoneCountryCode { get; set; } = "+60";

    // ── New fields (Bank & statutory identity) ──────────────
    /// <summary>"NRIC" (12 digits) or "Passport" (8–10 letters/digits) — see <see cref="IcPassport"/></summary>
    public string   IdType        { get; set; } = IdTypes.Nric;

    /// <summary>NRIC or passport number, depending on <see cref="IdType"/> (NRIC stored as 12 digits, no dashes)</summary>
    public string   IcPassport    { get; set; } = string.Empty;

    /// <summary>Country of the ID: always "Malaysia" for NRIC, the issuing country for a passport</summary>
    public string   IdCountry     { get; set; } = "Malaysia";

    /// <summary>Tax Identification Number for PCB/Income Tax purposes</summary>
    public string   TaxNumber     { get; set; } = string.Empty;

    /// <summary>Foreign key to BankMaster — employee's salary bank</summary>
    public int?     BankId        { get; set; }

    /// <summary>Bank account number for salary disbursement</summary>
    public string   AccountNumber { get; set; } = string.Empty;

    /// <summary>Date of birth (date only). Needed for age-based statutory rates (EPF, SOCSO).</summary>
    public DateTime? DateOfBirth  { get; set; }

    /// <summary>Gender: Male / Female / Other</summary>
    public string   Gender        { get; set; } = string.Empty;

    // ── Navigation properties ────────────────────────────────
    public Department?              Department  { get; set; }
    public BankMaster?              Bank        { get; set; }
    public ICollection<Attendance>  Attendances { get; set; } = new List<Attendance>();
    public ICollection<Payroll>     Payrolls    { get; set; } = new List<Payroll>();
}

/// <summary>Employee identification types.</summary>
public static class IdTypes
{
    public const string Nric     = "NRIC";
    public const string Passport = "Passport";
}
