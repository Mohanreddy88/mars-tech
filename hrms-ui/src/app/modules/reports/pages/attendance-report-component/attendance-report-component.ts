import { Component, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { Router } from '@angular/router';
import { FormsModule } from '@angular/forms';
import { ReportsService, AttendanceReport } from '../../../../core/services/reports.service';
import { LoadingService } from '../../../../core/services/loading.service';
import { ToastService } from '../../../../core/services/toast.service';

@Component({
  selector: 'app-attendance-report',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './attendance-report-component.html',
  styleUrl: './attendance-report-component.scss'
})
export class AttendanceReportComponent implements OnInit {
  startDate: string = '';
  endDate: string = '';
  /** 'YYYY-MM' — picking a month fills the whole month into the date range */
  month: string = '';
  reportData: AttendanceReport | null = null;

  constructor(
    private reportsService: ReportsService,
    private loadingService: LoadingService,
    private toast: ToastService
  ,
    private router: Router
  ) {
    // Default: the whole current month
    const today = new Date();
    this.month = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, '0')}`;
    this.applyMonthRange();
  }

  /** Month picked → start = 1st, end = last day of that month, and reload */
  onMonthChange(): void {
    if (!this.month) return;
    this.applyMonthRange();
    this.loadReport();
  }

  /** Dates edited by hand → no longer a single month */
  onDateChange(): void {
    this.month = '';
  }

  private applyMonthRange(): void {
    const [y, m] = this.month.split('-').map(Number);
    if (!y || !m) return;
    this.startDate = this.formatDate(new Date(y, m - 1, 1));
    this.endDate = this.formatDate(new Date(y, m, 0)); // day 0 of next month = last day of this month
  }

  isNonWorking(status: string): boolean {
    return status === 'Weekend' || status === 'Holiday';
  }

  ngOnInit(): void {
    this.loadReport();
  }

  formatDate(date: Date): string {
    const year = date.getFullYear();
    const month = String(date.getMonth() + 1).padStart(2, '0');
    const day = String(date.getDate()).padStart(2, '0');
    return `${year}-${month}-${day}`;
  }

  loadReport(): void {
    if (!this.startDate || !this.endDate) {
      this.toast.warning('Missing Dates', 'Please select both start and end dates');
      return;
    }

    this.loadingService.show();
    this.reportsService.getAttendanceByDateRange(this.startDate, this.endDate)
      .subscribe({
        next: (data) => {
          this.reportData = data;
          this.loadingService.hide();
        },
        error: () => {
          this.loadingService.hide();
          this.toast.error('Load Failed', 'Failed to load attendance report');
        }
      });
  }

  exportToExcel(): void {
    if (!this.startDate || !this.endDate) {
      this.toast.warning('Missing Dates', 'Please select both start and end dates');
      return;
    }

    this.loadingService.show();
    this.reportsService.exportAttendanceToExcel(this.startDate, this.endDate)
      .subscribe({
        next: (blob) => {
          const fileName = `Attendance_${this.startDate}_to_${this.endDate}.xlsx`;
          this.reportsService.downloadFile(blob, fileName);
          this.loadingService.hide();
        },
        error: () => {
          this.loadingService.hide();
          this.toast.error('Export Failed', 'Failed to export attendance data');
        }
      });
  }

  getStatusClass(status: string): string {
    const statusMap: { [key: string]: string } = {
      'Present': 'status-present',
      'Absent': 'status-absent',
      'Leave': 'status-leave',
      'HalfDay': 'status-halfday',
      'Weekend': 'status-weekend',
      'Holiday': 'status-holiday'
    };
    return statusMap[status] || '';
  }

  backToHome(): void {
    this.router.navigate(['/home']);
  }
}
