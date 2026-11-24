import { Routes } from '@angular/router';
import { inject } from '@angular/core';
import { AuthService } from './core/services/auth.service';

/** Landing page after login: admins → Dashboard, employees → their own dashboard. */
const landingPage = () => {
  const auth = inject(AuthService);
  return auth.isAdmin() ? '/dashboard' : auth.getRole() === 'Parent' ? '/parent' : '/self-service/dashboard';
};
import { authGuard } from './core/guards/auth.guard';
import { adminGuard } from './core/guards/admin.guard';
import { AdminLayoutComponent } from './layouts/admin-layout-component/admin-layout-component';
import { LoginComponent } from './modules/auth/pages/login/login.component';
import { ForgotPasswordComponent } from './modules/auth/pages/forgot-password/forgot-password.component';
import { ResetPasswordComponent } from './modules/auth/pages/reset-password/reset-password.component';
import { DashboardComponent } from './modules/dashboard/pages/dashboard-component/dashboard-component';
import { EmployeeListComponent } from './modules/employees/pages/employee-list-component/employee-list-component';
import { EmployeeFormComponent } from './modules/employees/pages/employee-form-component/employee-form-component';
import { AttendanceListComponent } from './modules/attendance/pages/attendance-list-component/attendance-list-component';
import { AttendanceApprovalComponent } from './modules/attendance/pages/attendance-approval-component/attendance-approval-component';
import { PayrollGenerateComponent } from './modules/payroll/pages/payroll-generate-component/payroll-generate-component';
import { PayrollListComponent } from './modules/payroll/pages/payroll-list-component/payroll-list-component';
import { SalaryReleaseComponent } from './modules/payroll/pages/salary-release-component/salary-release-component';
import { YearEndReportsComponent } from './modules/payroll/pages/year-end-reports-component/year-end-reports-component';
import { UserListComponent } from './modules/users/pages/user-list-component/user-list-component';
import { DepartmentListComponent } from './modules/master/pages/department-list-component/department-list-component';
import { BankListComponent } from './modules/master/pages/bank-list-component/bank-list-component';
import { TimesheetListComponent } from './modules/timesheets/pages/timesheet-list-component/timesheet-list-component';
import { LeaveBalanceComponent } from './modules/leave/pages/leave-balance-component/leave-balance-component';
import { LeaveRequestFormComponent } from './modules/leave/pages/leave-request-form-component/leave-request-form-component';
import { LeaveRequestListComponent } from './modules/leave/pages/leave-request-list-component/leave-request-list-component';
import { ReportsDashboardComponent } from './modules/reports/pages/reports-dashboard-component/reports-dashboard-component';
import { MonthlySummaryComponent } from './modules/reports/pages/monthly-summary-component/monthly-summary.component';
import { PayrollReportComponent } from './modules/reports/pages/payroll-report-component/payroll-report-component';
import { AttendanceReportComponent } from './modules/reports/pages/attendance-report-component/attendance-report-component';
import { EmployeeDirectoryComponent } from './modules/reports/pages/employee-directory-component/employee-directory-component';
import { MyProfileComponent } from './modules/self-service/pages/my-profile-component/my-profile-component';
import { MyPayslipsComponent } from './modules/self-service/pages/my-payslips-component/my-payslips-component';
import { MyAttendanceComponent } from './modules/self-service/pages/my-attendance-component/my-attendance-component';
import { MyLeaveComponent } from './modules/self-service/pages/my-leave-component/my-leave-component';
import { MyTimesheetComponent } from './modules/self-service/pages/my-timesheet-component/my-timesheet-component';
import { ChangePasswordComponent } from './modules/self-service/pages/change-password-component/change-password-component';
import { EmployeeDashboardComponent } from './modules/dashboard/pages/employee-dashboard-component/employee-dashboard-component';
import { AdminDashboardComponent } from './modules/dashboard/pages/admin-dashboard-component/admin-dashboard-component';
import { AnalyticsComponent } from './modules/analytics/pages/analytics-component/analytics-component';
import { PublicHolidaysComponent } from './modules/master/pages/public-holidays-component/public-holidays-component';
import { CompanySettingsComponent } from './modules/master/pages/company-settings-component/company-settings-component';
import { StatutoryRatesComponent } from './modules/master/pages/statutory-rates-component/statutory-rates-component';
import { PrivacyPolicyComponent } from './modules/legal/privacy-policy.component';
import { TermsOfUseComponent } from './modules/legal/terms-of-use.component';
import { NotificationsPageComponent } from './modules/notifications/pages/notifications-page/notifications-page.component';
import { AuditLogComponent } from './modules/audit/pages/audit-log-component/audit-log-component';
import { ChangePasswordComponent as ForceChangePasswordComponent } from './modules/auth/pages/change-password/change-password.component';
import { PlatformLoginComponent } from './modules/platform/platform-login/platform-login.component';
import { PlatformPortalComponent } from './modules/platform/platform-portal/platform-portal.component';
import { superAdminGuard } from './core/guards/super-admin.guard';
import { isPlatformHost } from './core/services/platform.service';
import { parentAreaGuard, parentOnlyGuard } from './core/guards/parent.guard';
// School pages load on demand (only schools use them)
const schoolClasses       = () => import('./modules/school/pages/school-classes/school-classes.component').then(m => m.SchoolClassesComponent);
const schoolStudents      = () => import('./modules/school/pages/school-students/school-students.component').then(m => m.SchoolStudentsComponent);
const schoolParents       = () => import('./modules/school/pages/school-parents/school-parents.component').then(m => m.SchoolParentsComponent);
const schoolFamilies      = () => import('./modules/school/pages/school-families/school-families.component').then(m => m.SchoolFamiliesComponent);
const schoolBanners       = () => import('./modules/school/pages/school-banners/school-banners.component').then(m => m.SchoolBannersComponent);
const schoolPickupPeople  =() => import('./modules/school/pages/school-pickup-people/school-pickup-people.component').then(m => m.SchoolPickupPeopleComponent);
const schoolAnnouncements = () => import('./modules/school/pages/school-announcements/school-announcements.component').then(m => m.SchoolAnnouncementsComponent);
const schoolMessages      = () => import('./modules/school/pages/school-messages/school-messages.component').then(m => m.SchoolMessagesComponent);
const schoolAttendance    = () => import('./modules/school/pages/school-attendance/school-attendance.component').then(m => m.SchoolAttendanceComponent);
const schoolFees          = () => import('./modules/school/pages/school-fees/school-fees.component').then(m => m.SchoolFeesComponent);
const parentChild         = () => import('./modules/school/pages/parent-child/parent-child.component').then(m => m.ParentChildComponent);
const parentFees          = () => import('./modules/school/pages/parent-fees/parent-fees.component').then(m => m.ParentFeesComponent);
const parentHome          = () => import('./modules/school/pages/parent-home/parent-home.component').then(m => m.ParentHomeComponent);
const parentAccount       = () => import('./modules/school/pages/parent-account/parent-account.component').then(m => m.ParentAccountComponent);

/** A company's own site (esync.marshrms.com …). */
const companyRoutes: Routes = [
  {
    path: 'login',
    component: LoginComponent
  },
  {
    path: 'change-password',
    component: ForceChangePasswordComponent
  },
  {
    path: 'forgot-password',
    component: ForgotPasswordComponent
  },
  {
    path: 'reset-password',
    component: ResetPasswordComponent
  },
  // Public legal pages (no login), linked from the footer
  { path: 'privacy', component: PrivacyPolicyComponent, title: 'Privacy Policy · MarsHRMS' },
  { path: 'terms',   component: TermsOfUseComponent,    title: 'Terms of Use · MarsHRMS' },
  {
    path: '',
    component: AdminLayoutComponent,
    canActivate: [authGuard],
    canActivateChild: [parentAreaGuard],   // parent logins stay in the parent portal
    children: [
      { path: '',                   pathMatch: 'full', redirectTo: landingPage },
      { path: 'dashboard',          component: AdminDashboardComponent, canActivate: [adminGuard] },
      // Home was merged into the Dashboard; old links and the pages' Home buttons land there
      { path: 'home',               pathMatch: 'full', redirectTo: landingPage },
      { path: 'analytics',          component: AnalyticsComponent, canActivate: [adminGuard] },
      { path: 'employees',          component: EmployeeListComponent },
      { path: 'employees/add',      component: EmployeeFormComponent },
      { path: 'employees/edit/:id', component: EmployeeFormComponent },
      { path: 'attendance',         component: AttendanceListComponent },
      { path: 'attendance/approval', component: AttendanceApprovalComponent, canActivate: [adminGuard] },
      
      // Payroll submenu
      { path: 'payroll/generate',       component: PayrollGenerateComponent },
      { path: 'payroll/list',           component: PayrollListComponent },
      { path: 'payroll/salary-release',   component: SalaryReleaseComponent },
      { path: 'payroll/year-end-reports',  component: YearEndReportsComponent },
      { path: 'payroll',                   redirectTo: 'payroll/generate', pathMatch: 'full' },
      
      // Timesheets
      { path: 'timesheets',         component: TimesheetListComponent },
      
      // Leave submenu
      { path: 'leave/balance',      component: LeaveBalanceComponent },
      { path: 'leave/request',      component: LeaveRequestFormComponent },
      { path: 'leave/requests',     component: LeaveRequestListComponent },
      { path: 'leave',              redirectTo: 'leave/balance', pathMatch: 'full' },
      
      // Reports submenu
      { path: 'reports',            component: ReportsDashboardComponent },
      { path: 'reports/payroll',    component: PayrollReportComponent },
      { path: 'reports/attendance', component: AttendanceReportComponent },
      { path: 'reports/directory',  component: EmployeeDirectoryComponent },
      { path: 'reports/monthly-summary', component: MonthlySummaryComponent, canActivate: [adminGuard] },
      
      // Self-Service (Employee Portal)
      { path: 'self-service/dashboard',        component: EmployeeDashboardComponent },
      { path: 'self-service/my-profile',       component: MyProfileComponent },
      { path: 'self-service/my-payslips',      component: MyPayslipsComponent },
      { path: 'self-service/my-attendance',    component: MyAttendanceComponent },
      { path: 'self-service/my-leave',         component: MyLeaveComponent },
      { path: 'self-service/my-timesheet',     component: MyTimesheetComponent },
      { path: 'self-service/change-password',  component: ChangePasswordComponent },
      { path: 'self-service',                  redirectTo: 'self-service/dashboard', pathMatch: 'full' },
      
      // Master submenu (Admin only)
      { path: 'master/departments',      component: DepartmentListComponent,   canActivate: [adminGuard] },
      { path: 'master/users',            component: UserListComponent,         canActivate: [adminGuard] },
      { path: 'master/banks',            component: BankListComponent,         canActivate: [adminGuard] },
      { path: 'master/public-holidays',  component: PublicHolidaysComponent,   canActivate: [adminGuard] },
      { path: 'master/company-settings', component: CompanySettingsComponent,  canActivate: [adminGuard] },
      { path: 'master/statutory-rates',  component: StatutoryRatesComponent,   canActivate: [adminGuard] },
      { path: 'master/chatbot',          loadComponent: () => import('./modules/master/pages/chatbot-component/chatbot-component').then(m => m.ChatbotComponent),
                                         canActivate: [adminGuard], title: 'Chatbot' },
      
      // School (only when the company has school features on; the API enforces access)
      { path: 'school/classes',       loadComponent: schoolClasses,       canActivate: [adminGuard], title: 'Classes' },
      { path: 'school/students',      loadComponent: schoolStudents,      title: 'Children' },
      { path: 'school/my-class',      loadComponent: schoolStudents,      title: 'My Class' },
      { path: 'school/parents',       loadComponent: schoolParents,       canActivate: [adminGuard], title: 'Parents' },
      { path: 'school/families',      loadComponent: schoolFamilies,      canActivate: [adminGuard], title: 'Families' },
      { path: 'school/pickup-people', loadComponent: schoolPickupPeople,  canActivate: [adminGuard], title: 'Pick-up People' },
      { path: 'school/banners',       loadComponent: schoolBanners,       canActivate: [adminGuard], title: 'Banners' },
      { path: 'school/announcements', loadComponent: schoolAnnouncements, title: 'Announcements' },
      { path: 'school/messages',      loadComponent: schoolMessages,      title: 'Messages' },
      { path: 'school/attendance',    loadComponent: schoolAttendance,    title: 'Attendance & Daily Reports' },
      { path: 'school/fees',          loadComponent: schoolFees,          canActivate: [adminGuard], title: 'Fees' },

      // Parent portal (parent logins)
      { path: 'parent',               loadComponent: parentHome,          canActivate: [parentOnlyGuard], title: 'Parent Portal' },
      { path: 'parent/announcements', loadComponent: schoolAnnouncements, canActivate: [parentOnlyGuard], title: 'Announcements' },
      { path: 'parent/messages',      loadComponent: schoolMessages,      canActivate: [parentOnlyGuard], title: 'Messages' },
      { path: 'parent/child/:id',     loadComponent: parentChild,         canActivate: [parentOnlyGuard], title: 'My Child' },
      { path: 'parent/fees',          loadComponent: parentFees,          canActivate: [parentOnlyGuard], title: 'Fees' },
      { path: 'parent/account',       loadComponent: parentAccount,       canActivate: [parentOnlyGuard], title: 'My Account' },

      // Notifications
      { path: 'notifications', component: NotificationsPageComponent },

      // Audit Log (Admin only)
      { path: 'audit', component: AuditLogComponent, canActivate: [adminGuard] },

      // Legacy route redirect
      { path: 'users',              redirectTo: 'master/users', pathMatch: 'full' },
    ]
  },
  {
    path: '**',
    redirectTo: ''
  }
];

/** Super Admin portal (admin.marshrms.com): only these pages exist on that address. */
const platformRoutes: Routes = [
  { path: 'login', component: PlatformLoginComponent },
  { path: '',      component: PlatformPortalComponent, canActivate: [superAdminGuard] },
  { path: '**',    redirectTo: '' }
];

export const routes: Routes = isPlatformHost() ? platformRoutes : companyRoutes;
