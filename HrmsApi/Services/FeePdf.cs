using System.Globalization;
using HrmsApi.Models;
using QuestPDF.Fluent;
using QuestPDF.Helpers;
using QuestPDF.Infrastructure;

namespace HrmsApi.Services;

/// <summary>School fee invoice and receipt PDFs (A4, the company's logo, name and colour).</summary>
public static class FeePdf
{
    private static readonly CultureInfo Inv = CultureInfo.InvariantCulture;

    static FeePdf() => QuestPDF.Settings.License = LicenseType.Community;

    private static string Rm(decimal v) => (v < 0 ? "- " : "") + "RM " + Math.Abs(v).ToString("#,##0.00", Inv);

    public static byte[] Invoice(CompanySettings company, FeeInvoice inv, IReadOnlyList<string> parents)
    {
        var month = new DateTime(inv.Year, inv.Month, 1).ToString("MMMM yyyy", Inv);
        return Document.Create(doc => doc.Page(page =>
        {
            Setup(page);
            page.Content().Column(col =>
            {
                Header(col, company, inv.Status == FeeInvoice.Void ? "INVOICE (VOID)" : "INVOICE");

                col.Item().PaddingTop(14).Row(row =>
                {
                    row.RelativeItem().Column(c =>
                    {
                        c.Item().Text("Bill to").FontSize(8).FontColor(Colors.Grey.Darken1);
                        c.Item().Text(parents.Count > 0 ? string.Join(" / ", parents) : "Parent / guardian").Bold();
                        c.Item().Text($"For: {inv.Student.FullName}" + (inv.Student.Class != null ? $" ({inv.Student.Class.Name})" : ""));
                    });
                    row.ConstantItem(200).Column(c =>
                    {
                        KeyValue(c, "Invoice no.", inv.InvoiceNo);
                        KeyValue(c, "Fees for", month);
                        KeyValue(c, "Invoice date", inv.IssueDate.ToString("d MMM yyyy", Inv));
                        KeyValue(c, "Due date", inv.DueDate.ToString("d MMM yyyy", Inv));
                    });
                });

                col.Item().PaddingTop(16).Table(t =>
                {
                    t.ColumnsDefinition(c => { c.ConstantColumn(28); c.RelativeColumn(); c.ConstantColumn(110); });
                    t.Header(h =>
                    {
                        HeadCell(h.Cell(), "#", company);
                        HeadCell(h.Cell(), "Description", company);
                        HeadCell(h.Cell(), "Amount", company, right: true);
                    });
                    var n = 1;
                    foreach (var l in inv.Lines.OrderBy(l => l.SortOrder))
                    {
                        BodyCell(t.Cell()).Text((n++).ToString(Inv));
                        BodyCell(t.Cell()).Text(l.Description);
                        BodyCell(t.Cell()).AlignRight().Text(Rm(l.Amount)).FontColor(l.Amount < 0 ? Colors.Green.Darken2 : Colors.Black);
                    }
                });

                col.Item().AlignRight().Width(240).PaddingTop(8).Column(c =>
                {
                    TotalRow(c, "Subtotal", Rm(inv.Subtotal));
                    if (inv.Discount > 0) TotalRow(c, "Discount", "- " + Rm(inv.Discount));
                    TotalRow(c, "Total", Rm(inv.Total), bold: true);
                    if (inv.AmountPaid > 0) TotalRow(c, "Paid", "- " + Rm(inv.AmountPaid));
                    TotalRow(c, "Balance due", Rm(inv.Balance), bold: true, color: company.BrandColor);
                });

                if (inv.Payments.Count > 0)
                {
                    col.Item().PaddingTop(14).Text("Payments received").Bold();
                    foreach (var p in inv.Payments.OrderBy(p => p.PaidOn))
                        col.Item().Text($"{p.PaidOn.ToString("d MMM yyyy", Inv)}  ·  {p.ReceiptNo}  ·  {p.Method}" +
                                        (p.Reference != null ? $" ({p.Reference})" : "") + $"  ·  {Rm(p.Amount)}").FontSize(9);
                }
                if (inv.Status == FeeInvoice.Void)
                    col.Item().PaddingTop(10).Text($"This invoice was cancelled: {inv.VoidReason}").FontColor(Colors.Red.Darken2).Bold();
                if (!string.IsNullOrWhiteSpace(inv.Notes))
                    col.Item().PaddingTop(10).Text(inv.Notes).Italic();
                if (!string.IsNullOrWhiteSpace(company.FeePaymentInstructions) && inv.Balance > 0)
                {
                    col.Item().PaddingTop(16).Background(Colors.Grey.Lighten4).Padding(10).Column(c =>
                    {
                        c.Item().Text("How to pay").Bold();
                        c.Item().Text(company.FeePaymentInstructions);
                    });
                }
            });
            Footer(page);
        })).GeneratePdf();
    }

    /// <summary>
    /// "Price &amp; Terms 2027": each session's hours, meals and monthly fee, the first-time charges,
    /// the total upon registration, the deposit and the second month, and the terms — like the
    /// school's own price sheet, made from the price list.
    /// </summary>
    public static byte[] PriceTerms(CompanySettings company, FeePriceList list)
    {
        var sessions = list.Sessions.Where(s => s.Offered).OrderBy(s => Array.IndexOf(Student.SessionTypes, s.SessionType)).ToList();
        return Document.Create(doc => doc.Page(page =>
        {
            Setup(page);
            page.Content().Column(col =>
            {
                Header(col, company, "PRICE & TERMS");
                col.Item().PaddingTop(12).AlignCenter().Text($"Price & Terms, {list.Name}").FontSize(16).Bold().FontColor(company.BrandColor);
                col.Item().AlignCenter().Text($"From {list.EffectiveFrom.ToString("d MMMM yyyy", Inv)}").FontSize(9).FontColor(Colors.Grey.Darken1);

                col.Item().PaddingTop(14).Table(t =>
                {
                    t.ColumnsDefinition(c => { c.RelativeColumn(2); foreach (var _ in sessions) c.RelativeColumn(); });
                    t.Header(h =>
                    {
                        HeadCell(h.Cell(), "", company);
                        foreach (var s in sessions) HeadCell(h.Cell(), s.SessionType, company, right: true);
                    });
                    void Row(string label, Func<FeePriceSession, string> value, bool bold = false)
                    {
                        var l = BodyCell(t.Cell()).Text(label);
                        if (bold) l.Bold();
                        foreach (var s in sessions)
                        {
                            var v = BodyCell(t.Cell()).AlignRight().Text(value(s));
                            if (bold) v.Bold();
                        }
                    }
                    Row("Hours", s => $"{s.Start} – {s.End}");
                    Row("Monthly school fees", s => Rm(s.MonthlyFee), bold: true);
                    Row("Meals included", s => s.MealsIncluded ?? "—");

                    var firstTime = list.Charges.Where(c => c.Kind != FeePriceCharge.Deposit).OrderBy(c => c.SortOrder).ThenBy(c => c.Id).ToList();
                    foreach (var c in firstTime)
                        Row(c.Kind == FeePriceCharge.TwiceAYear ? $"{c.Name} (twice a year)" : c.Name,
                            s => FeePrices.AppliesTo(c, s.SessionType) ? Rm(c.Amount) : "n.a.");
                    Row("Total upon registration", s => Rm(s.MonthlyFee + firstTime.Where(c => FeePrices.AppliesTo(c, s.SessionType)).Sum(c => c.Amount)), bold: true);

                    foreach (var d in list.Charges.Where(c => c.Kind == FeePriceCharge.Deposit).OrderBy(c => c.SortOrder))
                        Row($"{d.Name} (refundable, 2nd month)", s => FeePrices.AppliesTo(d, s.SessionType) ? Rm(d.Amount) : "n.a.");
                    if (list.Charges.Any(c => c.Kind == FeePriceCharge.Deposit))
                        Row("2nd month payable", s => Rm(s.MonthlyFee + list.Charges
                            .Where(c => c.Kind == FeePriceCharge.Deposit && FeePrices.AppliesTo(c, s.SessionType)).Sum(c => c.Amount)), bold: true);
                });

                var months = FeePrices.Months(list.TwiceAYearMonths);
                if (list.Charges.Any(c => c.Kind == FeePriceCharge.TwiceAYear) && months.Length > 0)
                    col.Item().PaddingTop(10).Text("Twice-a-year charges are billed at registration and in " +
                        string.Join(" and ", months.Select(m => new DateTime(2000, m, 1).ToString("MMMM", Inv))) + ".").FontSize(9);
                if (!string.IsNullOrWhiteSpace(list.Terms))
                    col.Item().PaddingTop(10).Text(list.Terms).FontSize(9);
                if (!string.IsNullOrWhiteSpace(company.FeePaymentInstructions))
                    col.Item().PaddingTop(14).Background(Colors.Grey.Lighten4).Padding(10).Column(c =>
                    {
                        c.Item().Text("How to pay").Bold();
                        c.Item().Text(company.FeePaymentInstructions);
                    });
            });
            Footer(page);
        })).GeneratePdf();
    }

    public static byte[] Receipt(CompanySettings company, FeeInvoice inv, FeePayment payment, IReadOnlyList<string> parents)
    {
        var month = new DateTime(inv.Year, inv.Month, 1).ToString("MMMM yyyy", Inv);
        var balanceAfter = Math.Max(0, inv.Total - inv.Payments.Where(p => p.PaidOn < payment.PaidOn
                                                                          || (p.PaidOn == payment.PaidOn && p.Id <= payment.Id)).Sum(p => p.Amount));
        return Document.Create(doc => doc.Page(page =>
        {
            Setup(page);
            page.Content().Column(col =>
            {
                Header(col, company, "OFFICIAL RECEIPT");

                col.Item().PaddingTop(14).Row(row =>
                {
                    row.RelativeItem().Column(c =>
                    {
                        c.Item().Text("Received from").FontSize(8).FontColor(Colors.Grey.Darken1);
                        c.Item().Text(parents.Count > 0 ? string.Join(" / ", parents) : "Parent / guardian").Bold();
                        c.Item().Text($"For: {inv.Student.FullName}" + (inv.Student.Class != null ? $" ({inv.Student.Class.Name})" : ""));
                    });
                    row.ConstantItem(200).Column(c =>
                    {
                        KeyValue(c, "Receipt no.", payment.ReceiptNo);
                        KeyValue(c, "Date", payment.PaidOn.ToString("d MMM yyyy", Inv));
                        KeyValue(c, "Invoice", inv.InvoiceNo);
                    });
                });

                col.Item().PaddingTop(20).Border(1).BorderColor(Colors.Grey.Lighten1).Padding(14).Column(c =>
                {
                    c.Item().Row(r =>
                    {
                        r.RelativeItem().Text($"School fees for {month}");
                        r.ConstantItem(140).AlignRight().Text(Rm(payment.Amount)).FontSize(16).Bold().FontColor(company.BrandColor);
                    });
                    c.Item().PaddingTop(6).Text($"Paid by {payment.Method}" + (payment.Reference != null ? $", reference {payment.Reference}" : "") + ".").FontSize(9);
                    c.Item().Text($"Invoice total {Rm(inv.Total)}; balance after this payment {Rm(balanceAfter)}.").FontSize(9);
                });

                col.Item().PaddingTop(30).Text($"Received by: {payment.RecordedByName}").FontSize(9);
                col.Item().PaddingTop(2).Text("This is a computer-generated receipt; no signature is required.").FontSize(8).FontColor(Colors.Grey.Darken1);
            });
            Footer(page);
        })).GeneratePdf();
    }

    // ── layout pieces ──

    private static void Setup(PageDescriptor page)
    {
        page.Size(PageSizes.A4);
        page.MarginHorizontal(36);
        page.MarginVertical(30);
        page.DefaultTextStyle(x => x.FontSize(10).FontFamily("Arial"));
    }

    private static void Header(ColumnDescriptor col, CompanySettings company, string title)
    {
        col.Item().Row(row =>
        {
            if (company.LogoData != null)
                row.ConstantItem(70).Height(56).AlignMiddle().Image(company.LogoData).FitArea();
            row.RelativeItem().PaddingLeft(company.LogoData != null ? 10 : 0).AlignMiddle().Column(c =>
            {
                c.Item().Text(company.NameForDocuments).FontSize(15).Bold().FontColor(company.BrandColor);
                if (!string.IsNullOrWhiteSpace(company.RegistrationNo)) c.Item().Text($"({company.RegistrationNo})").FontSize(8);
                if (!string.IsNullOrWhiteSpace(company.Address)) c.Item().Text(company.Address).FontSize(8);
                var contact = string.Join("  ·  ", new[] { company.Phone, company.Website }.Where(x => !string.IsNullOrWhiteSpace(x)));
                if (contact.Length > 0) c.Item().Text(contact).FontSize(8);
            });
            row.ConstantItem(170).AlignRight().AlignMiddle().Text(title).FontSize(16).Bold();
        });
        col.Item().PaddingTop(8).LineHorizontal(1.5f).LineColor(company.BrandColor);
    }

    private static void Footer(PageDescriptor page) =>
        page.Footer().AlignCenter().Text(t =>
        {
            t.DefaultTextStyle(x => x.FontSize(7).FontColor(Colors.Grey.Darken1));
            t.Span("Generated ");
            t.Span(DateTime.UtcNow.Add(SchoolClock.Offset).ToString("d MMM yyyy HH:mm", Inv));
            t.Span(" · page ");
            t.CurrentPageNumber();
        });

    private static void KeyValue(ColumnDescriptor c, string key, string value) =>
        c.Item().Row(r =>
        {
            r.ConstantItem(80).Text(key).FontSize(8).FontColor(Colors.Grey.Darken1);
            r.RelativeItem().AlignRight().Text(value).FontSize(9).Bold();
        });

    private static void HeadCell(IContainer cell, string text, CompanySettings company, bool right = false)
    {
        var inner = cell.Background(company.BrandColor).PaddingVertical(5).PaddingHorizontal(6);
        (right ? inner.AlignRight() : inner).Text(text).FontColor(Colors.White).Bold().FontSize(9);
    }

    private static IContainer BodyCell(IContainer cell) =>
        cell.BorderBottom(0.5f).BorderColor(Colors.Grey.Lighten2).PaddingVertical(5).PaddingHorizontal(6);

    private static void TotalRow(ColumnDescriptor c, string label, string value, bool bold = false, string? color = null) =>
        c.Item().PaddingVertical(2).Row(r =>
        {
            var l = r.RelativeItem().Text(label);
            var v = r.ConstantItem(120).AlignRight().Text(value);
            if (bold) { l.Bold(); v.Bold(); }
            if (color != null) v.FontColor(color);
        });
}
