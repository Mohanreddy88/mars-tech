import { Component, OnInit, ChangeDetectorRef } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';
import { ReportsService, MonthlySummary } from '../../../../core/services/reports.service';

/** Insights › Reports › Monthly Summary: one month's payroll and attendance at a glance. */
@Component({
  selector: 'app-monthly-summary',
  standalone: true,
  imports: [CommonModule, FormsModule, RouterLink],
  templateUrl: './monthly-summary.component.html',
  styleUrl: './monthly-summary.component.scss'
})
export class MonthlySummaryComponent implements OnInit {
  readonly months = ['January', 'February', 'March', 'April', 'May', 'June',
                     'July', 'August', 'September', 'October', 'November', 'December'];
  years: number[] = [];
  month = new Date().getMonth() + 1;
  year = new Date().getFullYear();

  summary: MonthlySummary | null = null;
  loading = false;
  error = '';

  constructor(private reports: ReportsService, private cdr: ChangeDetectorRef) {
    const y = new Date().getFullYear();
    for (let i = y + 1; i >= y - 5; i--) this.years.push(i);
  }

  ngOnInit(): void { this.load(); }

  load(): void {
    this.loading = true;
    this.error = '';
    this.reports.getMonthlySummary(Number(this.year), Number(this.month)).subscribe({
      next: (s) => { this.summary = s; this.loading = false; this.cdr.detectChanges(); },
      error: (e) => {
        this.summary = null;
        this.loading = false;
        this.error = e?.error?.message || 'Could not load the summary.';
        this.cdr.detectChanges();
      }
    });
  }

  /** Deductions withheld from employees (EPF, SOCSO, EIS, PCB). */
  get statutoryTotal(): number {
    const p = this.summary?.payroll;
    return p ? p.totalEpf + p.totalSocso + (p.totalEis ?? 0) + p.totalTax : 0;
  }

  /** Share of working days that were full days. */
  get attendanceRate(): number | null {
    const a = this.summary?.attendance;
    return a && a.totalRecords > 0 ? Math.round((a.presentCount / a.totalRecords) * 1000) / 10 : null;
  }
}
