import { Component, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { Router, RouterModule } from '@angular/router';
import { HttpClient } from '@angular/common/http';
import { forkJoin, of, Observable } from 'rxjs';
import { catchError } from 'rxjs/operators';
import { environment } from '../../../../../environments/environment';
import { photoUrl } from '../../../../core/utils/photo-url';
import { ReportsService } from '../../../../core/services/reports.service';
import { ToastService } from '../../../../core/services/toast.service';
import { HighlightsCarouselComponent } from '../../../../shared/components/highlights-carousel/highlights-carousel.component';

/** One month in the payroll trend (from /analytics/payroll-trends). */
interface PayrollTrendPoint { year: number; month: number; monthName: string; totalNet: number; totalGross: number; employeeCount: number; }

/** A birthday (day and month only — no year or age). */
interface BirthdayItem {
  id: number; name: string; employeeCode: string; profilePicture: string | null;
  department: string | null; birthday: string; daysUntil?: number; daysAgo?: number;
}

interface HolidayItem { id: number; name: string; date: string; isNational: boolean; state?: string; }

interface AuditItem { id: number; username: string; action: string; entityType: string; description: string; createdAt: string; }

interface AdminDashboardData {
  stats: {
    totalEmployees: number;
    activeEmployees: number;
    inactiveEmployees: number;
    totalDepartments: number;
    pendingApprovals: number;
    pendingLeaves: number;
    pendingAttendance: number;
    pendingTimesheets: number;
    currentMonthPayrolls: number;
    currentMonthPayrollAmount: number;
  };
  pendingCounts: {
    leaveRequests: number;
    attendancePeriods: number;
    timesheets: number;
    total: number;
  };
  recentLeaveRequests: Array<{
    id: number;
    employeeName: string;
    employeeCode: string;
    leaveType: string;
    leaveTypeCode: string;
    startDate: string;
    endDate: string;
    totalDays: number;
    status: string;
    requestedOn: string;
  }>;
  recentAttendance: Array<{
    id: number;
    employeeName: string;
    employeeCode: string;
    startDate: string;
    endDate: string;
    periodLabel: string;
    status: string;
    submittedAt: string;
  }>;
  currentMonthPayrolls: Array<{
    status: string;
    count: number;
    totalAmount: number;
  }>;
  departmentStats: Array<{
    departmentName: string;
    employeeCount: number;
  }>;
  leaveUsageStats: Array<{
    leaveType: string;
    leaveTypeCode: string;
    totalDays: number;
    requestCount: number;
  }>;
  recentActivities: Array<{
    type: string;
    employeeName: string;
    description: string;
    timestamp: string;
    icon: string;
  }>;
}

@Component({
  selector: 'app-admin-dashboard',
  standalone: true,
  imports: [CommonModule, RouterModule, HighlightsCarouselComponent],
  templateUrl: './admin-dashboard-component.html',
  styleUrls: ['./admin-dashboard-component.scss']
})
export class AdminDashboardComponent implements OnInit {
  dashboardData: AdminDashboardData | null = null;
  loading = true;
  error = '';
  currentYear = new Date().getFullYear();
  currentMonth = new Date().toLocaleDateString('en-US', { month: 'long', year: 'numeric' });

  // ── Insights & People (each loads on its own; a failure just hides that card's data) ──
  payrollTrend: PayrollTrendPoint[] = [];
  attendanceRate: number | null = null;     // this month, % of recorded days that were full days
  attendanceRecords = 0;
  latestChanges: AuditItem[] = [];
  upcomingBirthdays: BirthdayItem[] = [];
  upcomingHolidays: HolidayItem[] = [];
  extrasLoaded = false;
  downloading: 'payroll' | 'employees' | null = null;
  readonly photoUrl = photoUrl;

  constructor(
    private http: HttpClient,
    private router: Router,
    private reports: ReportsService,
    private toast: ToastService
  ) {}

  ngOnInit(): void {
    this.loadDashboard();
    this.loadExtras();
  }

  /** Insights and People cards: trend, attendance rate, latest changes, birthdays, holidays. */
  loadExtras(): void {
    const api = environment.apiUrl;
    const now = new Date();
    const y = now.getFullYear(), m = now.getMonth() + 1;
    const safe = <T>(obs: Observable<T>, fallback: T) => obs.pipe(catchError(() => of(fallback)));

    forkJoin({
      trend:     safe(this.http.get<PayrollTrendPoint[]>(`${api}/analytics/payroll-trends?months=6`), []),
      att:       safe(this.http.get<{ totalRecords: number; presentCount: number } | null>(`${api}/analytics/attendance-statistics?year=${y}&month=${m}`), null),
      audit:     safe(this.http.get<{ logs: AuditItem[] } | null>(`${api}/audit?page=1&pageSize=5`), null),
      birthdays: safe(this.http.get<{ upcoming: BirthdayItem[] } | null>(`${api}/dashboard/birthdays`), null),
      holidays:  safe(this.http.get<HolidayItem[]>(`${api}/publicholidays?year=${y}`), []),
      nextYear:  safe(this.http.get<HolidayItem[]>(`${api}/publicholidays?year=${y + 1}`), []),
    }).subscribe(r => {
      this.payrollTrend = (r.trend ?? []).slice(-6);
      if (r.att && r.att.totalRecords > 0) {
        this.attendanceRecords = r.att.totalRecords;
        this.attendanceRate = Math.round((r.att.presentCount / r.att.totalRecords) * 1000) / 10;
      }
      this.latestChanges = r.audit?.logs ?? [];
      this.upcomingBirthdays = (r.birthdays?.upcoming ?? []).slice(0, 5);
      const today = new Date(); today.setHours(0, 0, 0, 0);
      this.upcomingHolidays = [...(r.holidays ?? []), ...(r.nextYear ?? [])]
        .filter(h => new Date(h.date) >= today)
        .sort((a, b) => a.date.localeCompare(b.date))
        .slice(0, 5);
      this.extrasLoaded = true;
    });
  }

  /** Height (%) of a month's bar in the payroll trend. */
  trendHeight(p: PayrollTrendPoint): number {
    const max = Math.max(...this.payrollTrend.map(x => x.totalNet), 1);
    return Math.max(4, Math.round((p.totalNet / max) * 100));
  }

  shortMonth(p: PayrollTrendPoint): string {
    return new Date(p.year, p.month - 1, 1).toLocaleDateString('en-GB', { month: 'short' });
  }

  birthdayLabel(b: BirthdayItem): string {
    return b.daysUntil === 0 ? 'Today' : b.daysUntil === 1 ? 'Tomorrow' : `in ${b.daysUntil} days`;
  }

  daysUntil(date: string): string {
    const d = new Date(date); d.setHours(0, 0, 0, 0);
    const t = new Date(); t.setHours(0, 0, 0, 0);
    const n = Math.round((d.getTime() - t.getTime()) / 86_400_000);
    return n === 0 ? 'Today' : n === 1 ? 'Tomorrow' : `in ${n} days`;
  }

  initial(name: string): string { return (name || '?').charAt(0).toUpperCase(); }

  /** Quick downloads (Excel): this month's payroll, or the employee list. */
  download(kind: 'payroll' | 'employees'): void {
    const now = new Date();
    const req = kind === 'payroll'
      ? this.reports.exportPayrollToExcel(now.getFullYear(), now.getMonth() + 1)
      : this.reports.exportEmployeesToExcel();
    const name = kind === 'payroll'
      ? `Payroll_${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}.xlsx`
      : `Employees_${now.toISOString().substring(0, 10)}.xlsx`;
    this.downloading = kind;
    req.subscribe({
      next: (blob) => {
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url; a.download = name; a.click();
        setTimeout(() => URL.revokeObjectURL(url), 10_000);
        this.downloading = null;
      },
      error: () => { this.downloading = null; this.toast.error('Download Failed', 'Could not create the file. Please try again.'); }
    });
  }

  loadDashboard(): void {
    this.loading = true;
    this.error = '';

    this.http.get<AdminDashboardData>(`${environment.apiUrl}/dashboard/admin`).subscribe({
      next: (data) => {
        this.dashboardData = data;
        this.loading = false;
        console.log('✓ Admin dashboard loaded:', data);
      },
      error: (err) => {
        console.error('✗ Failed to load admin dashboard:', err);
        this.error = err.error?.message || 'Failed to load dashboard data';
        this.loading = false;
      }
    });
  }

  /** Accepts a path with a query string, e.g. "/leave/requests?status=Pending". */
  navigateTo(route: string): void {
    this.router.navigateByUrl(route);
  }

  /** "Pending Approvals" number: open the first list that has something waiting. */
  openPending(): void {
    const p = this.dashboardData?.pendingCounts;
    if ((p?.leaveRequests ?? 0) > 0) this.navigateTo('/leave/requests?status=Pending');
    else if ((p?.attendancePeriods ?? 0) > 0) this.navigateTo('/attendance/approval');
    else if ((p?.timesheets ?? 0) > 0) this.navigateTo('/timesheets');
    else this.navigateTo('/attendance/approval');   // nothing waiting: open the approvals page anyway
  }

  formatDate(dateStr: string): string {
    return new Date(dateStr).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' });
  }

  formatDateTime(dateStr: string): string {
    return new Date(dateStr).toLocaleDateString('en-US', { 
      month: 'short', 
      day: 'numeric', 
      hour: '2-digit', 
      minute: '2-digit' 
    });
  }

  getStatusClass(status: string): string {
    const statusMap: { [key: string]: string } = {
      'Pending': 'status-pending',
      'Submitted': 'status-submitted',
      'Approved': 'status-approved',
      'Rejected': 'status-rejected',
      'Draft': 'status-draft'
    };
    return statusMap[status] || 'status-default';
  }

  getLeaveTypeColor(code: string): string {
    const colors: { [key: string]: string } = {
      'AL': '#3b82f6',
      'ML': '#8b5cf6',
      'EL': '#ef4444',
      'CL': '#10b981',
      'MTL': '#f59e0b',
      'PTL': '#ec4899',
      'UL': '#6b7280',
      'SL': '#06b6d4',
      'HL': '#84cc16',
      'RL': '#a855f7'
    };
    return colors[code] || '#6b7280';
  }

  getActivityIcon(type: string): string {
    const icons: { [key: string]: string } = {
      'leave_approval': 'calendar-check',
      'attendance_approval': 'clock-history',
      'payroll_generated': 'cash-stack',
      'employee_created': 'person-plus'
    };
    return icons[type] || 'info-circle';
  }
}
