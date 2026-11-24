import { ChangeDetectorRef, Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { SchoolFeesService, StudentDepositRow, rm } from '../../../../core/services/school-fees.service';
import { ToastService } from '../../../../core/services/toast.service';

/**
 * School → Fees → Deposits: refundable deposits the school holds (billed in each child's second
 * month). At the end of the year: refund (cash / transfer, with a note) or deduct from one of the
 * child's unpaid invoices. Same as the app.
 */
@Component({
  selector: 'app-deposits',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './deposits.component.html',
  styleUrls: ['../../school-shared.scss']
})
export class DepositsComponent implements OnInit {
  private fees = inject(SchoolFeesService);
  private toast = inject(ToastService);
  private cdr = inject(ChangeDetectorRef);

  readonly rm = rm;

  all = false;
  rows: StudentDepositRow[] = [];
  loading = true;

  settling: StudentDepositRow | null = null;
  how: 'refund' | 'deduct' = 'refund';
  invoiceId: number | null = null;
  note = '';
  busy = false;

  get heldTotal(): number { return this.rows.filter(r => r.status === 'Held').reduce((s, r) => s + r.amount, 0); }

  ngOnInit(): void { this.load(); }

  load(): void {
    this.loading = true;
    this.fees.getDeposits(this.all).subscribe({
      next: r => { this.rows = r; this.loading = false; this.cdr.markForCheck(); },
      error: err => { this.loading = false; this.toast.error('Deposits', err?.error?.message ?? 'Could not load.'); this.cdr.markForCheck(); }
    });
  }

  start(r: StudentDepositRow): void {
    this.settling = r;
    this.how = 'refund';
    this.invoiceId = r.openInvoices[0]?.id ?? null;
    this.note = '';
  }

  confirm(): void {
    const r = this.settling;
    if (!r) return;
    if (this.how === 'deduct' && !this.invoiceId) { this.toast.error('Deposit', 'Choose the invoice.'); return; }
    this.busy = true;
    this.fees.settleDeposit(r.id, this.how, this.how === 'deduct' ? this.invoiceId : null, this.note.trim() || null).subscribe({
      next: () => {
        this.busy = false;
        this.settling = null;
        this.toast.success('Deposit', this.how === 'refund' ? `${r.childName}'s deposit marked refunded.` : `Deducted from the invoice.`);
        this.load();
      },
      error: err => { this.busy = false; this.toast.error('Deposit', err?.error?.message ?? 'Could not save.'); this.cdr.markForCheck(); }
    });
  }

  monthName(y: number, m: number): string { return new Date(y, m - 1, 1).toLocaleDateString(undefined, { month: 'short', year: 'numeric' }); }
}
