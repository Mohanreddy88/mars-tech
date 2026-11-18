import { Component, OnInit, ChangeDetectorRef } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import {
  StatutoryRateService, StatutoryRateSet, StatutoryRateSetRequest, StatutoryPreview, SocsoBand, TaxBand
} from '../../../../core/services/statutory-rate.service';
import { ToastService } from '../../../../core/services/toast.service';
import { ConfirmModalComponent } from '../../../../shared/components/confirm-modal/confirm-modal.component';

type EditorMode = 'create' | 'edit' | 'copy';

/**
 * Master → Statutory Rates: EPF, SOCSO, EIS and PCB rates by effective date.
 * Payroll uses the latest set that starts on or before the payroll month.
 */
@Component({
  selector: 'app-statutory-rates',
  standalone: true,
  imports: [CommonModule, FormsModule, ConfirmModalComponent],
  templateUrl: './statutory-rates-component.html',
  styleUrls: ['./statutory-rates-component.scss']
})
export class StatutoryRatesComponent implements OnInit {
  sets: StatutoryRateSet[] = [];
  loading = false;

  // Editor
  showEditor = false;
  mode: EditorMode = 'create';
  editId: number | null = null;
  editPayrollsUsing = 0;
  saving = false;
  editorError = '';
  form: StatutoryRateSetRequest = this.blank();

  // Try-a-salary preview
  previewWage = 5000;
  preview: StatutoryPreview | null = null;
  previewing = false;
  previewError = '';

  // Delete
  showConfirm = false;
  confirmMessage = '';
  pendingDelete: StatutoryRateSet | null = null;

  constructor(
    private service: StatutoryRateService,
    private toast: ToastService,
    private cdr: ChangeDetectorRef
  ) {}

  ngOnInit(): void { this.load(); }

  load(): void {
    this.loading = true;
    this.service.getAll().subscribe({
      next: (data) => { this.sets = data; this.loading = false; this.cdr.detectChanges(); },
      error: (err) => {
        this.loading = false;
        this.toast.error('Load Failed', err?.error?.message ?? 'Could not load statutory rates.');
        this.cdr.detectChanges();
      }
    });
  }

  get current(): StatutoryRateSet | undefined { return this.sets.find(s => s.isCurrent); }

  isUpcoming(s: StatutoryRateSet): boolean {
    return s.effectiveFrom.substring(0, 10) > new Date().toISOString().substring(0, 10);
  }

  // ── Editor ──────────────────────────────────────────────

  private blank(): StatutoryRateSetRequest {
    return {
      name: '', effectiveFrom: '', notes: '',
      epfEmployeeRate: 0, epfEmployerRate: 0, epfEmployerRateAboveThreshold: 0, epfEmployerThreshold: 5000,
      socsoBands: [{ upTo: null, employee: 0, employer: 0 }],
      eisEmployeeRate: 0, eisEmployerRate: 0, eisWageCeiling: 6000,
      taxPersonalRelief: 9000,
      taxBands: [{ upTo: null, rate: 0 }],
    };
  }

  private toForm(s: StatutoryRateSet): StatutoryRateSetRequest {
    return {
      name: s.name,
      effectiveFrom: s.effectiveFrom.substring(0, 10),
      notes: s.notes ?? '',
      epfEmployeeRate: s.epfEmployeeRate,
      epfEmployerRate: s.epfEmployerRate,
      epfEmployerRateAboveThreshold: s.epfEmployerRateAboveThreshold,
      epfEmployerThreshold: s.epfEmployerThreshold,
      socsoBands: s.socsoBands.map(b => ({ ...b })),
      eisEmployeeRate: s.eisEmployeeRate,
      eisEmployerRate: s.eisEmployerRate,
      eisWageCeiling: s.eisWageCeiling,
      taxPersonalRelief: s.taxPersonalRelief,
      taxBands: s.taxBands.map(b => ({ ...b })),
    };
  }

  /** New rates usually only change a few numbers, so a new set starts as a copy of the current one. */
  openCreate(): void {
    const base = this.current ?? this.sets[0];
    if (base) { this.openCopy(base); return; }
    this.open('create', null, this.blank(), 0);
  }

  openCopy(s: StatutoryRateSet): void {
    const f = this.toForm(s);
    f.name = '';
    f.effectiveFrom = '';
    f.notes = '';
    this.open('copy', null, f, 0);
  }

  openEdit(s: StatutoryRateSet): void {
    this.open('edit', s.id, this.toForm(s), s.payrollsUsing);
  }

  private open(mode: EditorMode, id: number | null, form: StatutoryRateSetRequest, using: number): void {
    this.mode = mode;
    this.editId = id;
    this.form = form;
    this.editPayrollsUsing = using;
    this.editorError = '';
    this.preview = null;
    this.previewError = '';
    this.showEditor = true;
  }

  closeEditor(): void { this.showEditor = false; }

  get editorTitle(): string {
    return this.mode === 'edit' ? 'Edit Rate Set' : 'New Rate Set';
  }

  addSocsoRow(): void {
    // Insert before the open-ended last row
    const rows = this.form.socsoBands;
    const lastBounded = [...rows].reverse().find(r => r.upTo != null)?.upTo ?? 0;
    rows.splice(Math.max(rows.length - 1, 0), 0, { upTo: lastBounded + 100, employee: 0, employer: 0 });
  }

  removeSocsoRow(i: number): void {
    if (this.form.socsoBands.length > 1) this.form.socsoBands.splice(i, 1);
  }

  addTaxRow(): void {
    const rows = this.form.taxBands;
    const lastBounded = [...rows].reverse().find(r => r.upTo != null)?.upTo ?? 0;
    rows.splice(Math.max(rows.length - 1, 0), 0, { upTo: lastBounded + 10000, rate: 0 });
  }

  removeTaxRow(i: number): void {
    if (this.form.taxBands.length > 1) this.form.taxBands.splice(i, 1);
  }

  /** Lower limit shown for a band row (previous row's "up to"). */
  bandFrom(rows: Array<SocsoBand | TaxBand>, i: number): number {
    return i === 0 ? 0 : (rows[i - 1].upTo ?? 0);
  }

  /** Numbers from inputs can arrive as strings or empty; send clean numbers, empty "up to" = open-ended. */
  private payload(): StatutoryRateSetRequest {
    const n = (v: any) => (v === '' || v == null || isNaN(+v)) ? 0 : +v;
    const up = (v: any) => (v === '' || v == null) ? null : +v;
    const f = this.form;
    return {
      name: (f.name ?? '').trim(),
      effectiveFrom: f.effectiveFrom,
      notes: (f.notes ?? '').trim() || null,
      epfEmployeeRate: n(f.epfEmployeeRate),
      epfEmployerRate: n(f.epfEmployerRate),
      epfEmployerRateAboveThreshold: n(f.epfEmployerRateAboveThreshold),
      epfEmployerThreshold: n(f.epfEmployerThreshold),
      socsoBands: f.socsoBands.map(b => ({ upTo: up(b.upTo), employee: n(b.employee), employer: n(b.employer) })),
      eisEmployeeRate: n(f.eisEmployeeRate),
      eisEmployerRate: n(f.eisEmployerRate),
      eisWageCeiling: n(f.eisWageCeiling),
      taxPersonalRelief: n(f.taxPersonalRelief),
      taxBands: f.taxBands.map(b => ({ upTo: up(b.upTo), rate: n(b.rate) })),
    };
  }

  save(): void {
    const body = this.payload();
    if (!body.name) { this.editorError = 'Give the rate set a name, e.g. "2027 rates".'; return; }
    if (!body.effectiveFrom) { this.editorError = 'Choose the date these rates start.'; return; }

    this.saving = true;
    this.editorError = '';
    const req$ = this.mode === 'edit' && this.editId != null
      ? this.service.update(this.editId, body)
      : this.service.create(body);

    req$.subscribe({
      next: () => {
        this.saving = false;
        this.toast.success('Rates Saved', `"${body.name}" applies to payrolls from ${this.formatDate(body.effectiveFrom)}.`);
        this.showEditor = false;
        this.load();
      },
      error: (err) => {
        this.saving = false;
        this.editorError = err?.error?.message ?? 'Could not save the rate set.';
        this.cdr.detectChanges();
      }
    });
  }

  runPreview(): void {
    const wage = +this.previewWage;
    if (!wage || wage < 0) { this.previewError = 'Enter a monthly salary.'; return; }
    this.previewing = true;
    this.previewError = '';
    this.service.preview(this.payload(), wage).subscribe({
      next: (p) => { this.preview = p; this.previewing = false; this.cdr.detectChanges(); },
      error: (err) => {
        this.previewing = false;
        this.preview = null;
        this.previewError = err?.error?.message ?? 'Could not calculate.';
        this.cdr.detectChanges();
      }
    });
  }

  // ── Delete ──────────────────────────────────────────────

  askDelete(s: StatutoryRateSet): void {
    this.pendingDelete = s;
    this.confirmMessage = s.payrollsUsing > 0
      ? `Delete "${s.name}"? ${s.payrollsUsing} payroll(s) were calculated with it; they keep their amounts, but future payrolls for those months will use the previous rate set.`
      : `Delete "${s.name}"? Payrolls from ${this.formatDate(s.effectiveFrom)} will use the previous rate set.`;
    this.showConfirm = true;
  }

  onConfirmDelete(): void {
    const s = this.pendingDelete;
    this.showConfirm = false;
    if (!s) return;
    this.service.delete(s.id).subscribe({
      next: () => { this.toast.success('Deleted', `"${s.name}" was removed.`); this.pendingDelete = null; this.load(); },
      error: (err) => { this.toast.error('Delete Failed', err?.error?.message ?? 'Could not delete.'); this.pendingDelete = null; }
    });
  }

  onCancelDelete(): void { this.pendingDelete = null; this.showConfirm = false; }

  formatDate(d: string): string {
    if (!d) return '';
    const [y, m, day] = d.substring(0, 10).split('-').map(Number);
    return new Date(y, m - 1, day).toLocaleDateString('en-GB', { day: '2-digit', month: 'short', year: 'numeric' });
  }
}
