using HrmsApi.Data;
using HrmsApi.Models;
using Microsoft.EntityFrameworkCore;

namespace HrmsApi.Services;

public interface ILeaveService
{
    Task<LeaveRequest> CreateLeaveRequestAsync(LeaveRequestCreate request);
    Task<LeaveRequest> ApproveLeaveRequestAsync(int leaveRequestId, int approvedByUserId, string remarks);
    Task<LeaveRequest> RejectLeaveRequestAsync(int leaveRequestId, int rejectedByUserId, string remarks);
    Task<LeaveRequest> CancelLeaveRequestAsync(int leaveRequestId, string reason);
    Task<decimal> CalculateLeaveDaysAsync(DateTime startDate, DateTime endDate);
    Task InitializeLeaveBalancesAsync(int employeeId, int year);
    Task<List<EmployeeLeaveBalance>> GetEmployeeLeaveBalancesAsync(int employeeId, int year);

    /// <summary>
    /// Why leave can't be requested for these dates (a message), or null when it can: the days overlap
    /// a pending/approved leave request, or a leave day already deducted by an approved timesheet.
    /// </summary>
    Task<string?> FindLeaveConflictAsync(int employeeId, DateTime startDate, DateTime endDate, int? ignoreRequestId = null);

    /// <summary>
    /// When a timesheet is approved: every leave-coded day (AL, ML…) not already covered by a pending or
    /// approved leave request becomes an approved leave request, and the balance is deducted once through it.
    /// Saves changes. Returns the leave requests created.
    /// </summary>
    Task<List<LeaveRequest>> RecordTimesheetLeaveAsync(AttendancePeriod period, int approvedByUserId);
}

public class LeaveService : ILeaveService
{
    private readonly HrmsDbContext _db;
    private readonly ITimesheetService _timesheetService;
    private readonly ILogger<LeaveService> _logger;

    public LeaveService(
        HrmsDbContext db, 
        ITimesheetService timesheetService,
        ILogger<LeaveService> logger)
    {
        _db = db;
        _timesheetService = timesheetService;
        _logger = logger;
    }

    /// <summary>
    /// Create a new leave request
    /// Automatically calculates leave days excluding weekends and public holidays
    /// </summary>
    public async Task<LeaveRequest> CreateLeaveRequestAsync(LeaveRequestCreate request)
    {
        // Validate employee exists
        var employee = await _db.Employees.FindAsync(request.EmployeeId)
            ?? throw new KeyNotFoundException($"Employee {request.EmployeeId} not found");

        // Validate leave type exists
        var leaveType = await _db.LeaveTypes.FindAsync(request.LeaveTypeId)
            ?? throw new KeyNotFoundException($"Leave type {request.LeaveTypeId} not found");

        if (!leaveType.IsActive)
            throw new InvalidOperationException($"Leave type '{leaveType.Name}' is not active");

        // Normalize to UTC (Npgsql requires DateTimeKind.Utc for timestamp with time zone)
        var startDate = DateTime.SpecifyKind(request.StartDate.Date, DateTimeKind.Utc);
        var endDate   = DateTime.SpecifyKind(request.EndDate.Date,   DateTimeKind.Utc);

        // Validate dates
        if (startDate > endDate)
            throw new InvalidOperationException("Start date cannot be after end date");

        // Calculate leave days (excluding weekends and public holidays)
        var leaveDays = await CalculateLeaveDaysAsync(startDate, endDate);

        if (leaveDays <= 0)
            throw new InvalidOperationException("Leave request must be for at least 0.5 days");

        // One record per leave day: no overlap with leave already requested, approved, or recorded
        // from an approved timesheet. (A pending request for exactly these dates is updated below.)
        var samePendingId = await _db.LeaveRequests
            .Where(lr => lr.EmployeeId == request.EmployeeId && lr.StartDate == startDate && lr.EndDate == endDate
                      && (lr.Status == "Pending" || lr.Status == "Draft"))
            .Select(lr => (int?)lr.Id)
            .FirstOrDefaultAsync();
        var conflict = await FindLeaveConflictAsync(request.EmployeeId, startDate, endDate, samePendingId);
        if (conflict != null)
            throw new InvalidOperationException(conflict);

        // Check leave balance
        var year = startDate.Year;
        var balance = await _db.EmployeeLeaveBalances
            .FirstOrDefaultAsync(b => b.EmployeeId == request.EmployeeId 
                                   && b.LeaveTypeId == request.LeaveTypeId 
                                   && b.Year == year);

        if (balance == null)
        {
            // Initialize balance if not exists
            await InitializeLeaveBalancesAsync(request.EmployeeId, year);
            balance = await _db.EmployeeLeaveBalances
                .FirstOrDefaultAsync(b => b.EmployeeId == request.EmployeeId 
                                       && b.LeaveTypeId == request.LeaveTypeId 
                                       && b.Year == year);
        }

        if (balance != null && balance.BalanceDays < leaveDays)
        {
            throw new InvalidOperationException(
                $"Insufficient leave balance. Available: {balance.BalanceDays} days, Requested: {leaveDays} days");
        }

        // Check for existing leave request with same dates (only Pending or Draft status)
        var existingRequest = await _db.LeaveRequests
            .FirstOrDefaultAsync(lr => lr.EmployeeId == request.EmployeeId
                                    && lr.StartDate == startDate
                                    && lr.EndDate == endDate
                                    && (lr.Status == "Pending" || lr.Status == "Draft"));

        if (existingRequest != null)
        {
            // Update existing request instead of creating duplicate
            existingRequest.LeaveTypeId = request.LeaveTypeId;
            existingRequest.TotalDays = leaveDays;
            existingRequest.Reason = request.Reason;
            existingRequest.Status = "Pending";
            existingRequest.RequestedOn = DateTime.UtcNow;
            
            await _db.SaveChangesAsync();
            
            _logger.LogInformation("Leave request updated: Id {Id}, Employee {EmployeeId}, Type {LeaveType}, Days {Days}",
                existingRequest.Id, request.EmployeeId, leaveType.Name, leaveDays);
            
            return existingRequest;
        }

        // Create new leave request (use UTC-normalized dates)
        var leaveRequest = new LeaveRequest
        {
            EmployeeId = request.EmployeeId,
            LeaveTypeId = request.LeaveTypeId,
            StartDate = startDate,
            EndDate = endDate,
            TotalDays = leaveDays,
            Reason = request.Reason,
            Status = "Pending",
            RequestedOn = DateTime.UtcNow
        };

        _db.LeaveRequests.Add(leaveRequest);
        await _db.SaveChangesAsync();

        _logger.LogInformation("Leave request created: Employee {EmployeeId}, Type {LeaveType}, Days {Days}",
            request.EmployeeId, leaveType.Name, leaveDays);

        return leaveRequest;
    }

    /// <summary>
    /// Approve a leave request and deduct from employee leave balance
    /// </summary>
    public async Task<LeaveRequest> ApproveLeaveRequestAsync(int leaveRequestId, int approvedByUserId, string remarks)
    {
        var leaveRequest = await _db.LeaveRequests
            .Include(lr => lr.LeaveType)
            .Include(lr => lr.Employee)
            .FirstOrDefaultAsync(lr => lr.Id == leaveRequestId)
            ?? throw new KeyNotFoundException($"Leave request {leaveRequestId} not found");

        if (leaveRequest.Status != "Pending")
            throw new InvalidOperationException($"Leave request is already {leaveRequest.Status}");

        // Update leave request status
        leaveRequest.Status = "Approved";
        leaveRequest.ApprovedBy = approvedByUserId;
        leaveRequest.ApprovedOn = DateTime.UtcNow;
        leaveRequest.ApprovalRemarks = remarks;

        // Deduct from leave balance
        var year = leaveRequest.StartDate.Year;
        var balance = await _db.EmployeeLeaveBalances
            .FirstOrDefaultAsync(b => b.EmployeeId == leaveRequest.EmployeeId
                                   && b.LeaveTypeId == leaveRequest.LeaveTypeId
                                   && b.Year == year);

        if (balance != null)
        {
            balance.UsedDays += leaveRequest.TotalDays;
            balance.BalanceDays = balance.TotalDays + balance.CarryForwardDays - balance.UsedDays;
            balance.UpdatedAt = DateTime.UtcNow;
        }

        await _db.SaveChangesAsync();

        _logger.LogInformation("Leave request {Id} approved by User {UserId}", leaveRequestId, approvedByUserId);

        return leaveRequest;
    }

    /// <summary>
    /// Reject a leave request
    /// </summary>
    public async Task<LeaveRequest> RejectLeaveRequestAsync(int leaveRequestId, int rejectedByUserId, string remarks)
    {
        var leaveRequest = await _db.LeaveRequests.FindAsync(leaveRequestId)
            ?? throw new KeyNotFoundException($"Leave request {leaveRequestId} not found");

        if (leaveRequest.Status != "Pending")
            throw new InvalidOperationException($"Leave request is already {leaveRequest.Status}");

        leaveRequest.Status = "Rejected";
        leaveRequest.ApprovedBy = rejectedByUserId;
        leaveRequest.ApprovedOn = DateTime.UtcNow;
        leaveRequest.ApprovalRemarks = remarks;

        await _db.SaveChangesAsync();

        _logger.LogInformation("Leave request {Id} rejected by User {UserId}", leaveRequestId, rejectedByUserId);

        return leaveRequest;
    }

    /// <summary>
    /// Cancel a leave request (can only cancel approved/pending requests)
    /// </summary>
    public async Task<LeaveRequest> CancelLeaveRequestAsync(int leaveRequestId, string reason)
    {
        var leaveRequest = await _db.LeaveRequests.FindAsync(leaveRequestId)
            ?? throw new KeyNotFoundException($"Leave request {leaveRequestId} not found");

        if (leaveRequest.Status == "Cancelled" || leaveRequest.Status == "Rejected")
            throw new InvalidOperationException($"Cannot cancel a {leaveRequest.Status} leave request");

        var wasApproved = leaveRequest.Status == "Approved";

        // If approved, restore leave balance
        if (wasApproved)
        {
            var year = leaveRequest.StartDate.Year;
            var balance = await _db.EmployeeLeaveBalances
                .FirstOrDefaultAsync(b => b.EmployeeId == leaveRequest.EmployeeId
                                       && b.LeaveTypeId == leaveRequest.LeaveTypeId
                                       && b.Year == year);

            if (balance != null)
            {
                balance.UsedDays -= leaveRequest.TotalDays;
                balance.BalanceDays = balance.TotalDays + balance.CarryForwardDays - balance.UsedDays;
                balance.UpdatedAt = DateTime.UtcNow;
            }
        }

        leaveRequest.Status = "Cancelled";
        leaveRequest.CancelledOn = DateTime.UtcNow;
        leaveRequest.CancellationReason = reason;

        await _db.SaveChangesAsync();

        _logger.LogInformation("Leave request {Id} cancelled", leaveRequestId);

        return leaveRequest;
    }

    // ══════════════════════════════════════════════════════════════════════════
    // One record per leave day (leave requests ⇄ timesheet leave codes)
    // ══════════════════════════════════════════════════════════════════════════

    /// <summary>Start of the Reason on leave requests created from an approved timesheet.</summary>
    public const string TimesheetLeaveReason = "Recorded on timesheet";

    private static string Range(DateTime start, DateTime end) =>
        start.Date == end.Date ? $"{start:dd MMM yyyy}"
        : start.Year == end.Year ? $"{start:dd MMM} – {end:dd MMM yyyy}"
        : $"{start:dd MMM yyyy} – {end:dd MMM yyyy}";

    public async Task<string?> FindLeaveConflictAsync(int employeeId, DateTime startDate, DateTime endDate, int? ignoreRequestId = null)
    {
        var start = startDate.Date;
        var end   = endDate.Date;

        // 1. A pending or approved leave request on any of these days
        var overlap = await _db.LeaveRequests
            .Include(lr => lr.LeaveType)
            .Where(lr => lr.EmployeeId == employeeId
                      && (lr.Status == "Pending" || lr.Status == "Approved")
                      && lr.StartDate.Date <= end && lr.EndDate.Date >= start
                      && (ignoreRequestId == null || lr.Id != ignoreRequestId))
            .OrderBy(lr => lr.StartDate)
            .FirstOrDefaultAsync();
        if (overlap != null)
        {
            var fromTimesheet = overlap.Reason != null && overlap.Reason.StartsWith(TimesheetLeaveReason);
            var state = overlap.Status == "Approved"
                ? (fromTimesheet ? "already approved (recorded from the timesheet)" : "already approved")
                : "already waiting for approval";
            return $"{overlap.LeaveType.Name} for {Range(overlap.StartDate, overlap.EndDate)} is {state}. " +
                   "Leave can't be requested twice for the same day" +
                   (fromTimesheet || overlap.Status == "Approved" ? " — open it in My Requests to add a document." : ".");
        }

        // 2. A leave day deducted by a timesheet approved before timesheet leave was recorded as leave requests
        var timesheetDay = await _db.AttendancePeriodDays
            .Where(d => d.AttendancePeriod.EmployeeId == employeeId
                     && d.AttendancePeriod.Status == "Approved"
                     && d.Note != null && d.Note != ""
                     && d.Date.Date >= start && d.Date.Date <= end)
            .OrderBy(d => d.Date)
            .Select(d => new { d.Date, d.Note })
            .FirstOrDefaultAsync();
        if (timesheetDay != null)
        {
            return $"{timesheetDay.Note} leave on {timesheetDay.Date:dd MMM yyyy} was already recorded on an approved timesheet " +
                   "and deducted from the leave balance. Leave can't be requested twice for the same day.";
        }

        return null;
    }

    public async Task<List<LeaveRequest>> RecordTimesheetLeaveAsync(AttendancePeriod period, int approvedByUserId)
    {
        var created = new List<LeaveRequest>();

        var coded = await _db.AttendancePeriodDays
            .Where(d => d.AttendancePeriodId == period.Id && d.Note != null && d.Note != "")
            .OrderBy(d => d.Date)
            .ToListAsync();
        if (coded.Count == 0)
        {
            await _db.SaveChangesAsync();
            return created;
        }

        // Days already covered by a pending or approved leave request are left to that request
        // (approved: already deducted; pending: deducted if HR approves it) — never counted twice.
        var covering = await _db.LeaveRequests
            .Where(lr => lr.EmployeeId == period.EmployeeId
                      && (lr.Status == "Pending" || lr.Status == "Approved")
                      && lr.StartDate <= period.EndDate && lr.EndDate >= period.StartDate)
            .Select(lr => new { lr.StartDate, lr.EndDate })
            .ToListAsync();
        var uncovered = coded
            .Where(d => !covering.Any(r => d.Date.Date >= r.StartDate.Date && d.Date.Date <= r.EndDate.Date))
            .ToList();

        // Consecutive days with the same code become one leave request (a weekend in between doesn't break it)
        var runs = new List<List<AttendancePeriodDay>>();
        foreach (var day in uncovered)
        {
            var last = runs.LastOrDefault();
            var prev = last?.Last();
            var joins = prev != null && prev.Note == day.Note &&
                        Enumerable.Range(1, Math.Max(0, (day.Date.Date - prev.Date.Date).Days - 1))
                            .Select(i => prev.Date.Date.AddDays(i))
                            .All(x => x.DayOfWeek is DayOfWeek.Saturday or DayOfWeek.Sunday);
            if (joins) last!.Add(day); else runs.Add(new List<AttendancePeriodDay> { day });
        }

        var reason = $"{TimesheetLeaveReason} for {Range(period.StartDate, period.EndDate)} and approved with it.";
        foreach (var run in runs)
        {
            var code = run[0].Note!;
            var leaveType = await _db.LeaveTypes.FirstOrDefaultAsync(lt => lt.Code == code && lt.IsActive);
            if (leaveType == null)
            {
                _logger.LogWarning("Timesheet {PeriodId}: no active leave type with code {Code}; {Days} day(s) not recorded",
                    period.Id, code, run.Count);
                continue;
            }

            var start = DateTime.SpecifyKind(run[0].Date.Date, DateTimeKind.Utc);
            var end   = DateTime.SpecifyKind(run[^1].Date.Date, DateTimeKind.Utc);
            decimal days = run.Count;

            var leaveRequest = new LeaveRequest
            {
                EmployeeId      = period.EmployeeId,
                LeaveTypeId     = leaveType.Id,
                StartDate       = start,
                EndDate         = end,
                TotalDays       = days,
                Reason          = reason,
                Status          = "Approved",
                RequestedOn     = DateTime.UtcNow,
                ApprovedBy      = approvedByUserId,
                ApprovedOn      = DateTime.UtcNow,
                ApprovalRemarks = "Approved with the timesheet"
            };
            _db.LeaveRequests.Add(leaveRequest);
            created.Add(leaveRequest);

            // Deduct once, through this leave request
            var year = start.Year;
            var balance = await _db.EmployeeLeaveBalances
                .FirstOrDefaultAsync(b => b.EmployeeId == period.EmployeeId && b.LeaveTypeId == leaveType.Id && b.Year == year);
            if (balance == null)
            {
                await InitializeLeaveBalancesAsync(period.EmployeeId, year);
                balance = await _db.EmployeeLeaveBalances
                    .FirstOrDefaultAsync(b => b.EmployeeId == period.EmployeeId && b.LeaveTypeId == leaveType.Id && b.Year == year);
            }
            if (balance != null)
            {
                balance.UsedDays   += days;
                balance.BalanceDays = balance.TotalDays + balance.CarryForwardDays - balance.UsedDays;
                balance.UpdatedAt   = DateTime.UtcNow;
            }

            _logger.LogInformation("Timesheet {PeriodId}: recorded {Days} {Code} day(s) {Start:dd MMM}–{End:dd MMM yyyy} as approved leave",
                period.Id, days, code, start, end);
        }

        await _db.SaveChangesAsync();
        return created;
    }

    /// <summary>
    /// Calculate leave days excluding weekends and public holidays
    /// Malaysia: Monday-Friday = working days
    /// </summary>
    public async Task<decimal> CalculateLeaveDaysAsync(DateTime startDate, DateTime endDate)
    {
        // Normalize to UTC date-only (strip time, set Kind=Utc)
        startDate = DateTime.SpecifyKind(startDate.Date, DateTimeKind.Utc);
        endDate   = DateTime.SpecifyKind(endDate.Date,   DateTimeKind.Utc);

        if (startDate > endDate)
            return 0;

        int month = startDate.Month;
        int year = startDate.Year;

        // Get public holidays
        var publicHolidays = await _timesheetService.GetPublicHolidaysInMonthAsync(month, year);
        var publicHolidayDates = publicHolidays.Select(d => d.Date).ToHashSet();

        // If end date is in different month, get those holidays too
        if (endDate.Month != startDate.Month || endDate.Year != startDate.Year)
        {
            var endMonthHolidays = await _timesheetService.GetPublicHolidaysInMonthAsync(endDate.Month, endDate.Year);
            foreach (var h in endMonthHolidays)
                publicHolidayDates.Add(h.Date);
        }

        decimal days = 0;

        for (var date = startDate; date <= endDate; date = date.AddDays(1))
        {
            // Skip weekends
            if (date.DayOfWeek == DayOfWeek.Saturday || date.DayOfWeek == DayOfWeek.Sunday)
                continue;

            // Skip public holidays
            if (publicHolidayDates.Contains(date.Date))
                continue;

            days += 1;
        }

        return days;
    }

    /// <summary>
    /// Creates the leave balances an employee is missing for a year, with their entitlement
    /// (see <see cref="LeaveEntitlement"/>: Employment Act tiers by service, company minimum,
    /// pro-rated joining year, Maternity for women, Paternity for men).
    /// Existing balances are never changed or removed — admins adjust those on the Leave Balance page.
    /// </summary>
    public async Task InitializeLeaveBalancesAsync(int employeeId, int year)
    {
        var employee = await _db.Employees.FindAsync(employeeId)
            ?? throw new KeyNotFoundException($"Employee {employeeId} not found");

        var activeLeaveTypes = await _db.LeaveTypes.Where(lt => lt.IsActive).ToListAsync();
        var existingTypeIds = await _db.EmployeeLeaveBalances
            .Where(b => b.EmployeeId == employeeId && b.Year == year)
            .Select(b => b.LeaveTypeId)
            .ToListAsync();

        foreach (var leaveType in activeLeaveTypes)
        {
            if (existingTypeIds.Contains(leaveType.Id)) continue;          // admin's numbers stay as they are

            var days = LeaveEntitlement.DaysFor(leaveType, employee, year);
            if (days == null) continue;                                       // e.g. Maternity for a male employee

            _db.EmployeeLeaveBalances.Add(new EmployeeLeaveBalance
            {
                EmployeeId       = employeeId,
                LeaveTypeId      = leaveType.Id,
                Year             = year,
                TotalDays        = days.Value,
                UsedDays         = 0,
                BalanceDays      = days.Value,
                CarryForwardDays = 0
            });
        }

        await _db.SaveChangesAsync();
    }

    /// <summary>
    /// Get all leave balances for an employee for a specific year
    /// </summary>
    public async Task<List<EmployeeLeaveBalance>> GetEmployeeLeaveBalancesAsync(int employeeId, int year)
    {
        return await _db.EmployeeLeaveBalances
            .Include(b => b.LeaveType)
            .Where(b => b.EmployeeId == employeeId && b.Year == year)
            .ToListAsync();
    }
}
