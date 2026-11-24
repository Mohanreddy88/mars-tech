import { ChangeDetectorRef, Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { SchoolFeesService, PriceList, rm } from '../../../../core/services/school-fees.service';
import { SchoolService } from '../../../../core/services/school.service';

/**
 * "Price &amp; Terms 2027" for parents: each session's hours, meals and monthly fee, the charges at
 * registration and the deposit, and the terms — from the price list in force. With the PDF.
 */
@Component({
  selector: 'app-price-terms',
  standalone: true,
  imports: [CommonModule],
  template: `
    @if (list) {
      <section class="pt-card">
        <header>
          <div><h4>Price &amp; Terms, {{ list.name }}</h4><small>From {{ list.effectiveFrom | date: 'd MMMM yyyy' }}</small></div>
          <button class="btn btn-sm btn-outline-primary" (click)="pdf()"><i class="bi bi-file-earmark-pdf"></i> PDF</button>
        </header>
        <div class="table-responsive">
          <table class="table align-middle mb-0">
            <thead><tr><th></th>@for (s of sessions; track s.sessionType) { <th class="text-end">{{ s.sessionType }}</th> }</tr></thead>
            <tbody>
              <tr><td>Hours</td>@for (s of sessions; track s.sessionType) { <td class="text-end">{{ s.start }} – {{ s.end }}</td> }</tr>
              <tr class="strong"><td>Monthly school fees</td>@for (s of sessions; track s.sessionType) { <td class="text-end">{{ rm(s.monthlyFee) }}</td> }</tr>
              <tr><td>Meals included</td>@for (s of sessions; track s.sessionType) { <td class="text-end">{{ s.mealsIncluded ?? '—' }}</td> }</tr>
              @for (c of firstTime; track $index) {
                <tr><td>{{ c.name }}{{ c.kind === 'TwiceAYear' ? ' (twice a year)' : '' }}</td>
                  @for (s of sessions; track s.sessionType) { <td class="text-end">{{ applies(c.sessionType, s.sessionType) ? rm(c.amount) : 'n.a.' }}</td> }</tr>
              }
              <tr class="strong"><td>Total upon registration</td>@for (s of sessions; track s.sessionType) { <td class="text-end">{{ rm(s.uponRegistration ?? 0) }}</td> }</tr>
              @if (deposits.length) {
                @for (d of deposits; track $index) {
                  <tr><td>{{ d.name }} (refundable, 2nd month)</td>
                    @for (s of sessions; track s.sessionType) { <td class="text-end">{{ applies(d.sessionType, s.sessionType) ? rm(d.amount) : 'n.a.' }}</td> }</tr>
                }
                <tr class="strong"><td>2nd month payable</td>@for (s of sessions; track s.sessionType) { <td class="text-end">{{ rm(s.secondMonth ?? 0) }}</td> }</tr>
              }
            </tbody>
          </table>
        </div>
        @if (list.terms) { <p class="terms">{{ list.terms }}</p> }
      </section>
    }
  `,
  styles: [`
    .pt-card { background: #fff; border: 1px solid #e5e7eb; border-radius: 14px; padding: 16px; margin-bottom: 18px; }
    header { display: flex; justify-content: space-between; align-items: flex-start; gap: 10px; margin-bottom: 8px;
      h4 { margin: 0; font-size: 18px; font-weight: 700; } small { color: #6b7280; } }
    tr.strong td { font-weight: 700; }
    .terms { margin: 10px 0 0; font-size: 13px; color: #4b5563; white-space: pre-line; }
  `]
})
export class PriceTermsComponent implements OnInit {
  private fees = inject(SchoolFeesService);
  private school = inject(SchoolService);
  private cdr = inject(ChangeDetectorRef);

  readonly rm = rm;
  list: PriceList | null = null;

  get sessions() { return (this.list?.sessions ?? []).filter(s => s.offered); }
  get firstTime() { return (this.list?.charges ?? []).filter(c => c.kind !== 'Deposit'); }
  get deposits() { return (this.list?.charges ?? []).filter(c => c.kind === 'Deposit'); }

  applies(chargeSession: string | null, session: string): boolean { return !chargeSession || chargeSession === session; }

  ngOnInit(): void {
    this.fees.currentPriceList().subscribe({ next: l => { this.list = l; this.cdr.markForCheck(); }, error: () => {} });
  }

  pdf(): void { if (this.list) this.school.openBlob(this.fees.priceListPdf(this.list.id)); }
}
