namespace HrmsApi.Models;

// ── Timetable, profile photos and class stories (school features) ──

/// <summary>
/// One period of a class's weekly timetable, e.g. Monday 09:00–10:00 "Phonics" with Ms Aisha.
/// Class teachers set up their class's plan (admins view it and the daily record); teachers see
/// "My timetable", parents their child's class.
/// </summary>
public class TimetableSlot
{
    public int      Id                { get; set; }
    public int      ClassId           { get; set; }
    /// <summary>1 = Monday … 7 = Sunday (ISO).</summary>
    public int      DayOfWeek         { get; set; }
    public TimeSpan StartTime         { get; set; }
    public TimeSpan EndTime           { get; set; }
    /// <summary>What is taught, e.g. "Phonics", "Outdoor play", "Lunch".</summary>
    public string   Subject           { get; set; } = string.Empty;
    /// <summary>Who teaches it (any employee); null = the class teacher.</summary>
    public int?     TeacherEmployeeId { get; set; }
    public string?  Notes             { get; set; }
    public DateTime CreatedAt         { get; set; } = DateTime.UtcNow;
    /// <summary>First school date the period is part of the plan (the day it was added).</summary>
    public DateTime ActiveFrom        { get; set; }
    /// <summary>
    /// School date it was removed (not part of the plan from that day). Periods are never deleted, so
    /// past weeks and their "what we covered" notes stay as they were.
    /// </summary>
    public DateTime? RemovedOn        { get; set; }

    public SchoolClass Class   { get; set; } = null!;
    public Employee?   Teacher { get; set; }
    public List<TimetableLog> Logs { get; set; } = new();
}

/// <summary>"What we covered" — the teacher's note for one period on one day (parents see it).</summary>
public class TimetableLog
{
    public int      Id            { get; set; }
    public int      SlotId        { get; set; }
    /// <summary>School date (Malaysia time, <c>SchoolClock</c>).</summary>
    public DateTime Date          { get; set; }
    public string   Note          { get; set; } = string.Empty;
    public string   UpdatedByName { get; set; } = string.Empty;
    public DateTime UpdatedAt     { get; set; } = DateTime.UtcNow;

    // The period as it was on that day (the plan may change later). Null on notes written before these were kept.
    public TimeSpan? StartTime    { get; set; }
    public TimeSpan? EndTime      { get; set; }
    public string?   Subject      { get; set; }
    public string?   TeacherName  { get; set; }

    public TimetableSlot Slot { get; set; } = null!;
}

/// <summary>
/// Profile photo of a child or a parent, kept in the company's database (never in the public
/// uploads folder) and served only to people allowed to see that child / parent.
/// Exactly one of <see cref="StudentId"/> / <see cref="ParentId"/> is set.
/// </summary>
public class ProfilePhoto
{
    public const int MaxBytes = 5 * 1024 * 1024;

    public int      Id          { get; set; }
    public int?     StudentId   { get; set; }
    public int?     ParentId    { get; set; }
    public string   ContentType { get; set; } = string.Empty;
    public byte[]   Data        { get; set; } = Array.Empty<byte>();
    public DateTime UpdatedAt   { get; set; } = DateTime.UtcNow;

    public Student? Student { get; set; }
    public Parent?  Parent  { get; set; }
}

/// <summary>
/// A class story: photos and videos a teacher (or the office) shares with every parent of a class,
/// or of the whole school (ClassId null, office only). Parents view and download them. Kept until deleted.
/// Created as a draft, media uploaded one file at a time, then published (parents get a push).
/// </summary>
public class Story
{
    public const int MaxMedia = 20;
    public const long MaxPhotoBytes = 10L * 1024 * 1024;
    public const long MaxVideoBytes = 100L * 1024 * 1024;

    public int       Id              { get; set; }
    /// <summary>Null = the whole school.</summary>
    public int?      ClassId         { get; set; }
    public string?   Caption         { get; set; }
    public int       CreatedByUserId { get; set; }
    public string    CreatedByName   { get; set; } = string.Empty;
    public DateTime  CreatedAt       { get; set; } = DateTime.UtcNow;
    /// <summary>Null while the teacher is still adding photos; parents see published stories only.</summary>
    public DateTime? PublishedAt     { get; set; }

    public SchoolClass? Class { get; set; }
    public List<StoryMedia> Media { get; set; } = new();
}

/// <summary>A photo or video of a story. The file lives on disk (media volume), not in the database.</summary>
public class StoryMedia
{
    public const string Photo = "Photo", Video = "Video";

    public int      Id          { get; set; }
    public int      StoryId     { get; set; }
    public string   Kind        { get; set; } = Photo;
    public string   FileName    { get; set; } = string.Empty;
    public string   ContentType { get; set; } = string.Empty;
    public long     SizeBytes   { get; set; }
    /// <summary>Path under the media root, e.g. "montessori/stories/12/3f2a….mp4".</summary>
    public string   StoragePath { get; set; } = string.Empty;
    public int      SortOrder   { get; set; }
    public DateTime CreatedAt   { get; set; } = DateTime.UtcNow;

    public Story Story { get; set; } = null!;
}
