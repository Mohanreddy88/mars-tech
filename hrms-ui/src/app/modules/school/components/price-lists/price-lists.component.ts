import { ChangeDetectorRef, Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { SchoolFeesService, PriceList, PriceCharge, CHARGE_KINDS, rm } from '../../../../core/services/school-fees.service';
import { SchoolService } from '../../../../core/services/school.service';
import { ToastService } from '../../../../core/services/toast.service';

/**
 * School → Fees → Price lists: one per academic year ("Price & Terms 2027"). Each session's hours,
 * meals and monthly fee, and the other charges (one-time, twice a year, refundable deposit). A new
 * year is copied from the last one, so the office only changes what's new. Same as the app.
 */
@Component({
  selector: 'app-price-lists',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './price-lists.component.html',
  styleUrls: ['../../school-shared.scss', './price-lists.component.scss']
})
export class PriceListsComponent implements OnInit {
  private fees = inject(SchoolFeesService);
  private school = inject(SchoolService);
  private toast = inject(ToastService);
  private cdr = inject(ChangeDetectorRef);

  readonly rm = rm;
  readonly kinds = CHARGE_KINDS;
  readonly months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  lists: PriceList[] = [];
  loading = true;
  /** The price list being edited (a copy; saved with Save). */
  edit: PriceList | null = null;
  saving = false;
  error = '';

  // New year's price list
  showNew = false;
  newName = '';
  newFrom = '';
  newCopyFrom: number | null = null;

  ngOnInit(): void { this.load(); }

  load(selectId?: number): void {
    this.fees.getPriceLists().subscribe({
      next: l => {
        this.lists = l;
        this.loading = false;
        const pick = l.find(x => x.id === selectId) ?? l.find(x => x.current) ?? l[0];
        if (pick) this.select(pick);
        this.cdr.markForCheck();
      },
      error: err => { this.loading = false; this.toast.error('Price lists', err?.error?.message ?? 'Could not load.'); this.cdr.markForCheck(); }
    });
  }

  select(p: PriceList): void {
    this.edit = JSON.parse(JSON.stringify(p));
    this.error = '';
  }

  /** Not started yet: can still be deleted. */
  get future(): boolean { return !!this.edit && this.edit.effectiveFrom > new Date().toISOString().substring(0, 10); }

  // ── Twice-a-year months ──
  monthOn(m: number): boolean { return (this.edit?.twiceAYearMonths ?? '').split(',').map(Number).includes(m); }
  toggleMonth(m: number, on: boolean): void {
    if (!this.edit) return;
    const set = new Set((this.edit.twiceAYearMonths || '').split(',').filter(x => x).map(Number));
    if (on) set.add(m); else set.delete(m);
    this.edit.twiceAYearMonths = [...set].sort((a, b) => a - b).join(',');
  }

  // ── Charges ──
  addCharge(): void { this.edit?.charges.push({ name: '', kind: 'OneTime', amount: 0, sessionType: null }); }
  removeCharge(c: PriceCharge): void { if (this.edit) this.edit.charges = this.edit.charges.filter(x => x !== c); }

  /** What a new child of this session pays at registration / in the 2nd month (live, as you type). */
  upon(sessionType: string, fee: number): number {
    return (fee || 0) + (this.edit?.charges ?? []).filter(c => c.kind !== 'Deposit' && (!c.sessionType || c.sessionType === sessionType))
      .reduce((s, c) => s + (+c.amount || 0), 0);
  }
  second(sessionType: string, fee: number): number {
    return (fee || 0) + (this.edit?.charges ?? []).filter(c => c.kind === 'Deposit' && (!c.sessionType || c.sessionType === sessionType))
      .reduce((s, c) => s + (+c.amount || 0), 0);
  }

  save(): void {
    if (!this.edit) return;
    this.saving = true;
    this.error = '';
    const body: PriceList = {
      ...this.edit,
      sessions: this.edit.sessions.map(s => ({ ...s, monthlyFee: +s.monthlyFee || 0 })),
      charges: this.edit.charges.map(c => ({ ...c, amount: +c.amount || 0, sessionType: c.sessionType || null }))
    };
    this.fees.savePriceList(body).subscribe({
      next: p => {
        this.saving = false;
        this.toast.success('Price list saved', `${p.name}: invoices from ${p.effectiveFrom} use these prices.`);
        this.school.loadMe(true).subscribe();
        this.load(p.id);
      },
      error: err => { this.saving = false; this.error = err?.error?.message ?? 'Could not save.'; this.cdr.markForCheck(); }
    });
  }

  startNew(): void {
    const year = new Date().getFullYear() + 1;
    this.newName = String(year);
    this.newFrom = `${year - 1}-11-01`;
    this.newCopyFrom = this.lists.find(l => l.current)?.id ?? this.lists[0]?.id ?? null;
    this.showNew = true;
  }

  create(): void {
    if (!this.newName.trim() || !this.newFrom) return;
    this.fees.createPriceList(this.newName.trim(), this.newFrom, this.newCopyFrom).subscribe({
      next: p => { this.showNew = false; this.toast.success('Price list created', `Now change the ${p.name} prices and save.`); this.load(p.id); },
      error: err => this.toast.error('New price list', err?.error?.message ?? 'Could not create.')
    });
  }

  remove(): void {
    const p = this.edit;
    if (!p || !confirm(`Delete the ${p.name} price list?`)) return;
    this.fees.deletePriceList(p.id).subscribe({
      next: () => { this.toast.success('Deleted', p.name); this.edit = null; this.load(); },
      error: err => this.toast.error('Delete', err?.error?.message ?? 'Could not delete.')
    });
  }

  pdf(): void { if (this.edit) this.school.openBlob(this.fees.priceListPdf(this.edit.id)); }
}
