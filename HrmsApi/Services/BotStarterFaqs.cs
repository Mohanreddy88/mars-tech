using HrmsApi.Models;

namespace HrmsApi.Services;

/// <summary>
/// Ready-made questions an admin can add with one click (Chatbot → "Add starter questions"),
/// then edit. Answers may use {company}, {phone} and {feeDueDay}; they're filled in when shown.
/// Parent questions are only added when the company has the school features on.
/// </summary>
public static class BotStarterFaqs
{
    public static IEnumerable<BotFaq> For(bool school)
    {
        var order = 0;
        BotFaq F(string audience, string category, string question, string answer, string keywords, string? action = null) => new()
        {
            Audience = audience, Category = category, Question = question, Answer = answer,
            Keywords = keywords, Action = action, SortOrder = order += 10
        };

        // ── Staff ──
        yield return F(BotFaq.ForEmployees, "Leave", "How do I apply for leave?",
            "Open My Leave and tap Apply. Choose the leave type and dates, add a reason and submit. For medical leave, attach your MC. You'll get a notification when it's approved or rejected.",
            "leave, cuti, apply leave, annual leave, medical leave, mc, sick, time off, day off", "apply-leave");
        yield return F(BotFaq.ForEmployees, "Leave", "How many leave days do I have left?",
            "My Leave shows your balance for each leave type: entitled, taken, pending and remaining days.",
            "leave balance, baki cuti, remaining leave, how many days, entitlement", "my-leave");
        yield return F(BotFaq.ForEmployees, "Leave", "Can I cancel a leave request?",
            "Yes. While a request is still pending, open My Leave and cancel it. If it was already approved, please contact HR.",
            "cancel leave, withdraw leave, batal cuti");
        yield return F(BotFaq.ForEmployees, "Payroll", "Where can I find my payslip?",
            "Open My Payslips to see every month's payslip and download it as a PDF.",
            "payslip, pay slip, slip gaji, salary slip, download payslip", "payslips");
        yield return F(BotFaq.ForEmployees, "Payroll", "When is salary paid?",
            "Salary is paid once the month's payroll is released by HR. If your salary is late, please contact HR at {phone}.",
            "salary date, pay day, payday, gaji, when paid, salary late, salary not received");
        yield return F(BotFaq.ForEmployees, "Payroll", "What are the EPF, SOCSO, EIS and PCB deductions?",
            "EPF (KWSP) is your retirement savings, SOCSO (PERKESO) and EIS cover work injuries and job loss, and PCB (MTD) is the monthly income tax deduction. Your payslip shows the amount of each one.",
            "epf, kwsp, socso, perkeso, eis, pcb, mtd, tax, deduction, potongan");
        yield return F(BotFaq.ForEmployees, "Attendance", "How do I check my attendance?",
            "Open My Attendance to see your days for each period and submit them for approval.",
            "attendance, kehadiran, check in, clock in, timesheet", "attendance");
        yield return F(BotFaq.ForEmployees, "My details", "How do I update my bank account, phone or address?",
            "Open My Profile to update your contact details. For bank account or IC changes, please contact HR.",
            "bank account, address, phone number, update profile, change details, alamat", "profile");

        // ── Everyone ──
        yield return F(BotFaq.ForAll, "Account", "How do I change my password?",
            "Open Change Password, enter your current password and the new one twice.",
            "change password, tukar kata laluan, new password", "change-password");
        yield return F(BotFaq.ForAll, "Account", "I forgot my password",
            "On the sign-in screen, tap \"Forgot password\" and enter your email. You'll get a link to set a new password.",
            "forgot password, reset password, lupa kata laluan, cannot login, can't sign in, locked out");
        yield return F(BotFaq.ForAll, "Contact", "How do I contact {company}?",
            "You can reach {company} at {phone}.",
            "contact, phone number, call, office, hr, talk to someone, hubungi");

        if (!school) yield break;

        // ── Parents ──
        yield return F(BotFaq.ForParents, "Fees", "How do I pay school fees?",
            "Open Fees to see this month's invoice and how to pay. After paying, tap \"I've paid\" and attach your receipt; the office confirms it and you'll get the official receipt.",
            "fee, fees, yuran, pay, payment, bayar, invoice, receipt, resit", "fees");
        yield return F(BotFaq.ForParents, "Fees", "When are fees due?",
            "Fees are due by day {feeDueDay} of each month.",
            "due date, fee due, deadline, tarikh akhir, late payment", "fees");
        yield return F(BotFaq.ForParents, "My child", "My child is sick or absent today",
            "Open your child's page and add an absence note, so the class teacher knows. You can also send the teacher a message.",
            "absent, sick, mc, fever, demam, sakit, not coming, cuti, tidak hadir", "new-message");
        yield return F(BotFaq.ForParents, "My child", "Someone else is picking up my child",
            "Open your child's page and add a pickup note with the person's name, so the school can hand your child over safely.",
            "pickup, pick up, collect, fetch, ambil, jemput, grandparent, driver");
        yield return F(BotFaq.ForParents, "Messages", "How do I message the teacher or the office?",
            "Open Messages and tap \"New conversation\". Choose your child, then the class teacher or the school office, and write a subject and your message.",
            "message, contact teacher, talk to teacher, office, guru, cikgu, chat", "new-message");
        yield return F(BotFaq.ForParents, "School", "Where can I see school announcements?",
            "Announcements from the school appear under Announcements, and you get a notification for each new one.",
            "announcement, notice, news, pengumuman, event, holiday", "announcements");
    }
}
