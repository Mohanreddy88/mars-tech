namespace HrmsApi.Models;

// ── School features (per company, off by default: CompanySettings.SchoolFeaturesEnabled) ──
// Classes, children, parents (with their own "Parent" logins), announcements and
// parent ↔ teacher / office messages. Teachers are ordinary employees; an employee is a
// class teacher when a class names them (SchoolClass.ClassTeacherId).

/// <summary>A class, e.g. "N2" or "K1 Sunflower", with its class teacher.</summary>
public class SchoolClass
{
    public int      Id             { get; set; }
    public string   Name           { get; set; } = string.Empty;
    public string?  Description    { get; set; }
    /// <summary>Employee who teaches the class; sees its children and answers its parents' messages.</summary>
    public int?     ClassTeacherId { get; set; }
    public int      SortOrder      { get; set; }
    public bool     IsActive       { get; set; } = true;
    public DateTime CreatedAt      { get; set; } = DateTime.UtcNow;

    public Employee? ClassTeacher { get; set; }
    public List<Student> Students { get; set; } = new();
}

/// <summary>A child at the school.</summary>
public class Student
{
    public const string HalfDay = "Half day", FullDay = "Full day", Daycare = "Daycare";
    public static readonly string[] SessionTypes = { HalfDay, FullDay, Daycare };

    public int       Id                    { get; set; }
    public string    FullName              { get; set; } = string.Empty;
    public string?   AdmissionNo           { get; set; }
    public DateTime? DateOfBirth           { get; set; }
    public string?   Gender                { get; set; }
    public int?      ClassId               { get; set; }
    public string    SessionType           { get; set; } = FullDay;
    public DateTime? JoinedOn              { get; set; }
    /// <summary>Allergies, medication, conditions the teachers must know about.</summary>
    public string?   MedicalNotes          { get; set; }
    public string?   EmergencyContactName  { get; set; }
    public string?   EmergencyContactPhone { get; set; }
    public string?   Notes                 { get; set; }
    public bool      IsActive              { get; set; } = true;
    public DateTime  CreatedAt             { get; set; } = DateTime.UtcNow;
    /// <summary>
    /// The office confirmed there is no mother / father to record (single parent), so the missing
    /// parent is not a mistake. Cleared when a mother / father is linked.
    /// </summary>
    public bool      NoMotherOnRecord      { get; set; }
    public bool      NoFatherOnRecord      { get; set; }

    public SchoolClass? Class { get; set; }
    public List<StudentParent> Parents { get; set; } = new();
}

/// <summary>A parent or guardian. <see cref="UserId"/> is their login (role "Parent"), if they have one.</summary>
public class Parent
{
    public const string Guardian = "Guardian";
    public static readonly string[] Relationships = { "Mother", "Father", Guardian };

    public int      Id           { get; set; }
    public string   FullName     { get; set; } = string.Empty;
    public string?  Email        { get; set; }
    public string?  Phone        { get; set; }
    public string   Relationship { get; set; } = "Mother";
    public int?     UserId       { get; set; }
    public bool     IsActive     { get; set; } = true;
    public DateTime CreatedAt    { get; set; } = DateTime.UtcNow;

    public User? User { get; set; }
    public List<StudentParent> Children { get; set; } = new();
}

/// <summary>Which parents belong to which children (siblings share parents).</summary>
public class StudentParent
{
    public int StudentId { get; set; }
    public int ParentId  { get; set; }

    public Student Student { get; set; } = null!;
    public Parent  Parent  { get; set; } = null!;
}

/// <summary>A notice from the school to all parents, or to one class's parents (ClassId).</summary>
public class Announcement
{
    public int      Id              { get; set; }
    public string   Title           { get; set; } = string.Empty;
    public string   Body            { get; set; } = string.Empty;
    /// <summary>Null = every parent in the school.</summary>
    public int?     ClassId         { get; set; }
    public int      CreatedByUserId { get; set; }
    public string   CreatedByName   { get; set; } = string.Empty;
    public DateTime CreatedAt       { get; set; } = DateTime.UtcNow;

    // Optional photo or PDF, stored in the company's database (never in the public uploads folder)
    public string?  AttachmentName        { get; set; }
    public string?  AttachmentContentType { get; set; }
    public int?     AttachmentSize        { get; set; }
    public byte[]?  AttachmentData        { get; set; }

    public SchoolClass? Class { get; set; }
}

/// <summary>A parent login has opened an announcement.</summary>
public class AnnouncementRead
{
    public int      AnnouncementId { get; set; }
    public int      UserId         { get; set; }
    public DateTime ReadAt         { get; set; } = DateTime.UtcNow;

    public Announcement Announcement { get; set; } = null!;
}

/// <summary>
/// A conversation about one child, between that child's parents and either the class
/// teacher (<see cref="Teacher"/>) or the school office (<see cref="Office"/>). A child can have
/// many conversations, each with its own subject; parents start them ("Sick leave tomorrow"),
/// staff close them when done, and a new message reopens a closed one.
/// Admins can read every conversation; a class teacher reads the "Teacher" ones of their classes.
/// </summary>
public class Conversation
{
    public const string Teacher = "Teacher", Office = "Office";
    public static readonly string[] Kinds = { Teacher, Office };
    public const string Open = "Open", Closed = "Closed";
    public const string DefaultSubject = "General";
    public const int MaxSubjectLength = 150;

    public int       Id            { get; set; }
    public int       StudentId     { get; set; }
    public string    Kind          { get; set; } = Teacher;
    public string    Subject       { get; set; } = DefaultSubject;
    /// <summary><see cref="Open"/> or <see cref="Closed"/>.</summary>
    public string    Status        { get; set; } = Open;
    /// <summary>Who started it (null for threads from before subjects existed).</summary>
    public int?      CreatedByUserId { get; set; }
    public DateTime? ClosedAt      { get; set; }
    public string?   ClosedByName  { get; set; }
    public DateTime  CreatedAt     { get; set; } = DateTime.UtcNow;
    public DateTime? LastMessageAt { get; set; }

    public Student Student { get; set; } = null!;
    public List<ChatMessage> Messages { get; set; } = new();
}

public class ChatMessage
{
    public const int MaxBodyLength = 4000;
    public const int MaxAttachmentBytes = 5 * 1024 * 1024;

    public int      Id             { get; set; }
    public int      ConversationId { get; set; }
    public int      SenderUserId   { get; set; }
    public string   SenderName     { get; set; } = string.Empty;
    /// <summary>"Parent", "Teacher" or "Office" (an admin).</summary>
    public string   SenderRole     { get; set; } = string.Empty;
    public string   Body           { get; set; } = string.Empty;
    public DateTime SentAt         { get; set; } = DateTime.UtcNow;

    public Conversation Conversation { get; set; } = null!;
    public ChatAttachment? Attachment { get; set; }
}

/// <summary>A photo or PDF sent with a message (in the company's database, like leave documents).</summary>
public class ChatAttachment
{
    public int    Id          { get; set; }
    public int    MessageId   { get; set; }
    public string FileName    { get; set; } = string.Empty;
    public string ContentType { get; set; } = string.Empty;
    public int    SizeBytes   { get; set; }
    public byte[] Data        { get; set; } = Array.Empty<byte>();

    public ChatMessage Message { get; set; } = null!;
}

/// <summary>How far a login has read a thread: unread counts and "Seen" ticks.</summary>
public class ConversationRead
{
    public int      ConversationId    { get; set; }
    public int      UserId            { get; set; }
    public int      LastReadMessageId { get; set; }
    public DateTime ReadAt            { get; set; } = DateTime.UtcNow;

    public Conversation Conversation { get; set; } = null!;
}
