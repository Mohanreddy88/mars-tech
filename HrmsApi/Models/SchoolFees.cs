namespace HrmsApi.Models;

// ── School features, phase 4: monthly fees ──
// Fee items (the session fee for each session type, plus add-ons such as Mandarin), a monthly
// invoice per child (session fee + the child's add-ons − sibling discount), payments with
// receipts. Parents see their children's invoices once the office sends them.

/// <summary>Something the school charges for, e.g. "Full day tuition" or "Mandarin class".</summary>
public class FeeItem
{
    /// <summary>The monthly fee for a session type; every child pays the one matching their session.</summary>
    public const string Session = "Session";
    /// <summary>An optional extra a child is signed up for (Mandarin, Speech &amp; Drama…).</summary>
    public const string AddOn = "AddOn";
    public static readonly string[] Kinds = { Session, AddOn };

    public int      Id          { get; set; }
    public string   Name        { get; set; } = string.Empty;
    public string   Kind        { get; set; } = Session;
    /// <summary>For <see cref="Session"/> items: "Half day", "Full day" or "Daycare".</summary>
    public string?  SessionType { get; set; }
    public decimal  Amount      { get; set; }
    public int      SortOrder   { get; set; }
    public bool     IsActive    { get; set; } = true;
    public DateTime CreatedAt   { get; set; } = DateTime.UtcNow;
}

/// <summary>A child is signed up for an add-on (billed every month).</summary>
public class StudentFeeAddOn
{
    public int StudentId { get; set; }
    public int FeeItemId { get; set; }

    public Student Student { get; set; } = null!;
    public FeeItem FeeItem { get; set; } = null!;
}

/// <summary>One child's fees for one month.</summary>
public class FeeInvoice
{
    public const string Unpaid = "Unpaid", Partial = "Partial", Paid = "Paid", Void = "Void";

    public int       Id             { get; set; }
    /// <summary>"INV-202611-0001".</summary>
    public string    InvoiceNo      { get; set; } = string.Empty;
    public int       StudentId      { get; set; }
    public int       Year           { get; set; }
    public int       Month          { get; set; }
    public DateTime  IssueDate      { get; set; }
    public DateTime  DueDate        { get; set; }
    public decimal   Subtotal       { get; set; }
    public decimal   Discount       { get; set; }
    public decimal   Total          { get; set; }
    public decimal   AmountPaid     { get; set; }
    public string    Status         { get; set; } = Unpaid;
    public string?   Notes          { get; set; }
    /// <summary>When the parents were told about it; until then only the office sees it.</summary>
    public DateTime? SentAt         { get; set; }
    /// <summary>Last time it was sent (first send or "send again").</summary>
    public DateTime? LastSentAt     { get; set; }
    /// <summary>How many times it was sent to the parents.</summary>
    public int       SendCount      { get; set; }
    public string?   VoidReason     { get; set; }
    public string    CreatedByName  { get; set; } = string.Empty;
    public DateTime  CreatedAt      { get; set; } = DateTime.UtcNow;

    public decimal Balance => Status == Void ? 0 : Math.Max(0, Total - AmountPaid);

    public Student Student { get; set; } = null!;
    public List<FeeInvoiceLine> Lines { get; set; } = new();
    public List<FeePayment> Payments { get; set; } = new();
    public List<FeePaymentClaim> Claims { get; set; } = new();

    /// <summary>Totals and status from the lines and payments.</summary>
    public void Recalculate()
    {
        Subtotal   = Lines.Where(l => l.Amount > 0).Sum(l => l.Amount);
        Discount   = -Lines.Where(l => l.Amount < 0).Sum(l => l.Amount);
        Total      = Math.Max(0, Subtotal - Discount);
        AmountPaid = Payments.Sum(p => p.Amount);
        if (Status != Void)
            Status = AmountPaid <= 0 ? Unpaid : AmountPaid >= Total ? Paid : Partial;
    }
}

/// <summary>A line on an invoice; a discount is a negative amount.</summary>
public class FeeInvoiceLine
{
    public int     Id          { get; set; }
    public int     InvoiceId   { get; set; }
    public string  Description { get; set; } = string.Empty;
    public decimal Amount      { get; set; }
    public int?    FeeItemId   { get; set; }
    public int     SortOrder   { get; set; }

    public FeeInvoice Invoice { get; set; } = null!;
}

/// <summary>Money received for an invoice, with its receipt number.</summary>
public class FeePayment
{
    public static readonly string[] Methods = { "Cash", "Bank transfer", "Card", "DuitNow / QR", "Cheque", "Online" };

    public int      Id             { get; set; }
    public int      InvoiceId      { get; set; }
    /// <summary>"RCP-202611-0001".</summary>
    public string   ReceiptNo      { get; set; } = string.Empty;
    public decimal  Amount         { get; set; }
    public DateTime PaidOn         { get; set; }
    public string   Method         { get; set; } = "Cash";
    public string?  Reference      { get; set; }
    public string   RecordedByName { get; set; } = string.Empty;
    public DateTime CreatedAt      { get; set; } = DateTime.UtcNow;

    public FeeInvoice Invoice { get; set; } = null!;
}

/// <summary>
/// A parent says "I've paid" (bank transfer, DuitNow…), with the amount, date and usually a photo of
/// the transfer slip. The office checks the bank, then confirms it (which records the payment and
/// issues the receipt) or rejects it with a reason the parent sees.
/// </summary>
public class FeePaymentClaim
{
    public const string Pending = "Pending", Confirmed = "Confirmed", Rejected = "Rejected";

    public int       Id              { get; set; }
    public int       InvoiceId       { get; set; }
    public decimal   Amount          { get; set; }
    public DateTime  PaidOn          { get; set; }
    public string    Method          { get; set; } = "Bank transfer";
    public string?   Reference       { get; set; }
    public string?   Note            { get; set; }

    // The transfer slip (photo or PDF), in the company's database
    public string?   SlipName        { get; set; }
    public string?   SlipContentType { get; set; }
    public byte[]?   SlipData        { get; set; }

    public string    Status          { get; set; } = Pending;
    public string?   RejectReason    { get; set; }
    public int       CreatedByUserId { get; set; }
    public string    CreatedByName   { get; set; } = string.Empty;
    public DateTime  CreatedAt       { get; set; } = DateTime.UtcNow;
    public string?   ReviewedByName  { get; set; }
    public DateTime? ReviewedAt      { get; set; }
    /// <summary>The payment recorded when the office confirmed it.</summary>
    public int?      PaymentId       { get; set; }

    public FeeInvoice Invoice { get; set; } = null!;
}

// ── Price lists: one per academic year ("Price & Terms 2027"), changed by the office every year ──

/// <summary>
/// A year's prices and session times, e.g. "2027", used for invoices from <see cref="EffectiveFrom"/>
/// (until the next price list starts). Older price lists are kept, so past invoices keep their prices.
/// </summary>
public class FeePriceList
{
    public int       Id            { get; set; }
    /// <summary>"2027" or "2027 / 2028".</summary>
    public string    Name          { get; set; } = string.Empty;
    /// <summary>First day these prices apply (invoices for that month on).</summary>
    public DateTime  EffectiveFrom { get; set; }
    /// <summary>Months the "twice a year" charges are billed, e.g. "1,7" (January and July).</summary>
    public string    TwiceAYearMonths { get; set; } = "1,7";
    /// <summary>Terms printed under the price list ("Fees are collected monthly…").</summary>
    public string?   Terms         { get; set; }
    public DateTime  CreatedAt     { get; set; } = DateTime.UtcNow;
    public DateTime  UpdatedAt     { get; set; } = DateTime.UtcNow;

    public List<FeePriceSession> Sessions { get; set; } = new();
    public List<FeePriceCharge>  Charges  { get; set; } = new();
}

/// <summary>A session in a price list: its hours, meals and monthly fee (Half day 8:00–12:00, RM 930).</summary>
public class FeePriceSession
{
    public int      Id            { get; set; }
    public int      PriceListId   { get; set; }
    /// <summary>"Half day", "Full day" or "Daycare" (<see cref="Student.SessionTypes"/>).</summary>
    public string   SessionType   { get; set; } = Student.FullDay;
    /// <summary>The school offers this session this year (Daycare is optional).</summary>
    public bool     Offered       { get; set; } = true;
    /// <summary>"07:30"</summary>
    public string   Start         { get; set; } = "08:00";
    /// <summary>"18:30"</summary>
    public string   End           { get; set; } = "16:30";
    /// <summary>"breakfast, lunch & tea-break"</summary>
    public string?  MealsIncluded { get; set; }
    public decimal  MonthlyFee    { get; set; }

    public FeePriceList PriceList { get; set; } = null!;
}

/// <summary>
/// A charge besides the monthly fee: one-time at registration (registration, uniform, bedding),
/// twice a year (supplies), or a refundable deposit (billed in the child's second month).
/// </summary>
public class FeePriceCharge
{
    public const string OneTime = "OneTime", TwiceAYear = "TwiceAYear", Deposit = "Deposit";
    public static readonly string[] Kinds = { OneTime, TwiceAYear, Deposit };

    public int      Id          { get; set; }
    public int      PriceListId { get; set; }
    public string   Name        { get; set; } = string.Empty;
    public string   Kind        { get; set; } = OneTime;
    public decimal  Amount      { get; set; }
    /// <summary>Only for this session ("Bedding" — Full day); null = every child.</summary>
    public string?  SessionType { get; set; }
    public int      SortOrder   { get; set; }

    public FeePriceList PriceList { get; set; } = null!;
}

/// <summary>A refundable deposit the school holds for a child, until refunded or deducted from an invoice.</summary>
public class StudentDeposit
{
    public const string Held = "Held", Refunded = "Refunded", Deducted = "Deducted";

    public int       Id               { get; set; }
    public int       StudentId        { get; set; }
    public string    Description      { get; set; } = "Deposit";
    public decimal   Amount           { get; set; }
    /// <summary>The invoice it was billed on.</summary>
    public int?      InvoiceId        { get; set; }
    public string    Status           { get; set; } = Held;
    public DateTime  CreatedAt        { get; set; } = DateTime.UtcNow;
    public DateTime? SettledAt        { get; set; }
    public string?   SettledByName    { get; set; }
    /// <summary>Refunded: "Bank transfer 12 Dec"; deducted: the invoice it was taken off.</summary>
    public string?   Note             { get; set; }
    public int?      DeductedInvoiceId { get; set; }

    public Student Student { get; set; } = null!;
}
