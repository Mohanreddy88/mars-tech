using HrmsApi.Data;
using HrmsApi.Models;
using HrmsApi.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using System.Security.Claims;
using System.Text.Json;
using BCrypt.Net;
using HrmsApi.Platform;
using System.Security.Cryptography;

namespace HrmsApi.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize]
public class EmployeesController : ControllerBase
{
    private readonly HrmsDbContext _db;
    private readonly IAuditService _audit;
    private readonly ILogger<EmployeesController> _logger;
    private readonly IEmailQueue _emailQueue;
    private readonly ICompanySettingsService _company;
    private readonly ITenantContext _tenant;
    private readonly IAccountService _accounts;

    public EmployeesController(HrmsDbContext db, IAuditService audit, ILogger<EmployeesController> logger,
        IEmailQueue emailQueue, ICompanySettingsService company, ITenantContext tenant, IAccountService accounts)
    {
        _db     = db;
        _audit  = audit;
        _logger = logger;
        _emailQueue = emailQueue;
        _company    = company;
        _tenant     = tenant;
        _accounts   = accounts;
    }

    private string CurrentUser() => User.FindFirst(ClaimTypes.Name)?.Value ?? "system";
    private int?   CurrentUserId() { var v = User.FindFirst(ClaimTypes.NameIdentifier)?.Value; return int.TryParse(v, out var id) ? id : null; }

    /// <summary>Optional per-employee EPF rates must be valid percentages.</summary>
    private static string? EpfOverrideError(EmployeeRequest req)
    {
        static bool Bad(decimal? v) => v is < 0 or > 100;
        if (Bad(req.EpfEmployeeRateOverride)) return "EPF employee rate must be between 0 and 100%.";
        if (Bad(req.EpfEmployerRateOverride)) return "EPF employer rate must be between 0 and 100%.";
        return null;
    }

    /// <summary>
    /// GET /api/employees
    /// Returns all employees with their department name and bank name for display in list/dropdown.
    /// </summary>
    [HttpGet]
    [Authorize(Roles = "Admin")]
    public async Task<IActionResult> GetAll()
    {
        var employees = await _db.Employees
            .Include(e => e.Department)
            .Include(e => e.Bank)
            .OrderBy(e => e.Name)
            .Select(e => new
            {
                e.Id, e.EmployeeCode, e.Name, e.Email, e.Phone,
                e.DepartmentId,
                DepartmentName = e.Department != null ? e.Department.Name : null,
                e.Designation,
                e.JoinDate, e.Salary, e.IsActive,
                e.BankId, e.AccountNumber,
                BankName = e.Bank != null ? e.Bank.Name : null,
                e.Gender,
                e.PhoneCountryCode, e.IdType, e.IcPassport, e.IdCountry, e.TaxNumber, e.ProfilePicture, e.DateOfBirth,
                e.EpfEmployeeRateOverride, e.EpfEmployerRateOverride
            })
            .ToListAsync();

        // Remove duplicates in memory
        var uniqueEmployees = employees
            .GroupBy(e => e.Id)
            .Select(g => g.First())
            .ToList();

        return Ok(uniqueEmployees);
    }

    /// <summary>
    /// GET /api/employees/active
    /// Returns only active employees (IsActive = true) for dropdowns and filters.
    /// </summary>
    [HttpGet("active")]
    [Authorize(Roles = "Admin")]
    public async Task<IActionResult> GetActive()
    {
        var employees = await _db.Employees
            .Where(e => e.IsActive)
            .Include(e => e.Department)
            .Include(e => e.Bank)
            .OrderBy(e => e.Name)
            .Select(e => new
            {
                e.Id, e.EmployeeCode, e.Name, e.Email, e.Phone,
                e.DepartmentId,
                DepartmentName = e.Department != null ? e.Department.Name : null,
                e.Designation,
                e.JoinDate, e.Salary, e.IsActive,
                e.BankId, e.AccountNumber,
                BankName = e.Bank != null ? e.Bank.Name : null,
                e.Gender,
                e.PhoneCountryCode, e.IdType, e.IcPassport, e.IdCountry, e.TaxNumber, e.ProfilePicture, e.DateOfBirth,
                e.EpfEmployeeRateOverride, e.EpfEmployerRateOverride
            })
            .ToListAsync();

        // Remove duplicates in memory
        var uniqueEmployees = employees
            .GroupBy(e => e.Id)
            .Select(g => g.First())
            .ToList();

        return Ok(uniqueEmployees);
    }

    /// <summary>
    /// GET /api/employees/{id}
    /// Returns a single employee record including department and bank details.
    /// </summary>
    [HttpGet("{id:int}")]
    public async Task<IActionResult> GetById(int id)
    {
        // Admins: any employee. Others: only their own record (the web navbar loads it for the photo).
        if (!User.IsInRole("Admin") && await _db.CurrentEmployeeIdAsync(User) != id)
            return Forbid();

        var emp = await _db.Employees
            .Include(e => e.Department)
            .Include(e => e.Bank)
            .Where(e => e.Id == id)
            .Select(e => new
            {
                e.Id, e.EmployeeCode, e.Name, e.Email, e.Phone,
                e.DepartmentId,
                DepartmentName = e.Department != null ? e.Department.Name : null,
                e.Designation,
                e.JoinDate, e.Salary, e.IsActive,
                e.BankId, e.AccountNumber,
                BankName = e.Bank != null ? e.Bank.Name : null,
                e.Gender,
                e.PhoneCountryCode, e.IdType, e.IcPassport, e.IdCountry, e.TaxNumber, e.ProfilePicture, e.DateOfBirth,
                e.EpfEmployeeRateOverride, e.EpfEmployerRateOverride
            })
            .FirstOrDefaultAsync()
            ?? throw new KeyNotFoundException($"Employee {id} not found.");

        return Ok(emp);
    }

    /// <summary>
    /// POST /api/employees
    /// Creates a new employee record.
    /// </summary>
    [HttpPost]
    [Authorize(Roles = "Admin")]
    public async Task<IActionResult> Create([FromBody] EmployeeRequest req)
    {
        var (id, idField, idError) = EmployeeIdentity.Check(req);
        if (id == null) return BadRequest(new { message = idError, field = idField });
        if (EpfOverrideError(req) is { } epfErr) return BadRequest(new { message = epfErr, field = "epf" });

        // One email = one employee (the login is linked by email)
        var email = (req.Email ?? "").Trim();
        if (await _db.Employees.AnyAsync(e => e.Email.ToLower() == email.ToLower()))
            return BadRequest(new { message = $"Another employee already uses {email}.", field = "email" });

        // Validate department exists if provided
        if (req.DepartmentId.HasValue)
        {
            var deptExists = await _db.Departments.AnyAsync(d => d.Id == req.DepartmentId.Value);
            if (!deptExists)
                throw new KeyNotFoundException($"Department with ID {req.DepartmentId} not found.");
        }

        // Validate bank exists if provided
        if (req.BankId.HasValue)
        {
            var bankExists = await _db.BankMasters.AnyAsync(b => b.Id == req.BankId.Value);
            if (!bankExists)
                throw new KeyNotFoundException($"Bank with ID {req.BankId} not found.");
        }

        // Auto-generate employee code - find the highest sequence number from all employee codes
        var allEmployeeCodes = await _db.Employees
            .Where(e => e.EmployeeCode.StartsWith("EMP"))
            .Select(e => e.EmployeeCode)
            .ToListAsync();
        
        int nextSequence = 1;
        if (allEmployeeCodes.Any())
        {
            var sequenceNumbers = allEmployeeCodes
                .Select(code => 
                {
                    if (code.Length > 3 && int.TryParse(code.Substring(3), out int num))
                        return num;
                    return 0;
                })
                .Where(num => num > 0)
                .ToList();
            
            if (sequenceNumbers.Any())
            {
                nextSequence = sequenceNumbers.Max() + 1;
            }
        }
        
        var employeeCode = $"EMP{nextSequence:D6}";

        // Convert JoinDate to UTC - PostgreSQL requires UTC timestamps
        var joinDateUtc = req.JoinDate.Kind == DateTimeKind.Unspecified
            ? DateTime.SpecifyKind(req.JoinDate, DateTimeKind.Utc)
            : req.JoinDate.ToUniversalTime();

        var emp = new Employee
        {
            EmployeeCode   = employeeCode,
            Name           = req.Name,
            Email          = req.Email,
            Phone          = id.Phone,
            PhoneCountryCode = id.PhoneCountryCode,
            IdType         = id.IdType,
            IcPassport     = id.IdNumber,
            IdCountry      = id.IdCountry,
            DateOfBirth    = id.DateOfBirth,
            TaxNumber      = req.TaxNumber?.Trim() ?? string.Empty,
            ProfilePicture = req.ProfilePicture ?? string.Empty,
            DepartmentId   = req.DepartmentId,
            Designation    = req.Designation,
            JoinDate       = joinDateUtc,
            Salary         = req.Salary,
            IsActive       = req.IsActive,
            BankId         = req.BankId,
            AccountNumber  = req.AccountNumber,
            Gender         = req.Gender ?? string.Empty,
            EpfEmployeeRateOverride = req.EpfEmployeeRateOverride,
            EpfEmployerRateOverride = req.EpfEmployerRateOverride
        };

        _db.Employees.Add(emp);
        
        try
        {
            await _db.SaveChangesAsync();
        }
        catch (DbUpdateException ex)
        {
            var innerException = ex.InnerException?.Message ?? ex.Message;
            return StatusCode(500, new
            {
                error = "Database update failed",
                message = ex.Message,
                innerException,
                employeeCode,
                stackTrace = ex.StackTrace
            });
        }

        // Auto-create a login for the employee and email them a "Set my password" link.
        // Username = part of email before '@'  (e.g. "john.doe@company.com" → "john.doe")
        var userCreated = false;
        var userAlreadyExists = false;
        var welcomeEmailSent = false;
        var generatedUsername = _accounts.UsernameFor(emp.Email);

        var existingUser = await _db.Users
            .FirstOrDefaultAsync(u => u.Email.ToLower() == emp.Email.ToLower()
                               || u.Username.ToLower() == generatedUsername);

        if (existingUser == null)
        {
            try
            {
                var newUser = _accounts.NewUser(emp.Email, generatedUsername, "Employee");
                _db.Users.Add(newUser);
                await _db.SaveChangesAsync();
                userCreated = true;
                welcomeEmailSent = await _accounts.SendWelcomeAsync(newUser, emp.Name);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Failed to auto-create user for employee {Email}", emp.Email);
            }
        }
        else
        {
            userAlreadyExists = true;
        }

        await _audit.LogAsync(
            action:      "Created",
            entityType:  "Employee",
            entityId:    emp.Id.ToString(),
            description: $"Created employee {emp.Name} ({employeeCode})" + (userCreated ? $" and auto-created user account ({generatedUsername})" : ""),
            username:    CurrentUser(),
            userId:      CurrentUserId(),
            newValues:   JsonSerializer.Serialize(new { emp.Name, emp.Email, emp.Designation, emp.Salary, emp.IsActive }),
            ipAddress:   HttpContext.Connection.RemoteIpAddress?.ToString());

        return CreatedAtAction(nameof(GetById), new { id = emp.Id }, new {
            message      = "Employee created successfully",
            employeeCode,
            id           = emp.Id,
            userCreated,
            userAlreadyExists,
            username     = userCreated ? generatedUsername : null,
            welcomeEmailSent,
            email        = emp.Email
        });
    }

    /// <summary>
    /// POST /api/employees/{id}/send-welcome
    /// Emails the employee a new "Set my password" link (creates their login if it is missing).
    /// Use when the first link expired or the email was lost. Their current password keeps working
    /// until they use the link.
    /// </summary>
    [HttpPost("{id:int}/send-welcome")]
    [Authorize(Roles = "Admin")]
    public async Task<IActionResult> SendWelcome(int id)
    {
        var emp = await _db.Employees.FindAsync(id)
            ?? throw new KeyNotFoundException($"Employee {id} not found.");
        if (string.IsNullOrWhiteSpace(emp.Email) || !emp.Email.Contains('@'))
            return BadRequest(new { message = "This employee has no valid email address." });

        var user = await _db.Users.FirstOrDefaultAsync(u => u.Email.ToLower() == emp.Email.ToLower());
        var created = false;
        if (user == null)
        {
            var username = _accounts.UsernameFor(emp.Email);
            if (await _db.Users.AnyAsync(u => u.Username.ToLower() == username))
                return BadRequest(new { message = $"The username \"{username}\" is already used by another login. Change it under Master → Users." });
            user = _accounts.NewUser(emp.Email, username, "Employee");
            _db.Users.Add(user);
            await _db.SaveChangesAsync();
            created = true;
        }
        if (!user.IsActive)
            return BadRequest(new { message = "This login is deactivated. Activate it under Master → Users first." });

        var sent = await _accounts.SendWelcomeAsync(user, emp.Name);
        if (!sent) return StatusCode(500, new { message = "The email could not be queued. Please try again." });

        await _audit.LogAsync(
            action:      "Updated",
            entityType:  "Employee",
            entityId:    emp.Id.ToString(),
            description: $"Sent login email to {emp.Name} ({user.Email})" + (created ? $" and created user account ({user.Username})" : ""),
            username:    CurrentUser(),
            userId:      CurrentUserId(),
            ipAddress:   HttpContext.Connection.RemoteIpAddress?.ToString());

        return Ok(new { message = $"Login email sent to {user.Email}.", username = user.Username, email = user.Email, userCreated = created });
    }

    /// <summary>
    /// PUT /api/employees/{id}
    /// Updates an existing employee record.
    /// </summary>
    [HttpPut("{id:int}")]
    [Authorize(Roles = "Admin")]
    public async Task<IActionResult> Update(int id, [FromBody] EmployeeRequest req)
    {
        var (ident, idField, idError) = EmployeeIdentity.Check(req);
        if (ident == null) return BadRequest(new { message = idError, field = idField });
        if (EpfOverrideError(req) is { } epfErr) return BadRequest(new { message = epfErr, field = "epf" });

        var emp = await _db.Employees.FindAsync(id)
            ?? throw new KeyNotFoundException($"Employee {id} not found.");

        // Validate department if changed
        if (req.DepartmentId.HasValue)
        {
            var deptExists = await _db.Departments.AnyAsync(d => d.Id == req.DepartmentId.Value);
            if (!deptExists)
                throw new KeyNotFoundException($"Department with ID {req.DepartmentId} not found.");
        }

        // Validate bank if changed
        if (req.BankId.HasValue)
        {
            var bankExists = await _db.BankMasters.AnyAsync(b => b.Id == req.BankId.Value);
            if (!bankExists)
                throw new KeyNotFoundException($"Bank with ID {req.BankId} not found.");
        }

        // Convert JoinDate to UTC - PostgreSQL requires UTC timestamps
        var joinDateUtc = req.JoinDate.Kind == DateTimeKind.Unspecified
            ? DateTime.SpecifyKind(req.JoinDate, DateTimeKind.Utc)
            : req.JoinDate.ToUniversalTime();

        var oldSnap = JsonSerializer.Serialize(new { emp.Name, emp.Email, emp.Designation, emp.Salary, emp.IsActive });

        // The login is linked by email: a new email must not belong to another employee or login
        var oldEmail = emp.Email;
        var newEmail = (req.Email ?? "").Trim();
        if (!string.Equals(oldEmail, newEmail, StringComparison.OrdinalIgnoreCase))
        {
            if (await _db.Employees.AnyAsync(e => e.Id != id && e.Email.ToLower() == newEmail.ToLower()))
                return BadRequest(new { message = $"Another employee already uses {newEmail}.", field = "email" });
            if (await _db.Users.AnyAsync(u => u.Email.ToLower() == newEmail.ToLower()))
                return BadRequest(new { message = $"{newEmail} is already used by another login (Master → Users).", field = "email" });
        }

        emp.Name           = req.Name;
        emp.Email          = newEmail;
        emp.Phone          = ident.Phone;
        emp.PhoneCountryCode = ident.PhoneCountryCode;
        emp.IdType         = ident.IdType;
        emp.IcPassport     = ident.IdNumber;
        emp.IdCountry      = ident.IdCountry;
        emp.DateOfBirth    = ident.DateOfBirth;
        emp.TaxNumber      = req.TaxNumber?.Trim() ?? string.Empty;
        emp.ProfilePicture = req.ProfilePicture ?? string.Empty;
        emp.DepartmentId   = req.DepartmentId;
        emp.Designation    = req.Designation;
        emp.JoinDate       = joinDateUtc;
        emp.Salary         = req.Salary;
        emp.IsActive       = req.IsActive;
        emp.BankId         = req.BankId;
        emp.AccountNumber  = req.AccountNumber;
        emp.Gender         = req.Gender ?? string.Empty;
        emp.EpfEmployeeRateOverride = req.EpfEmployeeRateOverride;
        emp.EpfEmployerRateOverride = req.EpfEmployerRateOverride;

        await _db.SaveChangesAsync();

        // Keep the employee's login in step (email, active / inactive)
        var loginNote = await _accounts.SyncFromEmployeeAsync(oldEmail, emp);

        await _audit.LogAsync(
            action:      "Updated",
            entityType:  "Employee",
            entityId:    id.ToString(),
            description: $"Updated employee {emp.Name} ({emp.EmployeeCode})" + (loginNote != null ? $"; {loginNote}" : ""),
            username:    CurrentUser(),
            userId:      CurrentUserId(),
            oldValues:   oldSnap,
            newValues:   JsonSerializer.Serialize(new { emp.Name, emp.Email, emp.Designation, emp.Salary, emp.IsActive }),
            ipAddress:   HttpContext.Connection.RemoteIpAddress?.ToString());

        return Ok(new { message = "Employee updated", loginNote });
    }

    /// <summary>
    /// DELETE /api/employees/{id}
    /// Deletes an employee and all related records (cascades).
    /// </summary>
    [HttpDelete("{id:int}")]
    [Authorize(Roles = "Admin")]
    public async Task<IActionResult> Delete(int id)
    {
        var emp = await _db.Employees.FindAsync(id)
            ?? throw new KeyNotFoundException($"Employee {id} not found.");

        var empName = emp.Name;
        var empCode = emp.EmployeeCode;
        var empEmail = emp.Email;
        _db.Employees.Remove(emp);
        await _db.SaveChangesAsync();

        // Someone who no longer works here must not be able to log in (login kept for the audit trail)
        var loginNote = await _accounts.DeactivateForEmployeeAsync(empEmail);

        await _audit.LogAsync(
            action:      "Deleted",
            entityType:  "Employee",
            entityId:    id.ToString(),
            description: $"Deleted employee {empName} ({empCode})" + (loginNote != null ? $"; {loginNote}" : ""),
            username:    CurrentUser(),
            userId:      CurrentUserId(),
            ipAddress:   HttpContext.Connection.RemoteIpAddress?.ToString());

        return NoContent();
    }
}
