import { Component, OnInit, Input, ChangeDetectorRef, ElementRef } from '@angular/core';
import { Router, RouterModule, NavigationEnd } from '@angular/router';
import { CommonModule } from '@angular/common';
import { HttpClient } from '@angular/common/http';
import { AuthService } from '../../../core/services/auth.service';
import { filter } from 'rxjs/operators';
import { environment } from '../../../../environments/environment';
import { CompanySettingsService, CompanyBranding } from '../../../core/services/company-settings.service';
import { SchoolService, SchoolMe } from '../../../core/services/school.service';

@Component({
  selector: 'app-sidebar-component',
  standalone: true,
  imports: [RouterModule, CommonModule],
  templateUrl: './sidebar-component.html',
  styleUrl: './sidebar-component.scss'
})
export class SidebarComponent implements OnInit {
  isAdmin = false;
  masterMenuOpen = false;
  payrollMenuOpen = false;
  attendanceMenuOpen = false;
  leaveMenuOpen = false;
  reportsMenuOpen = false;
  selfServiceMenuOpen = false;
  schoolMenuOpen = false;

  /** Parent login (school features): gets the parent portal menu only. */
  isParent = false;
  /** School features for this login (null until loaded, or when they don't apply). */
  school: SchoolMe | null = null;
  unreadMessages = 0;
  unreadAnnouncements = 0;

  @Input() isMobileMenuOpen = false;
  pendingLeaveCount = 0;
  branding: CompanyBranding | null = null;

  constructor(
    private authService: AuthService,
    private router: Router,
    private http: HttpClient,
    private companySettings: CompanySettingsService,
    private schoolService: SchoolService,
    private cdr: ChangeDetectorRef,
    private host: ElementRef<HTMLElement>
  ) {}

  ngOnInit(): void {
    const user = this.authService.getUser();
    this.isAdmin = user?.role === 'Admin';
    this.isParent = user?.role === 'Parent';

    // School menu items (classes, children, parents, messages) when the company uses them
    this.schoolService.me$.subscribe(me => { this.school = me?.enabled ? me : null; this.cdr.markForCheck(); });
    this.schoolService.unreadMessages$.subscribe(n => { this.unreadMessages = n; this.cdr.markForCheck(); });
    this.schoolService.unreadAnnouncements$.subscribe(n => { this.unreadAnnouncements = n; this.cdr.markForCheck(); });
    this.schoolService.loadMe().subscribe();

    // Company name/logo for the sidebar header
    this.companySettings.branding$.subscribe(b => { this.branding = b; this.cdr.markForCheck(); });
    this.companySettings.loadBranding();

    // Load pending leave count for admin badge
    if (this.isAdmin) {
      this.loadPendingLeaveCount();
    }

    // Auto-expand menu based on current route
    this.updateMenuStateFromRoute(this.router.url);
    this.scrollActiveIntoView();

    // Listen to route changes and keep menus open
    this.router.events
      .pipe(filter(event => event instanceof NavigationEnd))
      .subscribe((event: any) => {
        this.updateMenuStateFromRoute(event.url);
        this.scrollActiveIntoView();
      });
  }

  /** The menu scrolls on its own; keep the item for the current page visible (e.g. Master → Departments). */
  private scrollActiveIntoView(): void {
    // Wait for the submenu to render and routerLinkActive to mark the item
    setTimeout(() => {
      const active = this.host.nativeElement.querySelector<HTMLElement>('.active-submenu, .active-menu');
      active?.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
    }, 50);
  }

  /** After opening a group, scroll so its whole submenu is visible (as far as the menu height allows). */
  private revealSubmenu(event?: Event, opened?: boolean): void {
    const header = event?.currentTarget as HTMLElement | null;
    if (!opened || !header) return;
    setTimeout(() => {
      const submenu = header.nextElementSibling as HTMLElement | null;
      const target = submenu?.classList.contains('submenu') ? submenu : header;
      target.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
    }, 0);
  }

  private loadPendingLeaveCount(): void {
    this.http.get<any[]>(`${environment.apiUrl}/leavemanagement/requests`).subscribe({
      next: (data) => {
        this.pendingLeaveCount = data.filter(r => r.status === 'Pending').length;
      },
      error: () => { this.pendingLeaveCount = 0; }
    });
  }

  private updateMenuStateFromRoute(url: string): void {
    // Keep Payroll menu open if on any payroll route
    if (url.includes('/payroll')) {
      this.payrollMenuOpen = true;
    }
    // Keep Attendance menu open if on any attendance route
    if (url.includes('/attendance')) {
      this.attendanceMenuOpen = true;
    }
    // Keep Master menu open if on any master route
    if (url.includes('/master')) {
      this.masterMenuOpen = true;
    }
    // Keep Leave menu open if on any leave route
    if (url.includes('/leave')) {
      this.leaveMenuOpen = true;
    }
    // Keep Reports menu open if on any reports route
    if (url.includes('/reports') || url.includes('/analytics') || url.includes('/audit')) {   // Insights group
      this.reportsMenuOpen = true;
    }
    if (url.includes('/school/')) {
      this.schoolMenuOpen = true;
    }
    // Keep Self-Service menu open if on any self-service route
    if (url.includes('/self-service')) {
      this.selfServiceMenuOpen = true;
    }
  }

  toggleMasterMenu(event?: Event): void {
    this.masterMenuOpen = !this.masterMenuOpen;
    this.revealSubmenu(event, this.masterMenuOpen);
  }

  togglePayrollMenu(event?: Event): void {
    this.payrollMenuOpen = !this.payrollMenuOpen;
    this.revealSubmenu(event, this.payrollMenuOpen);
  }

  toggleAttendanceMenu(event?: Event): void {
    this.attendanceMenuOpen = !this.attendanceMenuOpen;
    this.revealSubmenu(event, this.attendanceMenuOpen);
  }

  toggleLeaveMenu(event?: Event): void {
    this.leaveMenuOpen = !this.leaveMenuOpen;
    this.revealSubmenu(event, this.leaveMenuOpen);
  }

  toggleReportsMenu(event?: Event): void {
    this.reportsMenuOpen = !this.reportsMenuOpen;
    this.revealSubmenu(event, this.reportsMenuOpen);
  }

  toggleSchoolMenu(event?: Event): void {
    this.schoolMenuOpen = !this.schoolMenuOpen;
    this.revealSubmenu(event, this.schoolMenuOpen);
  }

  toggleSelfServiceMenu(): void {
    this.selfServiceMenuOpen = !this.selfServiceMenuOpen;
  }
}
