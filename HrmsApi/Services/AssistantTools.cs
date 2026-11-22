using System.Text.Json;
using HrmsApi.Data;
using HrmsApi.Models;
using Anthropic.Models.Beta.Messages;
using Microsoft.EntityFrameworkCore;

namespace HrmsApi.Services;

/// <summary>Who is asking the AI assistant, built from the database (never from the client).</summary>
public sealed record AssistantUser(
    int UserId, string Name, bool IsAdmin, bool IsParent, List<int> ChildIds,
    int? EmployeeId, List<int> TeacherClassIds, bool School, string Audience);

/// <summary>
/// The read-only look-ups the AI assistant may call ("tools"). Every one is limited to the
/// signed-in person: a parent's own children, an employee's own leave and payslips, a teacher's
/// own classes. Nothing here changes data. The set offered depends on the person's role.
/// </summary>
public sealed class AssistantTools
{
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);

    private readonly HrmsDbContext _db;
    private readonly ILeaveService _leave;
    private readonly CompanySettings _settings;
    private readonly AssistantUser _me;
    private readonly IReadOnlyList<(string Key, string Label)> _pages;

    /// <summary>The page the AI suggested opening (shown as a button under the answer).</summary>
    public string? SuggestedPage { get; private set; }

    /// <summary>A file the AI offered (shown as a download button): API path relative to /api, and its label.</summary>
    public (string Label, string Path)? Download { get; private set; }

    public AssistantTools(HrmsDbContext db, ILeaveService leave, CompanySettings settings, AssistantUser me,
        IReadOnlyList<(string Key, string Label)> pages)
    {
        _db = db; _leave = leave; _settings = settings; _me = me; _pages = pages;
    }

    private bool Parent => _me.IsParent && _me.School;
    private bool Employee => _me.EmployeeId != null && !_me.IsParent;
    private bool Staff => _me.School && (_me.IsAdmin || _me.TeacherClassIds.Count > 0);
    private bool Admin => _me.IsAdmin;
    private bool SchoolAdmin => _me.IsAdmin && _me.School;

    /// <summary>Files this user may be offered, by key (see offer_download).</summary>
    private IEnumerable<string> Reports()
    {
        if (SchoolAdmin) { yield return "unpaid-fees"; yield return "all-fees"; }
        if (Admin) { yield return "payroll"; yield return "employees"; yield return "attendance"; }
        if (Parent) yield return "invoice";
        if (Employee) yield return "payslip";
    }

    // ── Definitions ──

    public List<BetaToolUnion> Definitions()
    {
        var tools = new List<BetaToolUnion>
        {
            Tool("search_help_articles",
                "Search the company's own help articles (questions and answers written by the school or HR office) " +
                "for general questions: hours, policies, how to do something in the app, contact details.",
                Props(("query", Str("What to look for, in a few words"))), "query"),
            Tool("get_company_info",
                "The school's or company's name, phone, address, website and the monthly fee due day.",
                Props()),
        };
        if (_pages.Count > 0)
            tools.Add(Tool("suggest_page",
                "Show a button under your answer that opens this page of the app. Use it when the person " +
                "would naturally go there next (e.g. Fees after a fee question). At most once per answer.",
                Props(("page", Enum("Page to open", _pages.Select(p => p.Key)))), "page"));

        if (Parent)
        {
            tools.Add(Tool("list_my_children", "The signed-in parent's children: id, name, class and class teacher.", Props()));
            tools.Add(Tool("get_child_day",
                "One child's day at school: attendance (checked in/out times, who picked up, absent and why), " +
                "the parent's absence/pickup notes for that day, and the teacher's daily report (meals, nap, mood, activities, note).",
                Props(("child_id", Int("Child id from list_my_children")),
                      ("date", Str("Date as yyyy-MM-dd (Malaysia time). Leave out for today."))), "child_id"));
            tools.Add(Tool("get_my_fees",
                "The parent's fee invoices (sent, not cancelled), newest first, with total, paid, balance, status " +
                "and due date, plus the total outstanding and how to pay.", Props()));
            tools.Add(Tool("get_announcements", "Recent school announcements to this parent (newest first).",
                Props(("limit", Int("How many, 1-10 (default 5)")))));
        }
        if (Employee)
        {
            tools.Add(Tool("get_my_leave_balance", "The employee's leave entitlement, used and remaining days per leave type.",
                Props(("year", Int("Year, default this year")))));
            tools.Add(Tool("get_my_leave_requests", "The employee's recent and upcoming leave requests with status.", Props()));
            tools.Add(Tool("get_my_payslips", "The employee's latest payslips: month, gross, deductions, net pay.",
                Props(("limit", Int("How many, 1-6 (default 3)")))));
        }
        if (Employee || _me.IsAdmin)
            tools.Add(Tool("get_public_holidays", "Upcoming public holidays (next 6 months).", Props()));
        if (Staff)
        {
            tools.Add(Tool("get_attendance_today",
                _me.IsAdmin ? "Today's check-in status of every child in the school, grouped by class."
                            : "Today's check-in status of the children in the classes this teacher teaches.",
                Props()));
            tools.Add(Tool("get_parent_messages_waiting",
                "Parent conversations with messages this user hasn't read yet (subject, child, last message, how many unread)" +
                (_me.IsAdmin ? ": office conversations and the admin's own classes." : ": this teacher's class conversations."),
                Props()));
            tools.Add(Tool("get_children",
                (_me.IsAdmin ? "Children in the school" : "Children in this teacher's classes") +
                ": class, session, medical notes, emergency contact and parents (name, relationship, phone).",
                Props(("class_name", Str("Only this class (e.g. N2). Leave out for all.")),
                      ("name", Str("Only children whose name contains this.")))));
        }
        if (SchoolAdmin)
            tools.Add(Tool("get_unpaid_fees",
                "School fee invoices that still have a balance (sent, not cancelled), with totals, overdue ones and " +
                "parents' 'I've paid' claims waiting to be confirmed.",
                Props(("year", Int("Only this year")), ("month", Int("Only this month (1-12)")))));
        if (Admin)
        {
            tools.Add(Tool("get_pending_approvals",
                "Leave requests and attendance periods waiting for the admin's approval.", Props()));
            tools.Add(Tool("get_payroll_summary", "One month's payroll: payslips, total gross/net, count by status.",
                Props(("year", Int("Year, default this year")), ("month", Int("Month 1-12, default this month")))));
            tools.Add(Tool("get_staff_on_leave", "Employees on approved or pending leave on a day.",
                Props(("date", Str("yyyy-MM-dd, default today")))));
            tools.Add(Tool("get_overview",
                "Head counts: active employees per department" + (_me.School ? ", children per class, parents with a login." : "."),
                Props()));
        }
        var reports = Reports().ToList();
        if (reports.Count > 0)
            tools.Add(Tool("offer_download",
                "Show a download button under your answer for a report or document. Reports: " + string.Join(", ", reports) +
                ". unpaid-fees/all-fees: Excel of fee invoices (year, month optional). payroll: Excel for a month (year, month). " +
                "employees: Excel staff directory. attendance: Excel for a date range (start_date, end_date). " +
                "invoice: the parent's invoice PDF (invoice_no). payslip: the employee's payslip PDF (year, month; latest if left out). " +
                "Use it when the person asks for a report, a file, a download, a PDF or Excel.",
                Props(("report", Enum("Which report", reports)),
                      ("year", Int("Year")), ("month", Int("Month 1-12")),
                      ("start_date", Str("yyyy-MM-dd")), ("end_date", Str("yyyy-MM-dd")),
                      ("invoice_no", Str("Invoice number, e.g. INV-2026-11-0001"))), "report"));
        return tools;
    }

    // ── Execution ──

    /// <summary>Runs one tool call; returns JSON for the model. Unknown tools or bad input throw.</summary>
    public async Task<string> RunAsync(string name, IReadOnlyDictionary<string, JsonElement> input)
    {
        object result = name switch
        {
            "search_help_articles" => await SearchHelpAsync(GetString(input, "query") ?? ""),
            "get_company_info" => CompanyInfo(),
            "suggest_page" => SuggestPage(GetString(input, "page")),
            "list_my_children" when Parent => await ChildrenAsync(),
            "get_child_day" when Parent => await ChildDayAsync(GetInt(input, "child_id") ?? 0, GetString(input, "date")),
            "get_my_fees" when Parent => await FeesAsync(),
            "get_announcements" when Parent => await AnnouncementsAsync(Math.Clamp(GetInt(input, "limit") ?? 5, 1, 10)),
            "get_my_leave_balance" when Employee => await LeaveBalanceAsync(GetInt(input, "year") ?? SchoolClock.Today.Year),
            "get_my_leave_requests" when Employee => await LeaveRequestsAsync(),
            "get_my_payslips" when Employee => await PayslipsAsync(Math.Clamp(GetInt(input, "limit") ?? 3, 1, 6)),
            "get_public_holidays" when Employee || _me.IsAdmin => await HolidaysAsync(),
            "get_attendance_today" when Staff => await AttendanceTodayAsync(),
            "get_parent_messages_waiting" when Staff => await MessagesWaitingAsync(),
            "get_children" when Staff => await StaffChildrenAsync(GetString(input, "class_name"), GetString(input, "name")),
            "get_unpaid_fees" when SchoolAdmin => await UnpaidFeesAsync(GetInt(input, "year"), GetInt(input, "month")),
            "get_pending_approvals" when Admin => await PendingApprovalsAsync(),
            "get_payroll_summary" when Admin => await PayrollSummaryAsync(GetInt(input, "year") ?? SchoolClock.Today.Year,
                                                                         GetInt(input, "month") ?? SchoolClock.Today.Month),
            "get_staff_on_leave" when Admin => await StaffOnLeaveAsync(GetString(input, "date")),
            "get_overview" when Admin => await OverviewAsync(),
            "offer_download" => await OfferDownloadAsync(input),
            _ => throw new InvalidOperationException($"Tool '{name}' is not available to this user.")
        };
        return JsonSerializer.Serialize(result, Json);
    }

    // ── Staff and admin look-ups ──

    private async Task<object> MessagesWaitingAsync()
    {
        var q = _db.Conversations.AsNoTracking().Where(c => c.LastMessageAt != null);
        if (_me.IsAdmin)
            q = q.Where(c => c.Kind == Conversation.Office
                             || (c.Student.ClassId != null && _me.TeacherClassIds.Contains(c.Student.ClassId.Value)));
        else
            q = q.Where(c => c.Kind == Conversation.Teacher && c.Student.ClassId != null
                             && _me.TeacherClassIds.Contains(c.Student.ClassId.Value));
        var me = _me.UserId;
        var rows = await q
            .Select(c => new
            {
                c.Subject, c.Kind, c.Status, c.LastMessageAt, child = c.Student.FullName,
                unread = c.Messages.Count(m => m.SenderUserId != me
                    && m.Id > (_db.ConversationReads.Where(r => r.ConversationId == c.Id && r.UserId == me)
                        .Select(r => (int?)r.LastReadMessageId).FirstOrDefault() ?? 0)),
                last = c.Messages.OrderByDescending(m => m.Id).Select(m => new { m.SenderName, m.Body }).FirstOrDefault()
            })
            .Where(c => c.unread > 0)
            .OrderByDescending(c => c.LastMessageAt).Take(15).ToListAsync();
        return new
        {
            conversationsWithUnread = rows.Count,
            conversations = rows.Select(r => new
            {
                r.Subject, r.child, with = r.Kind == Conversation.Office ? "office" : "class teacher", r.Status, r.unread,
                lastFrom = r.last?.SenderName,
                lastMessage = r.last == null ? null : r.last.Body.Length > 160 ? r.last.Body[..160] + "…" : r.last.Body
            })
        };
    }

    private async Task<object> StaffChildrenAsync(string? className, string? name)
    {
        var q = _db.Students.AsNoTracking().Where(s => s.IsActive);
        if (!_me.IsAdmin) q = q.Where(s => s.ClassId != null && _me.TeacherClassIds.Contains(s.ClassId.Value));
        if (!string.IsNullOrWhiteSpace(className)) q = q.Where(s => s.Class != null && s.Class.Name.ToLower() == className.Trim().ToLower());
        if (!string.IsNullOrWhiteSpace(name)) q = q.Where(s => s.FullName.ToLower().Contains(name.Trim().ToLower()));
        return await q.OrderBy(s => s.Class != null ? s.Class.Name : "").ThenBy(s => s.FullName).Take(60)
            .Select(s => new
            {
                s.FullName, className = s.Class != null ? s.Class.Name : null, s.SessionType, s.MedicalNotes,
                s.EmergencyContactName, s.EmergencyContactPhone,
                parents = s.Parents.Where(p => p.Parent.IsActive)
                    .Select(p => new { p.Parent.FullName, p.Parent.Relationship, p.Parent.Phone, hasAppLogin = p.Parent.UserId != null })
            }).ToListAsync();
    }

    private async Task<object> UnpaidFeesAsync(int? year, int? month)
    {
        var q = _db.FeeInvoices.AsNoTracking()
            .Where(i => i.SentAt != null && i.Status != FeeInvoice.Void && i.Status != FeeInvoice.Paid);
        if (year != null) q = q.Where(i => i.Year == year);
        if (month != null) q = q.Where(i => i.Month == month);
        var rows = await q.OrderBy(i => i.DueDate).ThenBy(i => i.Student.FullName)
            .Select(i => new
            {
                i.InvoiceNo, child = i.Student.FullName, className = i.Student.Class != null ? i.Student.Class.Name : null,
                i.Year, i.Month, i.Total, i.AmountPaid, i.Status, i.DueDate,
                claimPending = i.Claims.Any(c => c.Status == FeePaymentClaim.Pending)
            }).ToListAsync();
        var today = SchoolClock.Today;
        var drafts = await _db.FeeInvoices.CountAsync(i => i.SentAt == null && i.Status != FeeInvoice.Void
                                                           && (year == null || i.Year == year) && (month == null || i.Month == month));
        return new
        {
            currency = "MYR",
            invoices = rows.Count,
            outstanding = rows.Sum(r => Math.Max(0, r.Total - r.AmountPaid)),
            overdue = rows.Count(r => r.DueDate.Date < today),
            paymentClaimsToConfirm = rows.Count(r => r.claimPending),
            draftInvoicesNotSent = drafts,
            list = rows.Take(40).Select(r => new
            {
                r.InvoiceNo, r.child, r.className, month = new DateTime(r.Year, r.Month, 1).ToString("MMM yyyy"),
                balance = Math.Max(0, r.Total - r.AmountPaid), r.Status, dueDate = r.DueDate.ToString("yyyy-MM-dd"),
                overdue = r.DueDate.Date < today, r.claimPending
            }),
            note = rows.Count > 40 ? $"Showing 40 of {rows.Count}; offer the unpaid-fees Excel for the full list." : null
        };
    }

    private async Task<object> PendingApprovalsAsync()
    {
        var leave = await _db.LeaveRequests.AsNoTracking().Where(r => r.Status == "Pending")
            .OrderBy(r => r.StartDate).Take(30)
            .Select(r => new { employee = r.Employee.Name, leaveType = r.LeaveType.Name, start = r.StartDate, end = r.EndDate, days = r.TotalDays, r.Reason })
            .ToListAsync();
        var periods = await _db.AttendancePeriods.AsNoTracking().Where(p => p.Status == "Submitted")
            .OrderBy(p => p.SubmittedAt).Take(30)
            .Select(p => new { employee = p.Employee.Name, from = p.StartDate, to = p.EndDate, p.SubmittedAt })
            .ToListAsync();
        return new { leaveRequests = leave, leaveCount = leave.Count, attendancePeriods = periods, attendanceCount = periods.Count };
    }

    private async Task<object> PayrollSummaryAsync(int year, int month)
    {
        var rows = await _db.Payrolls.AsNoTracking().Where(p => p.Year == year && p.Month == month)
            .Select(p => new { p.Status, p.GrossIncome, p.NetSalary }).ToListAsync();
        return new
        {
            month = new DateTime(year, Math.Clamp(month, 1, 12), 1).ToString("MMMM yyyy"),
            currency = "MYR",
            payslips = rows.Count,
            totalGross = rows.Sum(r => r.GrossIncome),
            totalNet = rows.Sum(r => r.NetSalary),
            byStatus = rows.GroupBy(r => r.Status).Select(g => new { status = g.Key, count = g.Count(), net = g.Sum(x => x.NetSalary) }),
            note = rows.Count == 0 ? "No payroll generated for this month." : null
        };
    }

    private async Task<object> StaffOnLeaveAsync(string? dateText)
    {
        var day = SchoolClock.Today;
        if (!string.IsNullOrWhiteSpace(dateText) && DateTime.TryParse(dateText, out var d)) day = d.Date;
        var rows = await _db.LeaveRequests.AsNoTracking()
            .Where(r => (r.Status == "Approved" || r.Status == "Pending") && r.StartDate.Date <= day && r.EndDate.Date >= day)
            .Select(r => new { employee = r.Employee.Name, leaveType = r.LeaveType.Name, r.Status, start = r.StartDate, end = r.EndDate })
            .ToListAsync();
        return new { date = day.ToString("yyyy-MM-dd"), count = rows.Count, onLeave = rows };
    }

    private async Task<object> OverviewAsync()
    {
        var employees = await _db.Employees.AsNoTracking().Where(e => e.IsActive)
            .GroupBy(e => e.Department != null ? e.Department.Name : "No department")
            .Select(g => new { department = g.Key, employees = g.Count() }).ToListAsync();
        object? school = null;
        if (_me.School)
        {
            var classes = await _db.Students.AsNoTracking().Where(s => s.IsActive)
                .GroupBy(s => s.Class != null ? s.Class.Name : "No class")
                .Select(g => new { className = g.Key, children = g.Count() }).ToListAsync();
            school = new
            {
                children = classes.Sum(c => c.children),
                byClass = classes,
                parents = await _db.Parents.CountAsync(p => p.IsActive),
                parentsWithAppLogin = await _db.Parents.CountAsync(p => p.IsActive && p.UserId != null)
            };
        }
        return new { activeEmployees = employees.Sum(e => e.employees), byDepartment = employees, school };
    }

    // ── Downloads ──

    private async Task<object> OfferDownloadAsync(IReadOnlyDictionary<string, JsonElement> input)
    {
        var report = GetString(input, "report");
        if (report == null || !Reports().Contains(report)) return new { ok = false, note = "That report isn't available to this user." };
        var year = GetInt(input, "year");
        var month = GetInt(input, "month");
        if (month is < 1 or > 12) month = null;

        (string Label, string Path)? file = null;
        switch (report)
        {
            case "unpaid-fees":
            case "all-fees":
            {
                var period = month != null && year != null ? $" ({new DateTime(year.Value, month.Value, 1):MMM yyyy})" : year != null ? $" ({year})" : "";
                var qs = $"unpaidOnly={(report == "unpaid-fees" ? "true" : "false")}"
                         + (year != null ? $"&year={year}" : "") + (month != null ? $"&month={month}" : "");
                file = ($"{(report == "unpaid-fees" ? "Unpaid fees" : "Fee invoices")}{period} (Excel)", $"school/fees/export?{qs}");
                break;
            }
            case "payroll":
            {
                var y = year ?? SchoolClock.Today.Year;
                var m = month ?? SchoolClock.Today.Month;
                file = ($"Payroll {new DateTime(y, m, 1):MMM yyyy} (Excel)", $"reports/export/payroll-excel?year={y}&month={m}");
                break;
            }
            case "employees":
                file = ("Employee directory (Excel)", "reports/export/employees-excel");
                break;
            case "attendance":
            {
                var to = DateTime.TryParse(GetString(input, "end_date"), out var e) ? e.Date : SchoolClock.Today;
                var from = DateTime.TryParse(GetString(input, "start_date"), out var s) ? s.Date : new DateTime(to.Year, to.Month, 1);
                file = ($"Attendance {from:d MMM} – {to:d MMM yyyy} (Excel)",
                        $"reports/export/attendance-excel?startDate={from:yyyy-MM-dd}&endDate={to:yyyy-MM-dd}");
                break;
            }
            case "invoice":
            {
                var no = GetString(input, "invoice_no")?.Trim();
                var inv = await _db.FeeInvoices.AsNoTracking()
                    .Where(i => _me.ChildIds.Contains(i.StudentId) && i.SentAt != null && i.Status != FeeInvoice.Void
                                && (no == null || i.InvoiceNo == no))
                    .OrderByDescending(i => i.Year).ThenByDescending(i => i.Month)
                    .Select(i => new { i.Id, i.InvoiceNo }).FirstOrDefaultAsync();
                if (inv == null) return new { ok = false, note = "No such invoice for this parent." };
                file = ($"Invoice {inv.InvoiceNo} (PDF)", $"school/fees/invoices/{inv.Id}/pdf");
                break;
            }
            case "payslip":
            {
                var id = _me.EmployeeId!.Value;
                var p = await _db.Payrolls.AsNoTracking()
                    .Where(x => x.EmployeeId == id && (year == null || x.Year == year) && (month == null || x.Month == month))
                    .OrderByDescending(x => x.Year).ThenByDescending(x => x.Month)
                    .Select(x => new { x.Id, x.Year, x.Month }).FirstOrDefaultAsync();
                if (p == null) return new { ok = false, note = "No payslip found for that month." };
                file = ($"Payslip {new DateTime(p.Year, p.Month, 1):MMMM yyyy} (PDF)", $"selfservice/my-payslips/{p.Id}/download");
                break;
            }
        }
        Download = file;
        return new { ok = file != null, label = file?.Label };
    }

    private async Task<object> SearchHelpAsync(string query)
    {
        var faqs = await _db.BotFaqs.AsNoTracking().Where(f => f.IsActive).ToListAsync();
        faqs = faqs.Where(f => (_me.School || f.Audience != BotFaq.ForParents)
                               && (_me.IsAdmin || f.Audience == BotFaq.ForAll || f.Audience == _me.Audience)).ToList();
        var top = BotMatcher.Rank(faqs, query).Take(4).ToList();
        if (top.Count == 0) return new { results = Array.Empty<object>(), note = "No matching help article." };
        return new
        {
            results = top.Select(t => new { question = Fill(t.faq.Question), answer = Fill(t.faq.Answer), page = t.faq.Action })
        };
    }

    private object CompanyInfo() => new
    {
        name = _settings.NameForDisplay,
        phone = _settings.Phone,
        address = _settings.Address,
        website = _settings.Website,
        feeDueDayOfMonth = _me.School ? _settings.FeeDueDay : (int?)null
    };

    private object SuggestPage(string? page)
    {
        if (page == null || !_pages.Any(p => p.Key == page)) return new { ok = false, note = "Unknown page." };
        SuggestedPage = page;
        return new { ok = true };
    }

    private async Task<object> ChildrenAsync() =>
        await _db.Students.AsNoTracking().Where(s => _me.ChildIds.Contains(s.Id))
            .Select(s => new
            {
                id = s.Id, name = s.FullName, className = s.Class != null ? s.Class.Name : null,
                classTeacher = s.Class != null && s.Class.ClassTeacher != null ? s.Class.ClassTeacher.Name : null,
                s.SessionType
            }).ToListAsync();

    private async Task<object> ChildDayAsync(int childId, string? dateText)
    {
        if (!_me.ChildIds.Contains(childId)) return new { error = "That child is not linked to this parent." };
        var date = SchoolClock.Today;
        if (!string.IsNullOrWhiteSpace(dateText) && DateTime.TryParse(dateText, out var d)) date = d.Date;

        var name = await _db.Students.Where(s => s.Id == childId).Select(s => s.FullName).FirstAsync();
        var att = await _db.StudentAttendance.AsNoTracking().FirstOrDefaultAsync(a => a.StudentId == childId && a.Date == date);
        var notes = await _db.ParentNotes.AsNoTracking()
            .Where(n => n.StudentId == childId && n.FromDate <= date && n.ToDate >= date)
            .Select(n => new { n.Kind, n.Message, n.PickupName, n.PickupTime }).ToListAsync();
        var report = await _db.DailyReports.AsNoTracking().FirstOrDefaultAsync(r => r.StudentId == childId && r.Date == date);

        return new
        {
            child = name,
            date = date.ToString("yyyy-MM-dd"),
            isToday = date == SchoolClock.Today,
            attendance = att == null ? null : new
            {
                att.Status,
                checkedIn = att.CheckInAt == null ? null : SchoolClock.LocalTime(att.CheckInAt.Value),
                checkedInBy = att.CheckInBy,
                checkedOut = att.CheckOutAt == null ? null : SchoolClock.LocalTime(att.CheckOutAt.Value),
                pickedUpBy = att.PickedUpBy,
                att.AbsenceReason
            },
            attendanceNote = att == null ? "Not checked in (yet) on this day." : null,
            parentNotes = notes,
            dailyReport = report == null ? null : new
            {
                report.Breakfast, report.Lunch, report.Snack, report.NapFrom, report.NapTo,
                report.Toilet, report.Mood, report.Activities, report.TeacherNote
            }
        };
    }

    private async Task<object> FeesAsync()
    {
        var invoices = await _db.FeeInvoices.AsNoTracking()
            .Where(i => _me.ChildIds.Contains(i.StudentId) && i.SentAt != null && i.Status != FeeInvoice.Void)
            .OrderByDescending(i => i.Year).ThenByDescending(i => i.Month)
            .Take(12)
            .Select(i => new { i.InvoiceNo, child = i.Student.FullName, i.Year, i.Month, i.Total, i.AmountPaid, i.Status, i.DueDate })
            .ToListAsync();
        return new
        {
            currency = "MYR",
            outstanding = invoices.Sum(i => i.Status == FeeInvoice.Void ? 0 : Math.Max(0, i.Total - i.AmountPaid)),
            invoices = invoices.Select(i => new
            {
                i.InvoiceNo, i.child, month = new DateTime(i.Year, i.Month, 1).ToString("MMMM yyyy"),
                i.Total, paid = i.AmountPaid, balance = Math.Max(0, i.Total - i.AmountPaid), i.Status,
                dueDate = i.DueDate.ToString("yyyy-MM-dd"),
                overdue = i.Status != FeeInvoice.Paid && i.DueDate.Date < SchoolClock.Today
            }),
            howToPay = _settings.FeePaymentInstructions
        };
    }

    private async Task<object> AnnouncementsAsync(int limit)
    {
        var classIds = await _db.Students.Where(s => _me.ChildIds.Contains(s.Id) && s.ClassId != null)
            .Select(s => s.ClassId!.Value).ToListAsync();
        return await _db.Announcements.AsNoTracking()
            .Where(a => a.ClassId == null || classIds.Contains(a.ClassId.Value))
            .OrderByDescending(a => a.CreatedAt).Take(limit)
            .Select(a => new { a.Title, a.Body, date = a.CreatedAt, from = a.CreatedByName, forClass = a.Class != null ? a.Class.Name : null })
            .ToListAsync();
    }

    private async Task<object> LeaveBalanceAsync(int year)
    {
        var id = _me.EmployeeId!.Value;
        await _leave.InitializeLeaveBalancesAsync(id, year);
        return await _db.EmployeeLeaveBalances.AsNoTracking()
            .Where(b => b.EmployeeId == id && b.Year == year)
            .Select(b => new { leaveType = b.LeaveType.Name, b.Year, entitled = b.TotalDays, used = b.UsedDays, remaining = b.BalanceDays, carriedForward = b.CarryForwardDays })
            .ToListAsync();
    }

    private async Task<object> LeaveRequestsAsync()
    {
        var id = _me.EmployeeId!.Value;
        var from = SchoolClock.Today.AddMonths(-3);
        return await _db.LeaveRequests.AsNoTracking()
            .Where(r => r.EmployeeId == id && r.EndDate >= from)
            .OrderByDescending(r => r.StartDate).Take(10)
            .Select(r => new
            {
                leaveType = r.LeaveType.Name, start = r.StartDate, end = r.EndDate, days = r.TotalDays,
                r.Status, r.Reason, remarks = r.ApprovalRemarks
            }).ToListAsync();
    }

    private async Task<object> PayslipsAsync(int limit)
    {
        var id = _me.EmployeeId!.Value;
        var rows = await _db.Payrolls.AsNoTracking()
            .Where(p => p.EmployeeId == id)
            .OrderByDescending(p => p.Year).ThenByDescending(p => p.Month).Take(limit)
            .Select(p => new { p.Year, p.Month, p.GrossIncome, p.BasicSalary, p.Allowances, p.Deductions, p.EpfAmount, p.SocsoAmount, p.EisAmount, p.TaxAmount, p.NetSalary })
            .ToListAsync();
        return new
        {
            currency = "MYR",
            payslips = rows.Select(p => new
            {
                month = new DateTime(p.Year, p.Month, 1).ToString("MMMM yyyy"),
                p.GrossIncome, p.BasicSalary, p.Allowances, p.Deductions,
                epf = p.EpfAmount, socso = p.SocsoAmount, eis = p.EisAmount, pcbTax = p.TaxAmount, netPay = p.NetSalary
            })
        };
    }

    private async Task<object> HolidaysAsync()
    {
        var today = SchoolClock.Today;
        var until = today.AddMonths(6);
        return await _db.PublicHolidays.AsNoTracking()
            .Where(h => h.Date >= today && h.Date <= until)
            .OrderBy(h => h.Date)
            .Select(h => new { h.Name, date = h.Date, h.IsNational, h.State })
            .ToListAsync();
    }

    private async Task<object> AttendanceTodayAsync()
    {
        var today = SchoolClock.Today;
        var children = _db.Students.AsNoTracking().Where(s => s.IsActive);
        if (!_me.IsAdmin) children = children.Where(s => s.ClassId != null && _me.TeacherClassIds.Contains(s.ClassId.Value));
        var rows = await children
            .Select(s => new
            {
                s.FullName,
                className = s.Class != null ? s.Class.Name : "No class",
                att = _db.StudentAttendance.Where(a => a.StudentId == s.Id && a.Date == today)
                    .Select(a => new { a.Status, a.CheckInAt, a.CheckOutAt, a.AbsenceReason }).FirstOrDefault()
            }).ToListAsync();
        return rows.GroupBy(r => r.className).OrderBy(g => g.Key).Select(g => new
        {
            className = g.Key,
            total = g.Count(),
            checkedIn = g.Count(r => r.att != null && r.att.Status == StudentAttendance.Present && r.att.CheckInAt != null),
            absent = g.Where(r => r.att != null && r.att.Status == StudentAttendance.Absent)
                      .Select(r => new { r.FullName, reason = r.att!.AbsenceReason }),
            notCheckedIn = g.Where(r => r.att == null).Select(r => r.FullName),
            wentHome = g.Count(r => r.att?.CheckOutAt != null)
        });
    }

    // ── helpers ──

    private string Fill(string text) => text
        .Replace("{company}", _settings.NameForDisplay, StringComparison.OrdinalIgnoreCase)
        .Replace("{phone}", string.IsNullOrWhiteSpace(_settings.Phone) ? "the office" : _settings.Phone, StringComparison.OrdinalIgnoreCase)
        .Replace("{feeDueDay}", _settings.FeeDueDay.ToString(), StringComparison.OrdinalIgnoreCase);

    private static string? GetString(IReadOnlyDictionary<string, JsonElement> input, string key) =>
        input.TryGetValue(key, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() : null;

    private static int? GetInt(IReadOnlyDictionary<string, JsonElement> input, string key)
    {
        if (!input.TryGetValue(key, out var v)) return null;
        if (v.ValueKind == JsonValueKind.Number && v.TryGetInt32(out var i)) return i;
        if (v.ValueKind == JsonValueKind.String && int.TryParse(v.GetString(), out var s)) return s;
        return null;
    }

    private static BetaTool Tool(string name, string description, Dictionary<string, JsonElement> props, params string[] required) => new()
    {
        Name = name,
        Description = description,
        InputSchema = new() { Properties = props, Required = required },
    };

    private static Dictionary<string, JsonElement> Props(params (string name, JsonElement schema)[] props) =>
        props.ToDictionary(p => p.name, p => p.schema);

    private static JsonElement Str(string description) => JsonSerializer.SerializeToElement(new { type = "string", description });
    private static JsonElement Int(string description) => JsonSerializer.SerializeToElement(new { type = "integer", description });
    private static JsonElement Enum(string description, IEnumerable<string> values) =>
        JsonSerializer.SerializeToElement(new { type = "string", description, @enum = values.ToArray() });
}
