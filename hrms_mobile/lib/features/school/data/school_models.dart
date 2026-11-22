import '../../../core/utils/formatters.dart';

// Models for the school features (classes, children, parents, announcements, messages,
// attendance, daily reports, fees). They mirror the HrmsApi school endpoints (camelCase JSON).

String? _s(dynamic v) => v is String && v.isNotEmpty ? v : null;
int _i(dynamic v) => (v as num?)?.toInt() ?? 0;
double _d(dynamic v) => (v as num?)?.toDouble() ?? 0;
List<T> _list<T>(dynamic v, T Function(Map<String, dynamic>) f) =>
    (v as List<dynamic>? ?? const []).map((e) => f(e as Map<String, dynamic>)).toList();

/// GET school/me — the signed-in user's place in the school features.
class SchoolMe {
  const SchoolMe({
    required this.enabled,
    required this.userId,
    required this.name,
    required this.isAdmin,
    required this.isTeacher,
    required this.isParent,
    required this.classes,
    required this.children,
    this.school = SchoolInfo.empty,
  });

  final SchoolInfo school;
  final bool enabled;
  final int userId;
  final String name;
  final bool isAdmin;
  final bool isTeacher;
  final bool isParent;
  final List<SchoolClassRef> classes;
  final List<ChildSummary> children;

  bool get isStaff => enabled && (isAdmin || isTeacher);

  factory SchoolMe.fromJson(Map<String, dynamic> j) => SchoolMe(
        enabled: j['enabled'] as bool? ?? false,
        userId: _i(j['userId']),
        name: j['name'] as String? ?? '',
        isAdmin: j['isAdmin'] as bool? ?? false,
        isTeacher: j['isTeacher'] as bool? ?? false,
        isParent: j['isParent'] as bool? ?? false,
        classes: _list(j['classes'], SchoolClassRef.fromJson),
        children: _list(j['children'], ChildSummary.fromJson),
        school: j['school'] is Map<String, dynamic> ? SchoolInfo.fromJson(j['school'] as Map<String, dynamic>) : SchoolInfo.empty,
      );

  static const off = SchoolMe(enabled: false, userId: 0, name: '', isAdmin: false, isTeacher: false,
      isParent: false, classes: [], children: []);
}

/// GET school/today — staff home counters: children looked after, checked in / absent today,
/// and (admins) parents' payment claims to confirm.
class StaffToday {
  const StaffToday({required this.children, required this.checkedIn, required this.absent, this.feeClaimsPending});
  final int children;
  final int checkedIn;
  final int absent;
  final int? feeClaimsPending;

  factory StaffToday.fromJson(Map<String, dynamic> j) => StaffToday(
        children: _i(j['children']),
        checkedIn: _i(j['checkedIn']),
        absent: _i(j['absent']),
        feeClaimsPending: (j['feeClaimsPending'] as num?)?.toInt(),
      );
}

/// The school's name and contact details (from Company Settings).
class SchoolInfo {
  const SchoolInfo({required this.name, this.logoUrl, this.phone, this.address, this.website});
  final String name;
  /// Server path of the logo ("/api/company-settings/logo?v=…"), or null.
  final String? logoUrl;
  final String? phone;
  final String? address;
  final String? website;

  static const empty = SchoolInfo(name: '');

  factory SchoolInfo.fromJson(Map<String, dynamic> j) => SchoolInfo(
        name: j['name'] as String? ?? '',
        logoUrl: _s(j['logoUrl']),
        phone: _s(j['phone']),
        address: _s(j['address']),
        website: _s(j['website']),
      );
}

class SchoolClassRef {
  const SchoolClassRef({required this.id, required this.name});
  final int id;
  final String name;
  factory SchoolClassRef.fromJson(Map<String, dynamic> j) =>
      SchoolClassRef(id: _i(j['id']), name: j['name'] as String? ?? '');
}

class ChildSummary {
  const ChildSummary({
    required this.id,
    required this.fullName,
    this.dateOfBirth,
    required this.sessionType,
    this.classId,
    this.className,
    this.classTeacherName,
  });

  final int id;
  final String fullName;
  final DateTime? dateOfBirth;
  final String sessionType;
  final int? classId;
  final String? className;
  final String? classTeacherName;

  factory ChildSummary.fromJson(Map<String, dynamic> j) => ChildSummary(
        id: _i(j['id']),
        fullName: j['fullName'] as String? ?? '',
        dateOfBirth: tryParseApiDate(j['dateOfBirth']),
        sessionType: j['sessionType'] as String? ?? '',
        classId: (j['classId'] as num?)?.toInt(),
        className: _s(j['className']),
        classTeacherName: _s(j['classTeacherName']),
      );
}

/// A child on a staff list (GET school/students): with medical notes and parents' phones.
class StudentInfo {
  const StudentInfo({
    required this.id,
    required this.fullName,
    this.className,
    required this.sessionType,
    this.dateOfBirth,
    this.medicalNotes,
    this.emergencyContactName,
    this.emergencyContactPhone,
    required this.parents,
  });

  final int id;
  final String fullName;
  final String? className;
  final String sessionType;
  final DateTime? dateOfBirth;
  final String? medicalNotes;
  final String? emergencyContactName;
  final String? emergencyContactPhone;
  final List<ParentContact> parents;

  factory StudentInfo.fromJson(Map<String, dynamic> j) => StudentInfo(
        id: _i(j['id']),
        fullName: j['fullName'] as String? ?? '',
        className: _s(j['className']),
        sessionType: j['sessionType'] as String? ?? '',
        dateOfBirth: tryParseApiDate(j['dateOfBirth']),
        medicalNotes: _s(j['medicalNotes']),
        emergencyContactName: _s(j['emergencyContactName']),
        emergencyContactPhone: _s(j['emergencyContactPhone']),
        parents: _list(j['parents'], ParentContact.fromJson),
      );
}

class ParentContact {
  const ParentContact({required this.fullName, required this.relationship, this.phone});
  final String fullName;
  final String relationship;
  final String? phone;
  factory ParentContact.fromJson(Map<String, dynamic> j) => ParentContact(
        fullName: j['fullName'] as String? ?? '',
        relationship: j['relationship'] as String? ?? '',
        phone: _s(j['phone']),
      );
  String get label => '$fullName ($relationship)';
}

// ── Announcements ──

class Announcement {
  const Announcement({
    required this.id,
    required this.title,
    required this.body,
    this.className,
    required this.createdByName,
    this.createdAt,
    this.attachmentName,
    this.attachmentType,
    required this.isRead,
    required this.canDelete,
    this.readCount,
    this.audienceCount,
  });

  final int id;
  final String title;
  final String body;
  final String? className;
  final String createdByName;
  final DateTime? createdAt;
  final String? attachmentName;
  final String? attachmentType;
  final bool isRead;
  final bool canDelete;
  final int? readCount;
  final int? audienceCount;

  factory Announcement.fromJson(Map<String, dynamic> j) {
    final a = j['attachment'] as Map<String, dynamic>?;
    return Announcement(
      id: _i(j['id']),
      title: j['title'] as String? ?? '',
      body: j['body'] as String? ?? '',
      className: _s(j['className']),
      createdByName: j['createdByName'] as String? ?? '',
      createdAt: tryParseApiDate(j['createdAt']),
      attachmentName: a?['name'] as String?,
      attachmentType: a?['contentType'] as String?,
      isRead: j['isRead'] as bool? ?? false,
      canDelete: j['canDelete'] as bool? ?? false,
      readCount: (j['readCount'] as num?)?.toInt(),
      audienceCount: (j['audienceCount'] as num?)?.toInt(),
    );
  }
}

// ── Messages ──

/// A conversation about one child with the class teacher or the office, with its own subject.
/// Staff close it when done ([isClosed]); a new message reopens it.
class ConversationSummary {
  const ConversationSummary({
    required this.id,
    required this.kind,
    required this.studentName,
    this.className,
    required this.title,
    required this.subject,
    required this.status,
    this.lastMessageAt,
    this.lastText,
    this.lastSender,
    this.lastMine = false,
    required this.unread,
  });

  final int id;
  final String kind; // Teacher | Office
  final String studentName;
  final String? className;
  /// Who the conversation is with: "Class teacher · Ms Tan" or "School office".
  final String title;
  final String subject;
  final String status; // Open | Closed
  bool get isClosed => status == 'Closed';
  final DateTime? lastMessageAt;
  final String? lastText;
  final String? lastSender;
  final bool lastMine;
  final int unread;

  factory ConversationSummary.fromJson(Map<String, dynamic> j) {
    final last = j['lastMessage'] as Map<String, dynamic>?;
    return ConversationSummary(
      id: _i(j['id']),
      kind: j['kind'] as String? ?? 'Teacher',
      studentName: j['studentName'] as String? ?? '',
      className: _s(j['className']),
      title: j['title'] as String? ?? '',
      subject: j['subject'] as String? ?? 'General',
      status: j['status'] as String? ?? 'Open',
      lastMessageAt: tryParseApiDate(j['lastMessageAt']),
      lastText: last?['text'] as String?,
      lastSender: last?['senderName'] as String?,
      lastMine: last?['mine'] as bool? ?? false,
      unread: _i(j['unread']),
    );
  }
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.senderUserId,
    required this.senderName,
    required this.senderRole,
    required this.body,
    required this.sentAt,
    this.attachmentName,
    this.attachmentType,
  });

  final int id;
  final int senderUserId;
  final String senderName;
  final String senderRole;
  final String body;
  final DateTime sentAt;
  final String? attachmentName;
  final String? attachmentType;

  bool get hasPhoto => attachmentType?.startsWith('image/') ?? false;

  factory ChatMessage.fromJson(Map<String, dynamic> j) {
    final a = j['attachment'] as Map<String, dynamic>?;
    return ChatMessage(
      id: _i(j['id']),
      senderUserId: _i(j['senderUserId']),
      senderName: j['senderName'] as String? ?? '',
      senderRole: j['senderRole'] as String? ?? '',
      body: j['body'] as String? ?? '',
      sentAt: tryParseApiDate(j['sentAt']) ?? DateTime.now(),
      attachmentName: a?['name'] as String?,
      attachmentType: a?['contentType'] as String?,
    );
  }
}

class MessagePage {
  const MessagePage({required this.title, required this.subtitle, required this.messages,
      required this.hasMore, required this.seenUpTo, this.status = 'Open', this.closedByName});
  /// The conversation's subject.
  final String title;
  /// With whom, about which child, and the child's parents.
  final String subtitle;
  final List<ChatMessage> messages;
  final bool hasMore;
  final int seenUpTo;
  final String status; // Open | Closed
  final String? closedByName;
  bool get isClosed => status == 'Closed';

  MessagePage copyWith({List<ChatMessage>? messages, bool? hasMore, String? status, String? closedByName}) => MessagePage(
        title: title,
        subtitle: subtitle,
        messages: messages ?? this.messages,
        hasMore: hasMore ?? this.hasMore,
        seenUpTo: seenUpTo,
        status: status ?? this.status,
        closedByName: status == 'Open' ? null : closedByName ?? this.closedByName,
      );

  factory MessagePage.fromJson(Map<String, dynamic> j) {
    final c = j['conversation'] as Map<String, dynamic>? ?? const {};
    final parents = _list(c['parents'], (p) => p['fullName'] as String? ?? '').where((s) => s.isNotEmpty);
    return MessagePage(
      title: c['subject'] as String? ?? c['title'] as String? ?? '',
      subtitle: [c['title'], c['studentName'], if (c['className'] != null) c['className']].whereType<String>().join(' · ') +
          (parents.isNotEmpty ? ' · ${parents.join(', ')}' : ''),
      messages: _list(j['messages'], ChatMessage.fromJson),
      hasMore: j['hasMore'] as bool? ?? false,
      seenUpTo: _i(j['seenUpTo']),
      status: c['status'] as String? ?? 'Open',
      closedByName: _s(c['closedByName']),
    );
  }
}

// ── The child's day ──

class AttendanceInfo {
  const AttendanceInfo({required this.status, this.checkIn, this.checkInBy, this.checkOut,
      this.checkOutBy, this.pickedUpBy, this.absenceReason});
  final String status; // Present | Absent
  final String? checkIn; // "08:05"
  final String? checkInBy;
  final String? checkOut;
  final String? checkOutBy;
  final String? pickedUpBy;
  final String? absenceReason;

  bool get absent => status == 'Absent';

  static AttendanceInfo? fromJson(dynamic v) {
    if (v is! Map<String, dynamic>) return null;
    return AttendanceInfo(
      status: v['status'] as String? ?? 'Present',
      checkIn: _s(v['checkIn']),
      checkInBy: _s(v['checkInBy']),
      checkOut: _s(v['checkOut']),
      checkOutBy: _s(v['checkOutBy']),
      pickedUpBy: _s(v['pickedUpBy']),
      absenceReason: _s(v['absenceReason']),
    );
  }
}

class ParentNote {
  const ParentNote({required this.id, required this.studentId, required this.kind, required this.fromDate,
      required this.toDate, this.pickupName, this.pickupPhone, this.pickupTime, this.message,
      required this.createdByName, this.seenByName, required this.cancelled});
  final int id;
  final int studentId;
  final String kind; // Absence | Pickup
  final String fromDate; // yyyy-MM-dd
  final String toDate;
  final String? pickupName;
  final String? pickupPhone;
  final String? pickupTime;
  final String? message;
  final String createdByName;
  final String? seenByName;
  final bool cancelled;

  bool get isAbsence => kind == 'Absence';

  factory ParentNote.fromJson(Map<String, dynamic> j) => ParentNote(
        id: _i(j['id']),
        studentId: _i(j['studentId']),
        kind: j['kind'] as String? ?? 'Absence',
        fromDate: j['fromDate'] as String? ?? '',
        toDate: j['toDate'] as String? ?? '',
        pickupName: _s(j['pickupName']),
        pickupPhone: _s(j['pickupPhone']),
        pickupTime: _s(j['pickupTime']),
        message: _s(j['message']),
        createdByName: j['createdByName'] as String? ?? '',
        seenByName: _s(j['seenByName']),
        cancelled: j['cancelled'] as bool? ?? false,
      );
}

class DailyReport {
  const DailyReport({this.id = 0, this.breakfast, this.lunch, this.snack, this.napFrom, this.napTo, this.toilet,
      this.mood, this.activities, this.teacherNote, this.publishedAt, this.updatedByName = '',
      this.photoIds = const []});
  final int id;
  final String? breakfast;
  final String? lunch;
  final String? snack;
  final String? napFrom;
  final String? napTo;
  final String? toilet;
  final String? mood;
  final String? activities;
  final String? teacherNote;
  final DateTime? publishedAt;
  final String updatedByName;
  final List<int> photoIds;

  bool get published => publishedAt != null;

  static DailyReport? fromJson(dynamic v) {
    if (v is! Map<String, dynamic>) return null;
    return DailyReport(
      id: _i(v['id']),
      breakfast: _s(v['breakfast']),
      lunch: _s(v['lunch']),
      snack: _s(v['snack']),
      napFrom: _s(v['napFrom']),
      napTo: _s(v['napTo']),
      toilet: _s(v['toilet']),
      mood: _s(v['mood']),
      activities: _s(v['activities']),
      teacherNote: _s(v['teacherNote']),
      publishedAt: tryParseApiDate(v['publishedAt']),
      updatedByName: v['updatedByName'] as String? ?? '',
      photoIds: _list(v['photos'], (p) => _i(p['id'])),
    );
  }

  Map<String, dynamic> toJson({bool publish = false}) => {
        'breakfast': breakfast, 'lunch': lunch, 'snack': snack, 'napFrom': napFrom, 'napTo': napTo,
        'toilet': toilet, 'mood': mood, 'activities': activities, 'teacherNote': teacherNote,
        'publish': publish,
      };
}

class ChildDay {
  const ChildDay({required this.childId, required this.childName, this.className, this.teacher,
      required this.date, required this.today, this.attendance, this.report, required this.notes});
  final int childId;
  final String childName;
  final String? className;
  final String? teacher;
  final String date;
  final String today;
  final AttendanceInfo? attendance;
  final DailyReport? report;
  final List<ParentNote> notes;

  factory ChildDay.fromJson(Map<String, dynamic> j) {
    final c = j['child'] as Map<String, dynamic>? ?? const {};
    return ChildDay(
      childId: _i(c['id']),
      childName: c['fullName'] as String? ?? '',
      className: _s(c['className']),
      teacher: _s(c['teacher']),
      date: j['date'] as String? ?? '',
      today: j['today'] as String? ?? '',
      attendance: AttendanceInfo.fromJson(j['attendance']),
      report: DailyReport.fromJson(j['report']),
      notes: _list(j['notes'], ParentNote.fromJson),
    );
  }
}

class AttendanceRow {
  const AttendanceRow({required this.studentId, required this.fullName, this.className, required this.sessionType,
      this.medicalNotes, required this.parents, this.attendance, required this.notes, this.reportPublished,
      this.reportPhotos = 0, this.reportMood});
  final int studentId;
  final String fullName;
  final String? className;
  final String sessionType;
  final String? medicalNotes;
  final List<ParentContact> parents;
  final AttendanceInfo? attendance;
  final List<ParentNote> notes;

  /// null = no report yet; false = draft; true = sent to parents.
  final bool? reportPublished;
  final int reportPhotos;
  final String? reportMood;

  bool get expectedAbsent => attendance == null && notes.any((n) => n.isAbsence);

  factory AttendanceRow.fromJson(Map<String, dynamic> j) {
    final r = j['report'] as Map<String, dynamic>?;
    return AttendanceRow(
      studentId: _i(j['studentId']),
      fullName: j['fullName'] as String? ?? '',
      className: _s(j['className']),
      sessionType: j['sessionType'] as String? ?? '',
      medicalNotes: _s(j['medicalNotes']),
      parents: _list(j['parents'], ParentContact.fromJson),
      attendance: AttendanceInfo.fromJson(j['attendance']),
      notes: _list(j['notes'], ParentNote.fromJson),
      reportPublished: r == null ? null : r['published'] as bool? ?? false,
      reportPhotos: _i(r?['photos']),
      reportMood: _s(r?['mood']),
    );
  }
}

class AttendanceDay {
  const AttendanceDay({required this.date, required this.today, required this.rows, required this.present,
      required this.absent, required this.goneHome, required this.notMarked, required this.reportsSent});
  final String date;
  final String today;
  final List<AttendanceRow> rows;
  final int present;
  final int absent;
  final int goneHome;
  final int notMarked;
  final int reportsSent;

  factory AttendanceDay.fromJson(Map<String, dynamic> j) {
    final s = j['summary'] as Map<String, dynamic>? ?? const {};
    return AttendanceDay(
      date: j['date'] as String? ?? '',
      today: j['today'] as String? ?? '',
      rows: _list(j['rows'], AttendanceRow.fromJson),
      present: _i(s['present']),
      absent: _i(s['absent']),
      goneHome: _i(s['checkedOut']),
      notMarked: _i(s['notMarked']),
      reportsSent: _i(s['reportsPublished']),
    );
  }
}

// ── Fees ──

class InvoiceLine {
  const InvoiceLine({required this.description, required this.amount});
  final String description;
  final double amount;
  factory InvoiceLine.fromJson(Map<String, dynamic> j) =>
      InvoiceLine(description: j['description'] as String? ?? '', amount: _d(j['amount']));
}

class FeePayment {
  const FeePayment({required this.id, required this.receiptNo, required this.amount, required this.paidOn,
      required this.method, this.reference});
  final int id;
  final String receiptNo;
  final double amount;
  final String paidOn;
  final String method;
  final String? reference;
  factory FeePayment.fromJson(Map<String, dynamic> j) => FeePayment(
        id: _i(j['id']),
        receiptNo: j['receiptNo'] as String? ?? '',
        amount: _d(j['amount']),
        paidOn: j['paidOn'] as String? ?? '',
        method: j['method'] as String? ?? '',
        reference: _s(j['reference']),
      );
}

/// A parent's "I've paid": the office confirms it (payment + receipt) or says why not.
class PaymentClaim {
  const PaymentClaim({required this.id, required this.invoiceId, required this.invoiceNo, required this.studentName,
      this.className, required this.amount, required this.paidOn, required this.method, this.reference, this.note,
      required this.hasSlip, this.slipName, required this.slipIsPdf, required this.status, this.rejectReason,
      required this.createdByName, required this.invoiceBalance});
  final int id;
  final int invoiceId;
  final String invoiceNo;
  final String studentName;
  final String? className;
  final double amount;
  final String paidOn; // yyyy-MM-dd
  final String method;
  final String? reference;
  final String? note;
  final bool hasSlip;
  final String? slipName;
  final bool slipIsPdf;
  final String status; // Pending | Confirmed | Rejected
  final String? rejectReason;
  final String createdByName;
  final double invoiceBalance;

  bool get pending => status == 'Pending';

  factory PaymentClaim.fromJson(Map<String, dynamic> j) => PaymentClaim(
        id: _i(j['id']),
        invoiceId: _i(j['invoiceId']),
        invoiceNo: j['invoiceNo'] as String? ?? '',
        studentName: j['studentName'] as String? ?? '',
        className: _s(j['className']),
        amount: _d(j['amount']),
        paidOn: (j['paidOn'] as String? ?? '').split('T').first,
        method: j['method'] as String? ?? '',
        reference: _s(j['reference']),
        note: _s(j['note']),
        hasSlip: j['hasSlip'] as bool? ?? false,
        slipName: _s(j['slipName']),
        slipIsPdf: j['slipIsPdf'] as bool? ?? false,
        status: j['status'] as String? ?? 'Pending',
        rejectReason: _s(j['rejectReason']),
        createdByName: j['createdByName'] as String? ?? '',
        invoiceBalance: _d(j['invoiceBalance']),
      );
}

class Invoice {
  const Invoice({required this.id, required this.invoiceNo, required this.studentName, this.className,
      required this.monthName, required this.dueDate, required this.total, required this.discount,
      required this.amountPaid, required this.balance, required this.status, required this.overdue,
      required this.sent, this.notes, this.parents = const [], this.lines = const [], this.payments = const [],
      this.claims = const [], this.pendingClaim = false});
  final int id;
  final String invoiceNo;
  final String studentName;
  final String? className;
  final String monthName;
  final String dueDate;
  final double total;
  final double discount;
  final double amountPaid;
  final double balance;
  final String status; // Unpaid | Partial | Paid | Void
  final bool overdue;
  final bool sent;
  final String? notes;
  final List<String> parents;
  final List<InvoiceLine> lines;
  final List<FeePayment> payments;
  final List<PaymentClaim> claims;

  /// A parent reported paying it; the office hasn't checked yet (month list).
  final bool pendingClaim;

  PaymentClaim? get waitingClaim => claims.where((c) => c.pending).firstOrNull;
  PaymentClaim? get rejectedClaim => claims.isNotEmpty && claims.first.status == 'Rejected' ? claims.first : null;

  String get statusLabel => overdue ? 'Overdue' : status == 'Partial' ? 'Part paid' : status;

  factory Invoice.fromJson(Map<String, dynamic> j) => Invoice(
        id: _i(j['id']),
        invoiceNo: j['invoiceNo'] as String? ?? '',
        studentName: j['studentName'] as String? ?? '',
        className: _s(j['className']),
        monthName: j['monthName'] as String? ?? '',
        dueDate: j['dueDate'] as String? ?? '',
        total: _d(j['total']),
        discount: _d(j['discount']),
        amountPaid: _d(j['amountPaid']),
        balance: _d(j['balance']),
        status: j['status'] as String? ?? 'Unpaid',
        overdue: j['overdue'] as bool? ?? false,
        sent: j['sentAt'] != null,
        notes: _s(j['notes']),
        parents: (j['parents'] as List<dynamic>? ?? const []).whereType<String>().toList(),
        lines: _list(j['lines'], InvoiceLine.fromJson),
        payments: _list(j['payments'], FeePayment.fromJson),
        claims: _list(j['claims'], PaymentClaim.fromJson),
        pendingClaim: j['pendingClaim'] as bool? ?? false,
      );
}

class MyFees {
  const MyFees({this.paymentInstructions, required this.outstanding, required this.invoices});
  final String? paymentInstructions;
  final double outstanding;
  final List<Invoice> invoices;
  factory MyFees.fromJson(Map<String, dynamic> j) => MyFees(
        paymentInstructions: _s(j['paymentInstructions']),
        outstanding: _d(j['outstanding']),
        invoices: _list(j['invoices'], Invoice.fromJson),
      );
}

class InvoiceMonth {
  const InvoiceMonth({required this.invoices, required this.billed, required this.collected,
      required this.outstanding, required this.overdue, required this.paid, required this.count, this.claimsPending = 0});
  final List<Invoice> invoices;
  final double billed;
  final double collected;
  final double outstanding;
  final int overdue;
  final int paid;
  final int count;
  final int claimsPending;
  factory InvoiceMonth.fromJson(Map<String, dynamic> j) {
    final s = j['summary'] as Map<String, dynamic>? ?? const {};
    return InvoiceMonth(
      invoices: _list(j['invoices'], (m) => Invoice.fromJson({...m, 'monthName': ''})),
      billed: _d(s['billed']),
      collected: _d(s['collected']),
      outstanding: _d(s['outstanding']),
      overdue: _i(s['overdue']),
      paid: _i(s['paid']),
      count: _i(s['count']),
      claimsPending: _i(s['claimsPending']),
    );
  }
}

// ── School calendar (Malaysia time, like the API) ──

/// "2026-11-21": today in the school's time zone (UTC+8).
String schoolToday() => _ymd(DateTime.now().toUtc().add(const Duration(hours: 8)));

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String addDays(String ymd, int days) => _ymd(DateTime.parse(ymd).add(Duration(days: days)));

DateTime ymdToDate(String ymd) => DateTime.parse(ymd);
String dateToYmd(DateTime d) => _ymd(d);

const mealAmounts = ['All', 'Most', 'Some', 'None'];
const moods = {'Happy': '😄', 'Calm': '🙂', 'Tired': '🥱', 'Upset': '😢', 'Unwell': '🤒'};
const paymentMethods = ['Cash', 'Bank transfer', 'Card', 'DuitNow / QR', 'Cheque', 'Online'];
