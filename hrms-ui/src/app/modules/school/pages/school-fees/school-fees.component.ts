import { Component, OnInit, ChangeDetectorRef, inject } from '@angular/core';
import { CommonModule, Location } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router, RouterModule } from '@angular/router';
import { SchoolService, SchoolClass, SESSION_TYPES } from '../../../../core/services/school.service';
import {
  SchoolFeesService, FeeItem, FeeSettings, InvoiceRow, InvoiceSummary, InvoiceDetail, InvoiceLine, PaymentClaim, PAYMENT_METHODS, rm
} from '../../../../core/services/school-fees.service';
import { schoolToday } from '../../../../core/services/school-day.service';
import { ToastService } from '../../../../core/services/toast.service';
import { ConfirmModalComponent } from '../../../../shared/components/confirm-modal/confirm-modal.component';
import { InputModalComponent } from '../../../../shared/components/input-modal/input-modal.component';
import { PriceListsComponent } from '../../components/price-lists/price-lists.component';
import { DepositsComponent } from '../../components/deposits/deposits.component';

type Tab = 'invoices' | 'claims' | 'prices' | 'deposits' | 'items' | 'addons' | 'settings';

/**
 * School → Fees (admin). Monthly invoices per child (session fee + add-ons − sibling discount),
 * payments with receipts, reminders; fee items, which child takes which add-on, settings.
 */
@Component({
  selector: 'app-school-fees',
  standalone: true,
  imports: [CommonModule, FormsModule, RouterModule, ConfirmModalComponent, InputModalComponent, PriceListsComponent, DepositsComponent],
  templateUrl: './school-fees.component.html',
  styleUrls: ['../../school-shared.scss', './school-fees.component.scss']
})
export class SchoolFeesComponent implements OnInit {
  private school = inject(SchoolService);
  private fees = inject(SchoolFeesService);
  private toast = inject(ToastService);
  private route = inject(ActivatedRoute);
  private router = inject(Router);
  private location = inject(Location);
  private cdr = inject(ChangeDetectorRef);

  readonly rm = rm;
  readonly sessionTypes = SESSION_TYPES;
  readonly methods = PAYMENT_METHODS;

  tab: Tab = 'invoices';
  /** A price list exists (fees come from it, not from the session fee items). */
  hasPriceList = false;

  // ── Invoices ──
  year = +schoolToday().substring(0, 4);
  month = +schoolToday().substring(5, 7);
  status = '';
  classId: number | null = null;
  classes: SchoolClass[] = [];
  /** Invoices ticked for "Send selected". */
  selected = new Set<number>();
  invoices: InvoiceRow[] = [];
  summary: InvoiceSummary | null = null;
  loading = true;
  working = false;
  confirmGenerate = false;
  search = '';
  /** Sent to parents or not ('' = all) — filters the loaded list. */
  sentFilter: '' | 'sent' | 'unsent' = '';

  detail: InvoiceDetail | null = null;
  detailLines: InvoiceLine[] = [];
  detailDue = '';
  detailNotes = '';
  detailError = '';
  detailSaving = false;
  pay = { amount: 0, paidOn: schoolToday(), method: 'Cash', reference: '' };
  askVoid = false;
  confirmPaymentDelete: number | null = null;

  // ── "I've paid" claims ──
  claims: PaymentClaim[] = [];
  claimsStatus = 'Pending';
  claimsLoading = false;
  rejecting: PaymentClaim | null = null;
  confirming: number | null = null;

  // ── Items ──
  items: FeeItem[] = [];
  itemModal = false;
  itemEditing: FeeItem | null = null;
  itemForm: Partial<FeeItem> = {};
  itemError = '';
  confirmItemDelete: FeeItem | null = null;

  // ── Add-ons ──
  addOnItems: { id: number; name: string; amount: number; isActive: boolean }[] = [];
  addOnChildren: { id: number; fullName: string; sessionType: string; className: string | null; addOnIds: number[] }[] = [];

  // ── Settings ──
  settings: FeeSettings = { siblingDiscountPercent: 0, feeDueDay: 7, feePaymentInstructions: null };
  settingsSaving = false;

  get monthLabel(): string {
    return new Date(Date.UTC(this.year, this.month - 1, 1)).toLocaleDateString('en-GB', { month: 'long', year: 'numeric', timeZone: 'UTC' });
  }

  get shownInvoices(): InvoiceRow[] {
    const q = this.search.trim().toLowerCase();
    return this.invoices.filter(i =>
      (this.sentFilter === '' || (this.sentFilter === 'sent' ? !!i.sentAt : !i.sentAt && i.status !== 'Void'))
      && (!q || i.studentName.toLowerCase().includes(q) || i.invoiceNo.toLowerCase().includes(q) || i.parents.some(p => p.toLowerCase().includes(q))));
  }

  /** Shows only the invoices not sent to parents yet. */
  showUnsent(): void {
    this.sentFilter = 'unsent';
    if (this.status) { this.status = ''; this.loadInvoices(); }
  }

  get sessionItems(): FeeItem[] { return this.items.filter(i => i.kind === 'Session'); }
  get addOnFeeItems(): FeeItem[] { return this.items.filter(i => i.kind === 'AddOn'); }
  get detailTotal(): number { return this.detailLines.reduce((s, l) => s + (+l.amount || 0), 0); }
  get editable(): boolean { return !!this.detail && this.detail.status !== 'Void'; }

  ngOnInit(): void {
    const qp = this.route.snapshot.queryParamMap;
    const t = qp.get('tab') as Tab | null;
    if (t && ['invoices', 'claims', 'prices', 'deposits', 'items', 'addons', 'settings'].includes(t)) this.tab = t;
    this.school.getClasses().subscribe({ next: c => { this.classes = c.filter(x => x.isActive); this.cdr.markForCheck(); }, error: () => {} });
    this.fees.getPriceLists().subscribe({ next: l => { this.hasPriceList = l.length > 0; this.cdr.markForCheck(); }, error: () => {} });
    if (qp.get('month')) { const [y, m] = qp.get('month')!.split('-').map(Number); if (y && m) { this.year = y; this.month = m; } }
    this.loadItems();
    this.loadTab();
  }

  setTab(t: Tab): void {
    this.tab = t;
    this.syncUrl();
    this.loadTab();
  }

  private syncUrl(): void {
    const q = this.tab === 'invoices' ? `month=${this.year}-${String(this.month).padStart(2, '0')}` : `tab=${this.tab}`;
    this.location.replaceState(this.router.url.split('?')[0], q);
  }

  private loadTab(): void {
    if (this.tab === 'invoices') this.loadInvoices();
    if (this.tab === 'claims') this.loadClaims();
    if (this.tab === 'items') this.loadItems();
    if (this.tab === 'addons') this.loadAddOns();
    if (this.tab === 'settings') this.fees.getSettings().subscribe({ next: s => { this.settings = s; this.cdr.markForCheck(); }, error: () => {} });
  }

  // ════════════ Invoices ════════════

  loadInvoices(quiet = false): void {
    if (!quiet) this.loading = true;
    this.fees.getInvoices(this.year, this.month, this.status || null, this.classId).subscribe({
      next: r => {
        this.invoices = r.invoices;
        this.summary = r.summary;
        this.loading = false;
        // Keep only ticks that are still on the list
        const ids = new Set(r.invoices.map(i => i.id));
        this.selected = new Set([...this.selected].filter(id => ids.has(id)));
        this.cdr.markForCheck();
      },
      error: err => { this.loading = false; this.toast.error('Load Failed', err?.error?.message ?? 'Could not load invoices.'); this.cdr.markForCheck(); }
    });
  }

  shiftMonth(n: number): void {
    const d = new Date(Date.UTC(this.year, this.month - 1 + n, 1));
    this.year = d.getUTCFullYear();
    this.month = d.getUTCMonth() + 1;
    this.syncUrl();
    this.loadInvoices();
  }

  generate(): void {
    this.confirmGenerate = false;
    this.working = true;
    this.fees.generate(this.year, this.month).subscribe({
      next: r => {
        this.working = false;
        const skipped = r.skipped.length ? ` ${r.skipped.length} skipped: ${r.skipped.map(s => `${s.fullName} (${s.reason})`).join(', ')}.` : '';
        if (r.created === 0 && !r.skipped.length) this.toast.info('Invoices', `Every child already has an invoice for ${this.monthLabel}.`);
        else this.toast.success('Invoices created', `${r.created} invoice${r.created === 1 ? '' : 's'} for ${this.monthLabel}. Check them, then send them to the parents.${skipped}`);
        this.loadInvoices(true);
      },
      error: err => { this.working = false; this.toast.error('Invoices', err?.error?.message ?? 'Could not create the invoices.'); this.cdr.markForCheck(); }
    });
  }

  get className(): string { return this.classes.find(c => c.id === this.classId)?.name ?? ''; }

  sendAll(): void {
    this.working = true;
    this.fees.send(this.year, this.month, { classId: this.classId }).subscribe({
      next: r => { this.working = false; this.toast.success('Sent', this.sentText(r)); this.loadInvoices(true); },
      error: err => { this.working = false; this.toast.error('Send', err?.error?.message ?? 'Could not send.'); this.cdr.markForCheck(); }
    });
  }

  /** Ticked invoices: unsent ones are sent, sent ones are sent again. */
  sendSelected(): void {
    const ids = [...this.selected];
    if (!ids.length) return;
    this.working = true;
    this.fees.send(this.year, this.month, { invoiceIds: ids, resend: true }).subscribe({
      next: r => { this.working = false; this.selected.clear(); this.toast.success('Sent', this.sentText(r)); this.loadInvoices(true); },
      error: err => { this.working = false; this.toast.error('Send', err?.error?.message ?? 'Could not send.'); this.cdr.markForCheck(); }
    });
  }

  private sentText(r: { sent: number; emailed: number }): string {
    return `${r.sent} invoice${r.sent === 1 ? '' : 's'} sent to the parents` +
      (r.emailed ? ` (${r.emailed} email${r.emailed === 1 ? '' : 's'} with the PDF).` : '.');
  }

  toggleSelect(id: number, on: boolean): void { on ? this.selected.add(id) : this.selected.delete(id); }

  get allSelected(): boolean {
    const list = this.shownInvoices.filter(i => i.status !== 'Void');
    return list.length > 0 && list.every(i => this.selected.has(i.id));
  }

  toggleAll(on: boolean): void {
    for (const i of this.shownInvoices.filter(x => x.status !== 'Void')) on ? this.selected.add(i.id) : this.selected.delete(i.id);
  }

  remindAll(): void {
    this.working = true;
    this.fees.remind(this.year, this.month, this.classId).subscribe({
      next: r => { this.working = false; this.toast.success('Reminders', r.reminded ? `${r.reminded} reminder${r.reminded === 1 ? '' : 's'} sent.` : 'No overdue invoices that were sent.'); },
      error: err => { this.working = false; this.toast.error('Reminders', err?.error?.message ?? 'Could not send reminders.'); this.cdr.markForCheck(); }
    });
  }

  pdf(id: number): void { this.school.openBlob(this.fees.invoicePdf(id)); }
  receipt(paymentId: number): void { this.school.openBlob(this.fees.receiptPdf(paymentId)); }

  open(id: number): void {
    this.detailError = '';
    this.fees.getInvoice(id).subscribe({
      next: d => this.showDetail(d),
      error: err => this.toast.error('Invoice', err?.error?.message ?? 'Could not open the invoice.')
    });
  }

  private showDetail(d: InvoiceDetail): void {
    this.detail = d;
    this.detailLines = d.lines.map(l => ({ ...l }));
    this.detailDue = d.dueDate;
    this.detailNotes = d.notes ?? '';
    this.pay = { amount: d.balance, paidOn: schoolToday(), method: this.pay.method, reference: '' };
    this.cdr.markForCheck();
  }

  closeDetail(): void { this.detail = null; this.loadInvoices(true); }

  addLine(discount = false): void {
    this.detailLines = [...this.detailLines, { description: discount ? 'Discount' : '', amount: 0 }];
  }

  removeLine(i: number): void { this.detailLines = this.detailLines.filter((_, x) => x !== i); }

  saveDetail(): void {
    const d = this.detail;
    if (!d) return;
    this.detailSaving = true;
    this.detailError = '';
    this.fees.updateInvoice(d.id, {
      lines: this.detailLines.map(l => ({ description: l.description, amount: +l.amount || 0, feeItemId: l.feeItemId ?? null })),
      dueDate: this.detailDue || null, notes: this.detailNotes.trim() || null
    }).subscribe({
      next: r => { this.detailSaving = false; this.toast.success('Saved', `${r.invoiceNo} was updated.`); this.showDetail(r); },
      error: err => { this.detailSaving = false; this.detailError = err?.error?.message ?? 'Could not save.'; this.cdr.markForCheck(); }
    });
  }

  recordPayment(): void {
    const d = this.detail;
    if (!d) return;
    if (!(this.pay.amount > 0)) { this.detailError = 'Enter the amount received.'; return; }
    this.detailSaving = true;
    this.detailError = '';
    this.fees.addPayment(d.id, { ...this.pay, amount: +this.pay.amount, reference: this.pay.reference.trim() || null }).subscribe({
      next: r => {
        this.detailSaving = false;
        const p = r.payments[r.payments.length - 1];
        this.toast.success('Payment recorded', `Receipt ${p?.receiptNo ?? ''}: ${rm(p?.amount)}.`);
        this.showDetail(r);
      },
      error: err => { this.detailSaving = false; this.detailError = err?.error?.message ?? 'Could not record the payment.'; this.cdr.markForCheck(); }
    });
  }

  deletePayment(): void {
    const id = this.confirmPaymentDelete;
    this.confirmPaymentDelete = null;
    if (!id) return;
    this.fees.deletePayment(id).subscribe({
      next: r => { this.toast.success('Removed', 'The payment was removed.'); this.showDetail(r); },
      error: err => this.toast.error('Payment', err?.error?.message ?? 'Could not remove the payment.')
    });
  }

  /** Send (or send again, when a parent asks) this invoice: notification + email with the PDF. */
  sendOne(): void {
    const d = this.detail;
    if (!d) return;
    this.fees.send(this.year, this.month, { invoiceIds: [d.id], resend: true }).subscribe({
      next: r => { this.toast.success('Sent', `${d.invoiceNo}: ${this.sentText(r)}`); this.open(d.id); },
      error: err => this.toast.error('Send', err?.error?.message ?? 'Could not send.')
    });
  }

  voidInvoice(reason: string): void {
    this.askVoid = false;
    const d = this.detail;
    if (!d) return;
    this.fees.voidInvoice(d.id, reason).subscribe({
      next: () => { this.toast.success('Voided', `${d.invoiceNo} was cancelled.`); this.open(d.id); },
      error: err => this.toast.error('Void', err?.error?.message ?? 'Could not cancel the invoice.')
    });
  }

  // ════════════ "I've paid" claims ════════════

  loadClaims(): void {
    this.claimsLoading = true;
    this.fees.getClaims(this.claimsStatus || null).subscribe({
      next: c => { this.claims = c; this.claimsLoading = false; this.cdr.markForCheck(); },
      error: err => { this.claimsLoading = false; this.toast.error('Load Failed', err?.error?.message ?? 'Could not load.'); this.cdr.markForCheck(); }
    });
  }

  slip(c: PaymentClaim): void { this.school.openBlob(this.fees.claimSlip(c.id)); }

  /** The money is in the bank: record the payment and issue the receipt. */
  confirmClaim(c: PaymentClaim): void {
    this.confirming = c.id;
    this.fees.confirmClaim(c.id).subscribe({
      next: inv => {
        this.confirming = null;
        const p = inv.payments[inv.payments.length - 1];
        this.toast.success('Payment confirmed', `${c.studentName}: receipt ${p?.receiptNo ?? ''} (${rm(c.amount)}). The parent was told.`);
        if (this.tab === 'claims') this.loadClaims();
        if (this.summary) this.summary = { ...this.summary, claimsPending: Math.max(0, this.summary.claimsPending - 1) };
        if (this.detail?.id === inv.id) this.showDetail(inv);
      },
      error: err => { this.confirming = null; this.toast.error('Confirm', err?.error?.message ?? 'Could not confirm.'); this.cdr.markForCheck(); }
    });
  }

  rejectClaim(reason: string): void {
    const c = this.rejecting;
    this.rejecting = null;
    if (!c) return;
    this.fees.rejectClaim(c.id, reason).subscribe({
      next: () => {
        this.toast.success('Not confirmed', `${c.studentName}: the parent was told why.`);
        if (this.tab === 'claims') this.loadClaims();
        if (this.summary) this.summary = { ...this.summary, claimsPending: Math.max(0, this.summary.claimsPending - 1) };
        if (this.detail?.id === c.invoiceId) this.open(c.invoiceId);
      },
      error: err => this.toast.error('Reject', err?.error?.message ?? 'Could not save.')
    });
  }

  claimMonth(c: PaymentClaim): string {
    return new Date(Date.UTC(c.year, c.month - 1, 1)).toLocaleDateString('en-GB', { month: 'short', year: 'numeric', timeZone: 'UTC' });
  }

  // ════════════ Fee items ════════════

  loadItems(): void {
    this.fees.getItems().subscribe({ next: i => { this.items = i; this.cdr.markForCheck(); }, error: () => {} });
  }

  openItem(item: FeeItem | null, kind: 'Session' | 'AddOn' = 'Session'): void {
    this.itemEditing = item;
    this.itemForm = item ? { ...item } : {
      name: '', kind, sessionType: kind === 'Session' ? this.missingSessionType() : null,
      amount: 0, sortOrder: 0, isActive: true
    };
    this.itemError = '';
    this.itemModal = true;
  }

  /** The first session type without a monthly fee yet (to suggest it). */
  private missingSessionType(): string {
    return SESSION_TYPES.find(t => !this.items.some(i => i.kind === 'Session' && i.isActive && i.sessionType === t)) ?? SESSION_TYPES[0];
  }

  saveItem(): void {
    const body = { ...this.itemForm, amount: +(this.itemForm.amount ?? 0) };
    const req = this.itemEditing ? this.fees.updateItem(this.itemEditing.id, body) : this.fees.createItem(body);
    req.subscribe({
      next: () => { this.itemModal = false; this.toast.success('Saved', body.name ?? ''); this.loadItems(); },
      error: err => { this.itemError = err?.error?.message ?? 'Could not save.'; this.cdr.markForCheck(); }
    });
  }

  deleteItem(): void {
    const item = this.confirmItemDelete;
    this.confirmItemDelete = null;
    if (!item) return;
    this.fees.deleteItem(item.id).subscribe({
      next: () => { this.toast.success('Deleted', item.name); this.loadItems(); },
      error: err => this.toast.error('Delete', err?.error?.message ?? 'Could not delete.')
    });
  }

  // ════════════ Add-ons ════════════

  loadAddOns(): void {
    this.fees.getAddOns().subscribe({
      next: r => { this.addOnItems = r.items; this.addOnChildren = r.children; this.cdr.markForCheck(); },
      error: () => {}
    });
  }

  toggleAddOn(child: { id: number; fullName: string; addOnIds: number[] }, itemId: number, on: boolean): void {
    const before = child.addOnIds;
    child.addOnIds = on ? [...before, itemId] : before.filter(x => x !== itemId);
    this.fees.setAddOns(child.id, child.addOnIds).subscribe({
      error: err => { child.addOnIds = before; this.toast.error('Add-ons', err?.error?.message ?? 'Could not save.'); this.cdr.markForCheck(); }
    });
  }

  addOnCount(itemId: number): number { return this.addOnChildren.filter(c => c.addOnIds.includes(itemId)).length; }

  // ════════════ Settings ════════════

  saveSettings(): void {
    this.settingsSaving = true;
    this.fees.saveSettings({ ...this.settings, siblingDiscountPercent: +this.settings.siblingDiscountPercent, feeDueDay: +this.settings.feeDueDay }).subscribe({
      next: () => { this.settingsSaving = false; this.toast.success('Saved', 'Fee settings were saved.'); this.cdr.markForCheck(); },
      error: err => { this.settingsSaving = false; this.toast.error('Settings', err?.error?.message ?? 'Could not save.'); this.cdr.markForCheck(); }
    });
  }
}
