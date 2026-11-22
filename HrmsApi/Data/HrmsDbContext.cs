using HrmsApi.Models;
using Microsoft.EntityFrameworkCore;

namespace HrmsApi.Data;

public class HrmsDbContext : DbContext
{
    public HrmsDbContext(DbContextOptions<HrmsDbContext> options) : base(options) { }

    // ── DbSets ───────────────────────────────────────��────────
    public DbSet<User>                  Users                 => Set<User>();
    public DbSet<Department>            Departments           => Set<Department>();
    public DbSet<BankMaster>            BankMasters           => Set<BankMaster>();
    public DbSet<Employee>              Employees             => Set<Employee>();
    public DbSet<Attendance>            Attendances           => Set<Attendance>();
    public DbSet<Payroll>               Payrolls              => Set<Payroll>();
    public DbSet<PublicHoliday>         PublicHolidays        => Set<PublicHoliday>();
    public DbSet<Timesheet>             Timesheets            => Set<Timesheet>();
    public DbSet<LeaveType>             LeaveTypes            => Set<LeaveType>();
    public DbSet<EmployeeLeaveBalance>  EmployeeLeaveBalances => Set<EmployeeLeaveBalance>();
    public DbSet<LeaveRequest>          LeaveRequests         => Set<LeaveRequest>();
    public DbSet<AttendancePeriod>      AttendancePeriods     => Set<AttendancePeriod>();
    public DbSet<AttendancePeriodDay>   AttendancePeriodDays  => Set<AttendancePeriodDay>();
    public DbSet<PayrollAttendancePeriod> PayrollAttendancePeriods => Set<PayrollAttendancePeriod>();
    public DbSet<PayrollLeaveRequest>   PayrollLeaveRequests  => Set<PayrollLeaveRequest>();
    public DbSet<PayrollAdjustment>     PayrollAdjustments    => Set<PayrollAdjustment>();
    public DbSet<Notification>          Notifications         => Set<Notification>();
    public DbSet<AuditLog>              AuditLogs             => Set<AuditLog>();
    public DbSet<CompanySettings>       CompanySettings       => Set<CompanySettings>();
    public DbSet<StatutoryRateSet>      StatutoryRateSets     => Set<StatutoryRateSet>();
    public DbSet<LeaveAttachment>       LeaveAttachments      => Set<LeaveAttachment>();
    public DbSet<DeviceToken>           DeviceTokens          => Set<DeviceToken>();

    // ── School features ──
    public DbSet<SchoolClass>           SchoolClasses         => Set<SchoolClass>();
    public DbSet<Student>               Students              => Set<Student>();
    public DbSet<Parent>                Parents               => Set<Parent>();
    public DbSet<StudentParent>         StudentParents        => Set<StudentParent>();
    public DbSet<Announcement>          Announcements         => Set<Announcement>();
    public DbSet<AnnouncementRead>      AnnouncementReads     => Set<AnnouncementRead>();
    public DbSet<Conversation>          Conversations         => Set<Conversation>();
    public DbSet<ChatMessage>           ChatMessages          => Set<ChatMessage>();
    public DbSet<ChatAttachment>        ChatAttachments       => Set<ChatAttachment>();
    public DbSet<ConversationRead>      ConversationReads     => Set<ConversationRead>();
    public DbSet<StudentAttendance>     StudentAttendance     => Set<StudentAttendance>();
    public DbSet<ParentNote>            ParentNotes           => Set<ParentNote>();
    public DbSet<DailyReport>           DailyReports          => Set<DailyReport>();
    public DbSet<DailyReportPhoto>      DailyReportPhotos     => Set<DailyReportPhoto>();
    public DbSet<FeeItem>               FeeItems              => Set<FeeItem>();
    public DbSet<StudentFeeAddOn>       StudentFeeAddOns      => Set<StudentFeeAddOn>();
    public DbSet<FeeInvoice>            FeeInvoices           => Set<FeeInvoice>();
    public DbSet<FeeInvoiceLine>        FeeInvoiceLines       => Set<FeeInvoiceLine>();
    public DbSet<FeePayment>            FeePayments           => Set<FeePayment>();
    public DbSet<FeePaymentClaim>       FeePaymentClaims      => Set<FeePaymentClaim>();
    public DbSet<BotFaq>                BotFaqs               => Set<BotFaq>();
    public DbSet<BotUnanswered>         BotUnansweredQuestions => Set<BotUnanswered>();
    public DbSet<BotAiUsage>            BotAiUsageLog         => Set<BotAiUsage>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        base.OnModelCreating(modelBuilder);

        // ── CompanySettings (single row, Id = 1) ─────────────
        modelBuilder.Entity<CompanySettings>(e =>
        {
            e.ToTable("CompanySettings");
            e.Property(x => x.Id).ValueGeneratedNever();
        });

        // ── StatutoryRateSet (EPF / SOCSO / EIS / PCB rates by effective date) ──
        modelBuilder.Entity<StatutoryRateSet>(e =>
        {
            e.ToTable("StatutoryRateSets");
            e.Property(x => x.Name).IsRequired().HasMaxLength(100);
            e.Property(x => x.Notes).HasMaxLength(500);
            e.HasIndex(x => x.EffectiveFrom).IsUnique();
            e.Property(x => x.EpfEmployeeRate).HasPrecision(6, 3);
            e.Property(x => x.EpfEmployerRate).HasPrecision(6, 3);
            e.Property(x => x.EpfEmployerRateAboveThreshold).HasPrecision(6, 3);
            e.Property(x => x.EpfEmployerThreshold).HasPrecision(18, 2);
            e.Property(x => x.EisEmployeeRate).HasPrecision(6, 3);
            e.Property(x => x.EisEmployerRate).HasPrecision(6, 3);
            e.Property(x => x.EisWageCeiling).HasPrecision(18, 2);
            e.Property(x => x.TaxPersonalRelief).HasPrecision(18, 2);
            e.Property(x => x.SocsoBandsJson).IsRequired();
            e.Property(x => x.TaxBandsJson).IsRequired();
        });

        // ── BankMaster ────────────────────────────────────────
        modelBuilder.Entity<BankMaster>(e =>
        {
            e.ToTable("BankMaster");
        });

        // ── User ──────────────────────────────────────────────
        // DB has: Id, Username, Email, PasswordHash, Role, IsActive, CreatedAt,
        //         PasswordResetToken, PasswordResetTokenExpiry — all mapped
        modelBuilder.Entity<User>(e =>
        {

            e.Property(x => x.Email).HasMaxLength(255);
            e.HasIndex(x => x.Email)
             .IsUnique()
             .HasFilter("\"Email\" IS NOT NULL AND \"Email\" <> ''");
        });

        // ── Department ────────────────────────────────────────
        // DB has: Id, Name, Description, IsActive, CreatedAt — all match
        modelBuilder.Entity<Department>(e =>
        {
            e.ToTable("Departments");
        });

        // ── Employee ──────────────────────────────────────────
        // DB columns: FirstName, LastName, PhoneNumber, JoiningDate, BankAccountNumber
        // Model uses: Name, Phone, JoinDate, AccountNumber — map them
        // DB has all model columns directly — Name, Phone, JoinDate, AccountNumber match exactly
        // IcPassport, TaxNumber, ProfilePicture also exist in DB — all mapped, no ignores
        modelBuilder.Entity<Employee>(e =>
        {
            e.Property(x => x.EmployeeCode).IsRequired().HasMaxLength(20);
            e.HasIndex(x => x.EmployeeCode).IsUnique();
            e.Property(x => x.Salary).HasPrecision(18, 2);
            e.Property(x => x.EpfEmployeeRateOverride).HasPrecision(6, 3);
            e.Property(x => x.EpfEmployerRateOverride).HasPrecision(6, 3);

            e.HasOne(x => x.Department)
             .WithMany(d => d.Employees)
             .HasForeignKey(x => x.DepartmentId)
             .OnDelete(DeleteBehavior.SetNull);

            e.HasOne(x => x.Bank)
             .WithMany(b => b.Employees)
             .HasForeignKey(x => x.BankId)
             .OnDelete(DeleteBehavior.SetNull);
        });

        // ── Payroll ───────────────────────────────────────────
        // DB has all model columns directly — no renames, no ignores needed
        modelBuilder.Entity<Payroll>(e =>
        {
            e.Property(x => x.BasicSalary).HasPrecision(18, 2);
            e.Property(x => x.Allowances).HasPrecision(18, 2);
            e.Property(x => x.Deductions).HasPrecision(18, 2);
            e.Property(x => x.EpfAmount).HasPrecision(18, 2);
            e.Property(x => x.SocsoAmount).HasPrecision(18, 2);
            e.Property(x => x.TaxAmount).HasPrecision(18, 2);
            e.Property(x => x.EisAmount).HasPrecision(18, 2);
            e.Property(x => x.EpfEmployerAmount).HasPrecision(18, 2);
            e.Property(x => x.SocsoEmployerAmount).HasPrecision(18, 2);
            e.Property(x => x.EisEmployerAmount).HasPrecision(18, 2);
            e.Property(x => x.EpfEmployeeRate).HasPrecision(6, 3);
            e.Property(x => x.EpfEmployerRate).HasPrecision(6, 3);
            e.Property(x => x.StatutoryRateSetName).HasMaxLength(100);
            e.Property(x => x.GrossIncome).HasPrecision(18, 2);
            e.Property(x => x.NetSalary).HasPrecision(18, 2);
            e.Property(x => x.AttendanceHours).HasPrecision(10, 2);
            e.Property(x => x.ExpectedHours).HasPrecision(10, 2);

            e.HasOne(x => x.Approver)
             .WithMany()
             .HasForeignKey(x => x.ApprovedBy)
             .OnDelete(DeleteBehavior.Restrict);

            e.HasOne(x => x.Processor)
             .WithMany()
             .HasForeignKey(x => x.ProcessedBy)
             .OnDelete(DeleteBehavior.Restrict);
        });

        modelBuilder.Entity<Payroll>()
            .HasOne(p => p.Employee)
            .WithMany(e => e.Payrolls)
            .HasForeignKey(p => p.EmployeeId)
            .OnDelete(DeleteBehavior.Cascade);

        // One payroll record per employee per month/year
        modelBuilder.Entity<Payroll>()
            .HasIndex(p => new { p.EmployeeId, p.Month, p.Year })
            .IsUnique();

        // ── PayrollAttendancePeriod ───────────────────────────
        // DB has: Id, PayrollId, AttendancePeriodId, HoursWorked, CreatedAt — all mapped
        modelBuilder.Entity<PayrollAttendancePeriod>(e =>
        {
            e.Property(x => x.HoursWorked).HasPrecision(10, 2);

            e.HasOne(x => x.Payroll)
             .WithMany(p => p.AttendancePeriods)
             .HasForeignKey(x => x.PayrollId)
             .OnDelete(DeleteBehavior.Cascade);

            e.HasOne(x => x.AttendancePeriod)
             .WithMany()
             .HasForeignKey(x => x.AttendancePeriodId)
             .OnDelete(DeleteBehavior.Restrict);

            e.HasIndex(x => new { x.PayrollId, x.AttendancePeriodId }).IsUnique();
        });

        // ── PayrollLeaveRequest ───────────────────────────────
        // DB has: Id, PayrollId, LeaveRequestId, LeaveDays, IsPaid, DeductionAmount, CreatedAt — all mapped
        modelBuilder.Entity<PayrollLeaveRequest>(e =>
        {
            e.Property(x => x.LeaveDays).HasPrecision(5, 2);
            e.Property(x => x.DeductionAmount).HasPrecision(10, 2);

            e.HasOne(x => x.Payroll)
             .WithMany(p => p.LeaveRequests)
             .HasForeignKey(x => x.PayrollId)
             .OnDelete(DeleteBehavior.Cascade);

            e.HasOne(x => x.LeaveRequest)
             .WithMany()
             .HasForeignKey(x => x.LeaveRequestId)
             .OnDelete(DeleteBehavior.Restrict);

            e.HasIndex(x => new { x.PayrollId, x.LeaveRequestId }).IsUnique();
        });

        // ── PayrollAdjustment ─────────────────────────────────
        // DB has: Id, PayrollId, AdjustmentType, Description, Amount, CreatedBy, CreatedAt — all match
        modelBuilder.Entity<PayrollAdjustment>(e =>
        {
            e.Property(x => x.Amount).HasPrecision(10, 2);

            e.HasOne(x => x.Payroll)
             .WithMany(p => p.Adjustments)
             .HasForeignKey(x => x.PayrollId)
             .OnDelete(DeleteBehavior.Cascade);

            e.HasOne(x => x.Creator)
             .WithMany()
             .HasForeignKey(x => x.CreatedBy)
             .OnDelete(DeleteBehavior.Restrict);
        });

        // ── Attendance ────────────────────────────────────────
        // DB has: Id, EmployeeId, Date, TimeIn, TimeOut, WorkHours, Status, Remarks, CreatedAt
        modelBuilder.Entity<Attendance>(e =>
        {
            e.Property(x => x.WorkHours).HasPrecision(10, 2);
            e.Property(x => x.CheckIn).HasColumnName("TimeIn");
            e.Property(x => x.CheckOut).HasColumnName("TimeOut");

            e.HasOne(x => x.Employee)
             .WithMany(emp => emp.Attendances)
             .HasForeignKey(x => x.EmployeeId)
             .OnDelete(DeleteBehavior.Cascade);
        });

        // One attendance record per employee per calendar day
        modelBuilder.Entity<Attendance>()
            .HasIndex(a => new { a.EmployeeId, a.Date })
            .IsUnique();

        // ── AttendancePeriod ──────────────────────────────────
        // DB has: Id, EmployeeId, StartDate, EndDate, Status, CreatedAt,
        //         SubmittedAt, ApprovedAt, RejectedAt, ApprovedBy,
        //         RejectedBy, RejectionReason, Remarks — all mapped
        modelBuilder.Entity<AttendancePeriod>(e =>
        {
            e.HasOne(x => x.Employee)
             .WithMany()
             .HasForeignKey(x => x.EmployeeId)
             .OnDelete(DeleteBehavior.Cascade);

            e.HasIndex(x => new { x.EmployeeId, x.StartDate, x.EndDate }).IsUnique();
        });

        // ── AttendancePeriodDay ───────────────────────────────
        // DB has: Id, AttendancePeriodId, Date, Hours, Note,
        //         Remarks, IsPublicHoliday, IsWeekend — all mapped
        modelBuilder.Entity<AttendancePeriodDay>(e =>
        {
            e.Property(x => x.Hours).HasPrecision(5, 2);

            e.HasOne(x => x.AttendancePeriod)
             .WithMany(ap => ap.Days)
             .HasForeignKey(x => x.AttendancePeriodId)
             .OnDelete(DeleteBehavior.Cascade);

            e.HasIndex(x => new { x.AttendancePeriodId, x.Date }).IsUnique();
        });

        // ── PublicHoliday ─────────────────────────────────────
        // DB has: Id, Name, Date, Year, IsNational, State, Description, CreatedAt — all match
        // (no ignores needed)

        // ── Notification ──────────────────────────────────────
        // DB has: Id, UserId, Title, Message, Type, Link, IsRead, CreatedAt, ReadAt — all mapped
        // No ignores needed

        // ── Timesheet ─────────────────────────────────────────
        modelBuilder.Entity<Timesheet>(e =>
        {
            e.Property(x => x.TotalWorkHours).HasPrecision(10, 2);

            e.HasOne(x => x.Employee)
             .WithMany()
             .HasForeignKey(x => x.EmployeeId)
             .OnDelete(DeleteBehavior.Cascade);

            e.HasIndex(x => new { x.EmployeeId, x.Year, x.Month }).IsUnique();
        });

        // ── LeaveType ─────────────────────────────────────────
        // DB has: Id, Name, Code, Description, DefaultDaysPerYear, IsActive,
        //         RequiresApproval, IsPaid, CreatedAt — all match

        // ── EmployeeLeaveBalance ──────────────────────────────
        // DB has: Id, EmployeeId, LeaveTypeId, Year, TotalDays, UsedDays,
        //         BalanceDays, CarryForwardDays, CreatedAt, UpdatedAt — all match
        modelBuilder.Entity<EmployeeLeaveBalance>(e =>
        {
            e.Property(x => x.TotalDays).HasPrecision(5, 2);
            e.Property(x => x.UsedDays).HasPrecision(5, 2);
            e.Property(x => x.BalanceDays).HasPrecision(5, 2);
            e.Property(x => x.CarryForwardDays).HasPrecision(5, 2);

            e.HasOne(x => x.Employee)
             .WithMany()
             .HasForeignKey(x => x.EmployeeId)
             .OnDelete(DeleteBehavior.Cascade);

            e.HasOne(x => x.LeaveType)
             .WithMany(lt => lt.LeaveBalances)
             .HasForeignKey(x => x.LeaveTypeId)
             .OnDelete(DeleteBehavior.Cascade);

            e.HasIndex(x => new { x.EmployeeId, x.LeaveTypeId, x.Year }).IsUnique();
        });

        // ── LeaveRequest ──────────────────────────────────────
        // DB has all model columns directly — RequestedOn, ApprovedOn, ApprovalRemarks,
        // CancelledOn, CancellationReason all match — no renames, no ignores
        modelBuilder.Entity<LeaveRequest>(e =>
        {
            e.Property(x => x.TotalDays).HasPrecision(5, 2);

            e.HasOne(x => x.Employee)
             .WithMany()
             .HasForeignKey(x => x.EmployeeId)
             .OnDelete(DeleteBehavior.Cascade);

            e.HasOne(x => x.LeaveType)
             .WithMany(lt => lt.LeaveRequests)
             .HasForeignKey(x => x.LeaveTypeId)
             .OnDelete(DeleteBehavior.Restrict);
        });

        // ── LeaveAttachment (MC letter etc.; one per leave request) ──
        modelBuilder.Entity<LeaveAttachment>(e =>
        {
            e.ToTable("LeaveAttachments");
            e.Property(x => x.FileName).IsRequired().HasMaxLength(255);
            e.Property(x => x.ContentType).IsRequired().HasMaxLength(100);
            e.Property(x => x.Data).IsRequired();
            e.HasIndex(x => x.LeaveRequestId).IsUnique();

            e.HasOne(x => x.LeaveRequest)
             .WithMany()
             .HasForeignKey(x => x.LeaveRequestId)
             .OnDelete(DeleteBehavior.Cascade);
        });

        // ── User: current login session (one login at a time) ──
        modelBuilder.Entity<User>().Property(x => x.CurrentSessionId).HasMaxLength(64);
        modelBuilder.Entity<User>().Property(x => x.RefreshTokenHash).HasMaxLength(64);

        // ── Push notification devices ──
        modelBuilder.Entity<DeviceToken>(e =>
        {
            e.Property(x => x.Token).HasMaxLength(512).IsRequired();
            e.Property(x => x.Platform).HasMaxLength(20);
            e.HasIndex(x => x.Token).IsUnique();
            e.HasOne(x => x.User).WithMany().HasForeignKey(x => x.UserId).OnDelete(DeleteBehavior.Cascade);
        });

        ConfigureSchool(modelBuilder);
    }

    /// <summary>School features: classes, children, parents, announcements, messages.</summary>
    private static void ConfigureSchool(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<SchoolClass>(e =>
        {
            e.Property(x => x.Name).IsRequired().HasMaxLength(50);
            e.Property(x => x.Description).HasMaxLength(200);
            e.HasIndex(x => x.Name).IsUnique();
            // Deleting a teacher's employee record leaves the class without a teacher
            e.HasOne(x => x.ClassTeacher).WithMany().HasForeignKey(x => x.ClassTeacherId).OnDelete(DeleteBehavior.SetNull);
        });

        modelBuilder.Entity<Student>(e =>
        {
            e.Property(x => x.FullName).IsRequired().HasMaxLength(150);
            e.Property(x => x.AdmissionNo).HasMaxLength(30);
            e.Property(x => x.Gender).HasMaxLength(10);
            e.Property(x => x.SessionType).IsRequired().HasMaxLength(20);
            e.Property(x => x.MedicalNotes).HasMaxLength(1000);
            e.Property(x => x.EmergencyContactName).HasMaxLength(150);
            e.Property(x => x.EmergencyContactPhone).HasMaxLength(30);
            e.Property(x => x.Notes).HasMaxLength(1000);
            e.HasIndex(x => x.ClassId);
            e.HasOne(x => x.Class).WithMany(c => c.Students).HasForeignKey(x => x.ClassId).OnDelete(DeleteBehavior.Restrict);
        });

        modelBuilder.Entity<Parent>(e =>
        {
            e.Property(x => x.FullName).IsRequired().HasMaxLength(150);
            e.Property(x => x.Email).HasMaxLength(150);
            e.Property(x => x.Phone).HasMaxLength(30);
            e.Property(x => x.Relationship).IsRequired().HasMaxLength(20);
            e.HasIndex(x => x.UserId).IsUnique();
            // The login is removed with the parent (ParentsController deletes both)
            e.HasOne(x => x.User).WithMany().HasForeignKey(x => x.UserId).OnDelete(DeleteBehavior.SetNull);
        });

        modelBuilder.Entity<StudentParent>(e =>
        {
            e.HasKey(x => new { x.StudentId, x.ParentId });
            e.HasIndex(x => x.ParentId);
            e.HasOne(x => x.Student).WithMany(s => s.Parents).HasForeignKey(x => x.StudentId).OnDelete(DeleteBehavior.Cascade);
            e.HasOne(x => x.Parent).WithMany(p => p.Children).HasForeignKey(x => x.ParentId).OnDelete(DeleteBehavior.Cascade);
        });

        modelBuilder.Entity<Announcement>(e =>
        {
            e.Property(x => x.Title).IsRequired().HasMaxLength(150);
            e.Property(x => x.Body).IsRequired().HasMaxLength(4000);
            e.Property(x => x.CreatedByName).IsRequired().HasMaxLength(150);
            e.Property(x => x.AttachmentName).HasMaxLength(255);
            e.Property(x => x.AttachmentContentType).HasMaxLength(100);
            e.HasIndex(x => x.CreatedAt);
            e.HasOne(x => x.Class).WithMany().HasForeignKey(x => x.ClassId).OnDelete(DeleteBehavior.Cascade);
        });

        modelBuilder.Entity<AnnouncementRead>(e =>
        {
            e.HasKey(x => new { x.AnnouncementId, x.UserId });
            e.HasOne(x => x.Announcement).WithMany().HasForeignKey(x => x.AnnouncementId).OnDelete(DeleteBehavior.Cascade);
        });

        modelBuilder.Entity<Conversation>(e =>
        {
            e.Property(x => x.Kind).IsRequired().HasMaxLength(20);
            e.Property(x => x.Subject).IsRequired().HasMaxLength(Conversation.MaxSubjectLength).HasDefaultValue(Conversation.DefaultSubject);
            e.Property(x => x.Status).IsRequired().HasMaxLength(10).HasDefaultValue(Conversation.Open);
            e.Property(x => x.ClosedByName).HasMaxLength(150);
            // Many conversations per child and kind (one per subject)
            e.HasIndex(x => new { x.StudentId, x.Kind });
            e.HasIndex(x => x.LastMessageAt);
            e.HasOne(x => x.Student).WithMany().HasForeignKey(x => x.StudentId).OnDelete(DeleteBehavior.Cascade);
        });

        modelBuilder.Entity<ChatMessage>(e =>
        {
            e.ToTable("ChatMessages");
            e.Property(x => x.SenderName).IsRequired().HasMaxLength(150);
            e.Property(x => x.SenderRole).IsRequired().HasMaxLength(20);
            e.Property(x => x.Body).IsRequired().HasMaxLength(ChatMessage.MaxBodyLength);
            e.HasIndex(x => new { x.ConversationId, x.Id });
            e.HasOne(x => x.Conversation).WithMany(c => c.Messages).HasForeignKey(x => x.ConversationId).OnDelete(DeleteBehavior.Cascade);
        });

        modelBuilder.Entity<ChatAttachment>(e =>
        {
            e.ToTable("ChatAttachments");
            e.Property(x => x.FileName).IsRequired().HasMaxLength(255);
            e.Property(x => x.ContentType).IsRequired().HasMaxLength(100);
            e.Property(x => x.Data).IsRequired();
            e.HasIndex(x => x.MessageId).IsUnique();
            e.HasOne(x => x.Message).WithOne(m => m.Attachment).HasForeignKey<ChatAttachment>(x => x.MessageId).OnDelete(DeleteBehavior.Cascade);
        });

        modelBuilder.Entity<ConversationRead>(e =>
        {
            e.HasKey(x => new { x.ConversationId, x.UserId });
            e.HasOne(x => x.Conversation).WithMany().HasForeignKey(x => x.ConversationId).OnDelete(DeleteBehavior.Cascade);
        });

        ConfigureSchoolDay(modelBuilder);
        ConfigureSchoolFees(modelBuilder);
        ConfigureAssistant(modelBuilder);
    }

    /// <summary>School phase 3: attendance, parents' notes, daily reports.</summary>
    private static void ConfigureSchoolDay(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<StudentAttendance>(e =>
        {
            e.ToTable("StudentAttendance");
            e.Property(x => x.Date).HasColumnType("date");
            e.Property(x => x.Status).IsRequired().HasMaxLength(20);
            e.Property(x => x.CheckInBy).HasMaxLength(150);
            e.Property(x => x.CheckOutBy).HasMaxLength(150);
            e.Property(x => x.PickedUpBy).HasMaxLength(150);
            e.Property(x => x.AbsenceReason).HasMaxLength(300);
            e.HasIndex(x => new { x.StudentId, x.Date }).IsUnique();
            e.HasIndex(x => x.Date);
            e.HasOne(x => x.Student).WithMany().HasForeignKey(x => x.StudentId).OnDelete(DeleteBehavior.Cascade);
        });

        modelBuilder.Entity<ParentNote>(e =>
        {
            e.Property(x => x.Kind).IsRequired().HasMaxLength(20);
            e.Property(x => x.FromDate).HasColumnType("date");
            e.Property(x => x.ToDate).HasColumnType("date");
            e.Property(x => x.PickupName).HasMaxLength(150);
            e.Property(x => x.PickupPhone).HasMaxLength(30);
            e.Property(x => x.PickupTime).HasMaxLength(5);
            e.Property(x => x.Message).HasMaxLength(1000);
            e.Property(x => x.CreatedByName).IsRequired().HasMaxLength(150);
            e.Property(x => x.SeenByName).HasMaxLength(150);
            e.HasIndex(x => new { x.StudentId, x.FromDate });
            e.HasIndex(x => x.ToDate);
            e.HasOne(x => x.Student).WithMany().HasForeignKey(x => x.StudentId).OnDelete(DeleteBehavior.Cascade);
        });

        modelBuilder.Entity<DailyReport>(e =>
        {
            e.Property(x => x.Date).HasColumnType("date");
            e.Property(x => x.Breakfast).HasMaxLength(10);
            e.Property(x => x.Lunch).HasMaxLength(10);
            e.Property(x => x.Snack).HasMaxLength(10);
            e.Property(x => x.NapFrom).HasMaxLength(5);
            e.Property(x => x.NapTo).HasMaxLength(5);
            e.Property(x => x.Toilet).HasMaxLength(200);
            e.Property(x => x.Mood).HasMaxLength(20);
            e.Property(x => x.Activities).HasMaxLength(1000);
            e.Property(x => x.TeacherNote).HasMaxLength(1000);
            e.Property(x => x.UpdatedByName).IsRequired().HasMaxLength(150);
            e.HasIndex(x => new { x.StudentId, x.Date }).IsUnique();
            e.HasIndex(x => x.Date);
            e.HasOne(x => x.Student).WithMany().HasForeignKey(x => x.StudentId).OnDelete(DeleteBehavior.Cascade);
        });

        modelBuilder.Entity<DailyReportPhoto>(e =>
        {
            e.Property(x => x.FileName).IsRequired().HasMaxLength(255);
            e.Property(x => x.ContentType).IsRequired().HasMaxLength(100);
            e.Property(x => x.Data).IsRequired();
            e.HasIndex(x => x.DailyReportId);
            e.HasOne(x => x.Report).WithMany(r => r.Photos).HasForeignKey(x => x.DailyReportId).OnDelete(DeleteBehavior.Cascade);
        });
    }

    /// <summary>School phase 4: fee items, add-ons, invoices, payments.</summary>
    /// <summary>Help chatbot: admins' questions and answers, and questions it couldn't answer.</summary>
    private static void ConfigureAssistant(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<BotFaq>(e =>
        {
            e.Property(x => x.Category).IsRequired().HasMaxLength(BotFaq.MaxCategoryLength);
            e.Property(x => x.Question).IsRequired().HasMaxLength(BotFaq.MaxQuestionLength);
            e.Property(x => x.Answer).IsRequired().HasMaxLength(BotFaq.MaxAnswerLength);
            e.Property(x => x.Keywords).HasMaxLength(BotFaq.MaxKeywordsLength);
            e.Property(x => x.Audience).IsRequired().HasMaxLength(20);
            e.Property(x => x.Action).HasMaxLength(40);
        });

        modelBuilder.Entity<BotUnanswered>(e =>
        {
            e.ToTable("BotUnanswered");
            e.Property(x => x.Text).IsRequired().HasMaxLength(BotUnanswered.MaxTextLength);
            e.Property(x => x.Audience).IsRequired().HasMaxLength(20);
            e.HasIndex(x => x.AskedAt);
        });

        modelBuilder.Entity<BotAiUsage>(e =>
        {
            e.ToTable("BotAiUsage");
            e.Property(x => x.Model).IsRequired().HasMaxLength(60);
            e.HasIndex(x => new { x.UserId, x.AskedAt });
            e.HasIndex(x => x.AskedAt);
        });
    }

    private static void ConfigureSchoolFees(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<CompanySettings>().Property(x => x.SiblingDiscountPercent).HasPrecision(5, 2);

        modelBuilder.Entity<FeeItem>(e =>
        {
            e.Property(x => x.Name).IsRequired().HasMaxLength(100);
            e.Property(x => x.Kind).IsRequired().HasMaxLength(20);
            e.Property(x => x.SessionType).HasMaxLength(20);
            e.Property(x => x.Amount).HasPrecision(10, 2);
        });

        modelBuilder.Entity<StudentFeeAddOn>(e =>
        {
            e.HasKey(x => new { x.StudentId, x.FeeItemId });
            e.HasIndex(x => x.FeeItemId);
            e.HasOne(x => x.Student).WithMany().HasForeignKey(x => x.StudentId).OnDelete(DeleteBehavior.Cascade);
            e.HasOne(x => x.FeeItem).WithMany().HasForeignKey(x => x.FeeItemId).OnDelete(DeleteBehavior.Cascade);
        });

        modelBuilder.Entity<FeeInvoice>(e =>
        {
            e.Property(x => x.InvoiceNo).IsRequired().HasMaxLength(30);
            e.Property(x => x.IssueDate).HasColumnType("date");
            e.Property(x => x.DueDate).HasColumnType("date");
            e.Property(x => x.Subtotal).HasPrecision(10, 2);
            e.Property(x => x.Discount).HasPrecision(10, 2);
            e.Property(x => x.Total).HasPrecision(10, 2);
            e.Property(x => x.AmountPaid).HasPrecision(10, 2);
            e.Property(x => x.Status).IsRequired().HasMaxLength(20);
            e.Property(x => x.Notes).HasMaxLength(500);
            e.Property(x => x.VoidReason).HasMaxLength(300);
            e.Property(x => x.CreatedByName).IsRequired().HasMaxLength(150);
            e.Ignore(x => x.Balance);
            e.HasIndex(x => x.InvoiceNo).IsUnique();
            e.HasIndex(x => new { x.Year, x.Month });
            e.HasIndex(x => new { x.StudentId, x.Year, x.Month });
            // Invoices are financial records: a child with invoices can't be deleted (mark inactive instead)
            e.HasOne(x => x.Student).WithMany().HasForeignKey(x => x.StudentId).OnDelete(DeleteBehavior.Restrict);
        });

        modelBuilder.Entity<FeeInvoiceLine>(e =>
        {
            e.Property(x => x.Description).IsRequired().HasMaxLength(150);
            e.Property(x => x.Amount).HasPrecision(10, 2);
            e.HasIndex(x => x.InvoiceId);
            e.HasOne(x => x.Invoice).WithMany(i => i.Lines).HasForeignKey(x => x.InvoiceId).OnDelete(DeleteBehavior.Cascade);
        });

        modelBuilder.Entity<FeePayment>(e =>
        {
            e.Property(x => x.ReceiptNo).IsRequired().HasMaxLength(30);
            e.Property(x => x.Amount).HasPrecision(10, 2);
            e.Property(x => x.PaidOn).HasColumnType("date");
            e.Property(x => x.Method).IsRequired().HasMaxLength(30);
            e.Property(x => x.Reference).HasMaxLength(100);
            e.Property(x => x.RecordedByName).IsRequired().HasMaxLength(150);
            e.HasIndex(x => x.ReceiptNo).IsUnique();
            e.HasIndex(x => x.InvoiceId);
            e.HasOne(x => x.Invoice).WithMany(i => i.Payments).HasForeignKey(x => x.InvoiceId).OnDelete(DeleteBehavior.Cascade);
        });

        modelBuilder.Entity<FeePaymentClaim>(e =>
        {
            e.Property(x => x.Amount).HasPrecision(10, 2);
            e.Property(x => x.PaidOn).HasColumnType("date");
            e.Property(x => x.Method).IsRequired().HasMaxLength(30);
            e.Property(x => x.Reference).HasMaxLength(100);
            e.Property(x => x.Note).HasMaxLength(500);
            e.Property(x => x.SlipName).HasMaxLength(255);
            e.Property(x => x.SlipContentType).HasMaxLength(100);
            e.Property(x => x.Status).IsRequired().HasMaxLength(20);
            e.Property(x => x.RejectReason).HasMaxLength(300);
            e.Property(x => x.CreatedByName).IsRequired().HasMaxLength(150);
            e.Property(x => x.ReviewedByName).HasMaxLength(150);
            e.HasIndex(x => new { x.InvoiceId, x.Status });
            e.HasIndex(x => x.Status);
            e.HasOne(x => x.Invoice).WithMany(i => i.Claims).HasForeignKey(x => x.InvoiceId).OnDelete(DeleteBehavior.Cascade);
        });
    }
}
