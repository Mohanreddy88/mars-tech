namespace HrmsApi.Models;

public class Payroll
{
    public int Id { get; set; }
    public int EmployeeId { get; set; }
    public int Month { get; set; }
    public int Year { get; set; }
    public decimal BasicSalary { get; set; }
    public decimal Allowances { get; set; }
    public decimal Deductions { get; set; }

    // Statutory deductions (auto-calculated from the StatutoryRateSet in force for the month)
    public decimal EpfAmount { get; set; }    // EPF employee share
    public decimal SocsoAmount { get; set; }  // SOCSO employee share (PERKESO table)
    public decimal EisAmount { get; set; }    // EIS employee share
    public decimal TaxAmount { get; set; }    // PCB / MTD

    // Employer contributions (cost to the company, not deducted from pay)
    public decimal EpfEmployerAmount { get; set; }
    public decimal SocsoEmployerAmount { get; set; }
    public decimal EisEmployerAmount { get; set; }

    // Snapshot of the rates used, so later rate changes never alter this payroll.
    // Null on payrolls generated before statutory rates were configurable.
    public int?     StatutoryRateSetId   { get; set; }
    public string?  StatutoryRateSetName { get; set; }
    public decimal? EpfEmployeeRate      { get; set; }   // percent, e.g. 2
    public decimal? EpfEmployerRate      { get; set; }   // percent, e.g. 13

    public decimal GrossIncome { get; set; }
    public decimal NetSalary { get; set; }
    public DateTime GeneratedOn { get; set; } = DateTime.UtcNow;

    // Enhanced tracking fields
    public string Status { get; set; } = "Draft"; // Draft, Under Review, Pending Approval, Approved, Processed, Rejected
    public decimal? AttendanceHours { get; set; }
    public decimal? ExpectedHours { get; set; }
    public int? PaidLeaveDays { get; set; }
    public int? UnpaidLeaveDays { get; set; }
    public int? ApprovedBy { get; set; }
    public DateTime? ApprovedOn { get; set; }
    public int? ProcessedBy { get; set; }
    public DateTime? ProcessedOn { get; set; }
    public string? Remarks { get; set; }

    // Proration fields (populated when employee joins mid-month)
    public bool    IsProrated     { get; set; } = false;
    public int?    ProratedDays   { get; set; }        // actual paid days in the month
    public int?    TotalMonthDays { get; set; }        // total calendar days in the month
    public decimal? ProratedSalary { get; set; }       // basic salary after proration

    // Navigation properties
    public Employee Employee { get; set; } = null!;
    public User? Approver { get; set; }
    public User? Processor { get; set; }
    public ICollection<PayrollAttendancePeriod> AttendancePeriods { get; set; } = new List<PayrollAttendancePeriod>();
    public ICollection<PayrollLeaveRequest> LeaveRequests { get; set; } = new List<PayrollLeaveRequest>();
    public ICollection<PayrollAdjustment> Adjustments { get; set; } = new List<PayrollAdjustment>();
}
