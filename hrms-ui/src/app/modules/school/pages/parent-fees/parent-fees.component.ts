import { Component, OnDestroy, OnInit, ChangeDetectorRef, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { RouterModule } from '@angular/router';
import { Subscription } from 'rxjs';
import { SchoolService } from '../../../../core/services/school.service';
import { SchoolFeesService, InvoiceDetail, PaymentClaim, PAYMENT_METHODS, rm } from '../../../../core/services/school-fees.service';
import { schoolToday } from '../../../../core/services/school-day.service';
import { ToastService } from '../../../../core/services/toast.service';
import { PriceTermsComponent } from '../../components/price-terms/price-terms.component';

/** Parent portal → Fees: my children's invoices, what's still to pay, receipts. */
@Component({
  selector: 'app-parent-fees',
  standalone: true,
  imports: [CommonModule, FormsModule, RouterModule, PriceTermsComponent],
  templateUrl: './parent-fees.component.html',
  styleUrls: ['../../school-shared.scss', './parent-fees.component.scss']
})
export class ParentFeesComponent implements OnInit, OnDestroy {
  private school = inject(SchoolService);
  private fees = inject(SchoolFeesService);
  private toast = inject(ToastService);
  private cdr = inject(ChangeDetectorRef);
  private subs = new Subscription();

  readonly rm = rm;
  /** Ways a parent pays from home (cash is paid at the office, which records it). */
  readonly methods = PAYMENT_METHODS.filter(m => m !== 'Cash');
  readonly today = schoolToday();

  // "I've paid"
  paying: InvoiceDetail | null = null;
  pay = { amount: 0, paidOn: schoolToday(), method: 'Bank transfer', reference: '', note: '' };
  slip: File | null = null;
  paySaving = false;
  payError = '';

  invoices: InvoiceDetail[] = [];
  outstanding = 0;
  instructions: string | null = null;
  loading = true;
  open = new Set<number>();

  get unpaid(): InvoiceDetail[] { return this.invoices.filter(i => i.balance > 0); }
  get paid(): InvoiceDetail[] { return this.invoices.filter(i => i.balance <= 0); }

  ngOnInit(): void {
    this.subs.add(this.school.liveFees$.subscribe(() => this.load(true)));
    this.school.loadMe().subscribe();
    this.load();
  }

  ngOnDestroy(): void { this.subs.unsubscribe(); }

  load(quiet = false): void {
    if (!quiet) this.loading = true;
    this.fees.mine().subscribe({
      next: r => {
        this.invoices = r.invoices;
        this.outstanding = r.outstanding;
        this.instructions = r.paymentInstructions;
        this.loading = false;
        // Unpaid ones start opened
        if (!quiet) this.unpaid.forEach(i => this.open.add(i.id));
        this.cdr.markForCheck();
      },
      error: err => {
        this.loading = false;
        this.toast.error('Load Failed', err?.error?.message ?? 'Could not load your fees.');
        this.cdr.markForCheck();
      }
    });
  }

  /** A payment this parent reported that the office hasn't checked yet. */
  pendingClaim(i: InvoiceDetail): PaymentClaim | undefined { return i.claims?.find(c => c.status === 'Pending'); }

  /** The latest report, if the office couldn't confirm it (and nothing newer is waiting). */
  rejectedClaim(i: InvoiceDetail): PaymentClaim | undefined {
    const latest = i.claims?.[0];
    return latest?.status === 'Rejected' ? latest : undefined;
  }

  openPay(i: InvoiceDetail): void {
    this.paying = i;
    this.pay = { amount: i.balance, paidOn: schoolToday(), method: 'Bank transfer', reference: '', note: '' };
    this.slip = null;
    this.payError = '';
  }

  pickSlip(input: HTMLInputElement): void {
    const f = input.files?.[0] ?? null;
    if (f && f.size > 5 * 1024 * 1024) { this.payError = 'The file must be 5 MB or smaller.'; input.value = ''; return; }
    this.slip = f;
    this.payError = '';
  }

  submitPay(): void {
    const i = this.paying;
    if (!i) return;
    if (!(this.pay.amount > 0)) { this.payError = 'Enter the amount you paid.'; return; }
    if (this.pay.amount > i.balance) { this.payError = 'That is more than the balance (' + rm(i.balance) + ').'; return; }
    this.paySaving = true;
    this.payError = '';
    this.fees.createClaim(i.id, {
      amount: +this.pay.amount, paidOn: this.pay.paidOn, method: this.pay.method,
      reference: this.pay.reference.trim() || null, note: this.pay.note.trim() || null
    }, this.slip).subscribe({
      next: () => {
        this.paySaving = false;
        this.paying = null;
        this.toast.success('Sent to the school', 'The office will check it and send your receipt.');
        this.load(true);
      },
      error: err => { this.paySaving = false; this.payError = err?.error?.message ?? 'Could not send.'; this.cdr.markForCheck(); }
    });
  }

  toggle(id: number): void { this.open.has(id) ? this.open.delete(id) : this.open.add(id); }
  pdf(id: number): void { this.school.openBlob(this.fees.invoicePdf(id)); }
  receipt(id: number): void { this.school.openBlob(this.fees.receiptPdf(id)); }
}
