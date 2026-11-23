namespace HrmsApi.Models;

// ── School features, phase 3: the child's day ──
// Check-in / check-out (who picked the child up), parents' absence and pickup notes, and the
// daily report (meals, nap, toilet, mood, activities, photos) the teacher publishes for parents.
// Dates are school dates (Malaysia time, see SchoolClock); times are stored in UTC.

/// <summary>A child's attendance on one school day: present (check-in / check-out) or absent.</summary>
public class StudentAttendance
{
    public const string Present = "Present", Absent = "Absent";

    public int       Id            { get; set; }
    public int       StudentId     { get; set; }
    public DateTime  Date          { get; set; }
    public string    Status        { get; set; } = Present;

    public DateTime? CheckInAt     { get; set; }
    public string?   CheckInBy     { get; set; }
    public DateTime? CheckOutAt    { get; set; }
    public string?   CheckOutBy    { get; set; }
    /// <summary>Who collected the child, e.g. "Mounika (Mother)" or "Grandma Lim".</summary>
    public string?   PickedUpBy    { get; set; }
    public string?   AbsenceReason { get; set; }
    public DateTime  UpdatedAt     { get; set; } = DateTime.UtcNow;

    public Student Student { get; set; } = null!;
}

/// <summary>
/// A note from a parent to the school: the child will be absent (one or more days), or someone
/// else will pick them up. The class teacher sees it on the attendance list and marks it seen.
/// </summary>
public class ParentNote
{
    public const string Absence = "Absence", Pickup = "Pickup";
    public static readonly string[] Kinds = { Absence, Pickup };

    public int       Id              { get; set; }
    public int       StudentId       { get; set; }
    public string    Kind            { get; set; } = Absence;
    public DateTime  FromDate        { get; set; }
    /// <summary>Last day of an absence (same as <see cref="FromDate"/> for one day and for pickups).</summary>
    public DateTime  ToDate          { get; set; }
    public string?   PickupName      { get; set; }
    public string?   PickupPhone     { get; set; }
    /// <summary>"15:30" — when they will come.</summary>
    public string?   PickupTime      { get; set; }
    public string?   Message         { get; set; }
    public int       CreatedByUserId { get; set; }
    public string    CreatedByName   { get; set; } = string.Empty;
    public DateTime  CreatedAt       { get; set; } = DateTime.UtcNow;
    public DateTime? SeenAt          { get; set; }
    public string?   SeenByName      { get; set; }
    public DateTime? CancelledAt     { get; set; }

    public Student Student { get; set; } = null!;
}

/// <summary>
/// Someone besides the parents who may collect a child regularly (grandparent, driver…). A parent
/// adds them in the app; they count only once the office approves. One per child.
/// </summary>
public class PickupPerson
{
    public const string Pending = "Pending", Approved = "Approved", Rejected = "Rejected";

    public int       Id              { get; set; }
    public int       StudentId       { get; set; }
    public string    FullName        { get; set; } = string.Empty;
    /// <summary>"Grandmother", "Driver", "Aunt"…</summary>
    public string    Relationship    { get; set; } = string.Empty;
    public string?   Phone           { get; set; }
    public string?   Note            { get; set; }
    public string    Status          { get; set; } = Pending;
    public int       AddedByUserId   { get; set; }
    public string    AddedByName     { get; set; } = string.Empty;
    public DateTime  CreatedAt       { get; set; } = DateTime.UtcNow;
    public DateTime? DecidedAt       { get; set; }
    public string?   DecidedByName   { get; set; }
    /// <summary>Why the office said no (shown to the parent).</summary>
    public string?   RejectReason    { get; set; }

    public Student Student { get; set; } = null!;
}

/// <summary>The teacher's report on a child's day. Parents see it once published.</summary>
public class DailyReport
{
    public static readonly string[] MealAmounts = { "All", "Most", "Some", "None" };
    public static readonly string[] Moods = { "Happy", "Calm", "Tired", "Upset", "Unwell" };
    public const int MaxPhotos = 6;
    public const int MaxPhotoBytes = 5 * 1024 * 1024;

    public int       Id            { get; set; }
    public int       StudentId     { get; set; }
    public DateTime  Date          { get; set; }
    public string?   Breakfast     { get; set; }
    public string?   Lunch         { get; set; }
    public string?   Snack         { get; set; }
    /// <summary>"12:30" – "14:00"; empty when the child didn't nap.</summary>
    public string?   NapFrom       { get; set; }
    public string?   NapTo         { get; set; }
    /// <summary>Free text, e.g. "Diaper changed 3 times" or "Used the toilet".</summary>
    public string?   Toilet        { get; set; }
    public string?   Mood          { get; set; }
    public string?   Activities    { get; set; }
    public string?   TeacherNote   { get; set; }
    public DateTime? PublishedAt   { get; set; }
    public string    UpdatedByName { get; set; } = string.Empty;
    public DateTime  UpdatedAt     { get; set; } = DateTime.UtcNow;

    public Student Student { get; set; } = null!;
    public List<DailyReportPhoto> Photos { get; set; } = new();
}

/// <summary>A photo on a daily report (in the company's database, never at a public address).</summary>
public class DailyReportPhoto
{
    public int      Id            { get; set; }
    public int      DailyReportId { get; set; }
    public string   FileName      { get; set; } = string.Empty;
    public string   ContentType   { get; set; } = string.Empty;
    public int      SizeBytes     { get; set; }
    public byte[]   Data          { get; set; } = Array.Empty<byte>();
    public DateTime CreatedAt     { get; set; } = DateTime.UtcNow;

    public DailyReport Report { get; set; } = null!;
}
