import { Injectable, inject } from '@angular/core';
import { HttpClient, HttpParams } from '@angular/common/http';
import { Observable } from 'rxjs';
import { environment } from '../../../environments/environment';

// ── School phase 4: monthly fees ──

export interface FeeItem {
  id: number;
  name: string;
  kind: 'Session' | 'AddOn';
  sessionType: string | null;
  amount: number;
  sortOrder: number;
  isActive: boolean;
  children?: number;
}

export interface FeeSettings {
  siblingDiscountPercent: number;
  feeDueDay: number;
  feePaymentInstructions: string | null;
}

export interface InvoiceRow {
  id: number;
  invoiceNo: string;
  studentId: number;
  studentName: string;
  className: string | null;
  parents: string[];
  issueDate: string;
  dueDate: string;
  subtotal: number;
  discount: number;
  total: number;
  amountPaid: number;
  balance: number;
  status: 'Unpaid' | 'Partial' | 'Paid' | 'Void';
  sentAt: string | null;
  lastSentAt: string | null;
  sendCount: number;
  /** A parent reported paying it; waiting for the office. */
  pendingClaim?: boolean;
  overdue: boolean;
}

export interface InvoiceSummary {
  count: number;
  billed: number;
  collected: number;
  outstanding: number;
  paid: number;
  overdue: number;
  notSent: number;
  childrenWithoutInvoice: number;
  /** Payments parents reported, any month, waiting for the office. */
  claimsPending: number;
}

/** A parent's "I've paid": the office confirms (payment + receipt) or rejects it. */
export interface PaymentClaim {
  id: number;
  invoiceId: number;
  invoiceNo: string;
  studentName: string;
  className: string | null;
  year: number;
  month: number;
  invoiceBalance: number;
  amount: number;
  paidOn: string;
  method: string;
  reference: string | null;
  note: string | null;
  hasSlip: boolean;
  slipName: string | null;
  slipIsPdf: boolean;
  status: 'Pending' | 'Confirmed' | 'Rejected';
  rejectReason: string | null;
  createdByName: string;
  createdAt: string;
  reviewedByName: string | null;
  reviewedAt: string | null;
}

export interface InvoiceLine { id?: number; description: string; amount: number; feeItemId?: number | null; }

export interface FeePaymentInfo {
  id: number;
  receiptNo: string;
  amount: number;
  paidOn: string;
  method: string;
  reference: string | null;
  recordedByName: string;
}

export interface InvoiceDetail extends Omit<InvoiceRow, 'parents'> {
  year: number;
  month: number;
  monthName: string;
  notes: string | null;
  voidReason: string | null;
  lines: InvoiceLine[];
  payments: FeePaymentInfo[];
  claims: PaymentClaim[];
}

export const PAYMENT_METHODS = ['Cash', 'Bank transfer', 'Card', 'DuitNow / QR', 'Cheque', 'Online'];

/** "RM 1,234.00" */
export function rm(v: number | null | undefined): string {
  return 'RM ' + (v ?? 0).toLocaleString('en-MY', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

@Injectable({ providedIn: 'root' })
export class SchoolFeesService {
  private api = `${environment.apiUrl}/school/fees`;
  private http = inject(HttpClient);

  // Items and add-ons
  getItems(): Observable<FeeItem[]> { return this.http.get<FeeItem[]>(`${this.api}/items`); }
  createItem(i: Partial<FeeItem>): Observable<{ id: number }> { return this.http.post<{ id: number }>(`${this.api}/items`, i); }
  updateItem(id: number, i: Partial<FeeItem>): Observable<{ id: number }> { return this.http.put<{ id: number }>(`${this.api}/items/${id}`, i); }
  deleteItem(id: number): Observable<void> { return this.http.delete<void>(`${this.api}/items/${id}`); }
  getAddOns(): Observable<{ items: { id: number; name: string; amount: number; isActive: boolean }[];
                            children: { id: number; fullName: string; sessionType: string; className: string | null; addOnIds: number[] }[] }> {
    return this.http.get<any>(`${this.api}/addons`);
  }
  setAddOns(studentId: number, feeItemIds: number[]): Observable<void> {
    return this.http.put<void>(`${this.api}/addons/${studentId}`, { feeItemIds });
  }

  // Settings
  getSettings(): Observable<FeeSettings> { return this.http.get<FeeSettings>(`${this.api}/settings`); }
  saveSettings(s: FeeSettings): Observable<void> { return this.http.put<void>(`${this.api}/settings`, s); }

  // Invoices
  getInvoices(year: number, month: number, status?: string | null, classId?: number | null): Observable<{ invoices: InvoiceRow[]; summary: InvoiceSummary }> {
    let p = new HttpParams().set('year', year).set('month', month);
    if (status) p = p.set('status', status);
    if (classId) p = p.set('classId', classId);
    return this.http.get<{ invoices: InvoiceRow[]; summary: InvoiceSummary }>(`${this.api}/invoices`, { params: p });
  }
  getInvoice(id: number): Observable<InvoiceDetail> { return this.http.get<InvoiceDetail>(`${this.api}/invoices/${id}`); }
  generate(year: number, month: number): Observable<{ created: number; alreadyHad: number; skipped: { fullName: string; reason: string }[] }> {
    return this.http.post<any>(`${this.api}/invoices/generate`, { year, month });
  }
  updateInvoice(id: number, body: { lines: InvoiceLine[]; dueDate: string | null; notes: string | null }): Observable<InvoiceDetail> {
    return this.http.put<InvoiceDetail>(`${this.api}/invoices/${id}`, body);
  }
  voidInvoice(id: number, reason: string): Observable<void> { return this.http.post<void>(`${this.api}/invoices/${id}/void`, { reason }); }
  /** Send the month's unsent invoices (optionally one class), or the chosen ones; resend = also ones sent before. */
  send(year: number, month: number, opts: { invoiceIds?: number[]; classId?: number | null; resend?: boolean } = {}): Observable<{ sent: number; emailed: number }> {
    return this.http.post<{ sent: number; emailed: number }>(`${this.api}/invoices/send`, {
      year, month, invoiceIds: opts.invoiceIds ?? null, classId: opts.classId ?? null, resend: !!opts.resend
    });
  }
  remind(year: number, month: number, classId?: number | null): Observable<{ reminded: number }> {
    return this.http.post<{ reminded: number }>(`${this.api}/invoices/remind`, { year, month, classId: classId ?? null });
  }

  // "I've paid" claims
  getClaims(status: string | null = 'Pending'): Observable<PaymentClaim[]> {
    return this.http.get<PaymentClaim[]>(`${this.api}/claims`, { params: { status: status ?? '' } });
  }
  claimSlip(id: number): Observable<Blob> { return this.http.get(`${this.api}/claims/${id}/slip`, { responseType: 'blob' }); }
  confirmClaim(id: number, corrections?: { amount?: number; paidOn?: string; method?: string; reference?: string | null }): Observable<InvoiceDetail> {
    return this.http.post<InvoiceDetail>(`${this.api}/claims/${id}/confirm`, corrections ?? {});
  }
  rejectClaim(id: number, reason: string): Observable<void> { return this.http.post<void>(`${this.api}/claims/${id}/reject`, { reason }); }
  createClaim(invoiceId: number, c: { amount: number; paidOn: string; method: string; reference: string | null; note: string | null }, file: File | null): Observable<PaymentClaim> {
    const fd = new FormData();
    fd.append('amount', String(c.amount));
    fd.append('paidOn', c.paidOn);
    fd.append('method', c.method);
    if (c.reference) fd.append('reference', c.reference);
    if (c.note) fd.append('note', c.note);
    if (file) fd.append('file', file);
    return this.http.post<PaymentClaim>(`${this.api}/invoices/${invoiceId}/claims`, fd);
  }
  addPayment(id: number, p: { amount: number; paidOn: string; method: string; reference: string | null }): Observable<InvoiceDetail> {
    return this.http.post<InvoiceDetail>(`${this.api}/invoices/${id}/payments`, p);
  }
  deletePayment(paymentId: number): Observable<InvoiceDetail> { return this.http.delete<InvoiceDetail>(`${this.api}/payments/${paymentId}`); }
  invoicePdf(id: number): Observable<Blob> { return this.http.get(`${this.api}/invoices/${id}/pdf`, { responseType: 'blob' }); }
  receiptPdf(paymentId: number): Observable<Blob> { return this.http.get(`${this.api}/payments/${paymentId}/receipt`, { responseType: 'blob' }); }

  // Parents
  mine(): Observable<{ paymentInstructions: string | null; outstanding: number; invoices: InvoiceDetail[] }> {
    return this.http.get<any>(`${this.api}/mine`);
  }
}
