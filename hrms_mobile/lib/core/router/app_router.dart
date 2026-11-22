import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/admin/data/admin_models.dart';
import '../../features/admin/payroll/presentation/generate_payroll_screen.dart';
import '../../features/admin/payroll/presentation/payroll_record_screen.dart';
import '../../features/admin/payroll/presentation/payroll_screen.dart';
import '../../features/admin/payroll/presentation/salary_release_screen.dart';
import '../../features/admin/payroll/presentation/year_end_screen.dart';
import '../../features/admin/audit/presentation/audit_log_screen.dart';
import '../../features/admin/master/data/master_repository.dart' show MasterKind;
import '../../features/admin/master/presentation/company_rates_screens.dart';
import '../../features/admin/master/presentation/master_lists_screen.dart';
import '../../features/admin/master/presentation/users_screen.dart';
import '../../features/admin/reports/presentation/analytics_screen.dart';
import '../../features/admin/reports/presentation/report_screens.dart';
import '../../features/admin/presentation/admin_dashboard_screen.dart';
import '../../features/admin/presentation/admin_more_screen.dart';
import '../../features/admin/presentation/attendance_history_screen.dart';
import '../../features/admin/presentation/leave_balances_screen.dart';
import '../../features/admin/presentation/admin_home_shell.dart';
import '../../features/admin/presentation/approvals_screen.dart';
import '../../features/admin/presentation/attendance_review_screen.dart';
import '../../features/admin/presentation/employee_detail_screen.dart';
import '../../features/admin/presentation/employee_form_screen.dart';
import '../../features/admin/presentation/employees_screen.dart';
import '../../features/attendance/data/attendance_models.dart';
import '../../features/attendance/presentation/attendance_period_screen.dart';
import '../../features/attendance/presentation/attendance_screen.dart';
import '../../features/auth/application/auth_controller.dart';
import '../../features/auth/data/session.dart';
import '../../features/auth/presentation/change_password_screen.dart';
import '../../features/auth/presentation/forgot_password_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/dashboard/presentation/dashboard_screen.dart';
import '../../features/home/home_shell.dart';
import '../../features/leave/presentation/apply_leave_screen.dart';
import '../../features/leave/presentation/leave_screen.dart';
import '../../features/notifications/presentation/notifications_screen.dart';
import '../../features/payslips/presentation/payslip_detail_screen.dart';
import '../../features/payslips/presentation/payslips_screen.dart';
import '../../features/profile/data/profile_models.dart';
import '../../features/profile/presentation/edit_profile_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/school/presentation/admin_setup_screens.dart';
import '../../features/school/presentation/announcements_screen.dart';
import '../../features/school/presentation/child_day_screen.dart';
import '../../features/assistant/presentation/assistant_screen.dart';
import '../../features/assistant/presentation/chatbot_admin_screen.dart';
import '../../features/school/presentation/fees_admin_screens.dart';
import '../../features/school/presentation/fees_screens.dart';
import '../../features/school/presentation/messages_screens.dart';
import '../../features/school/presentation/parent_home_screen.dart';
import '../../features/school/presentation/parent_screens.dart';
import '../../features/school/presentation/staff_screens.dart';

class Routes {
  Routes._();

  static const login = '/login';
  static const forgotPassword = '/forgot-password';
  static const changePassword = '/change-password';

  // Bottom-navigation tabs
  static const dashboard = '/dashboard';
  static const payslips = '/payslips';
  static const leave = '/leave';
  static const attendance = '/attendance';
  static const profile = '/profile';

  // Full-screen pages opened from the tabs (no bottom navigation)
  static const applyLeave = '/apply-leave';
  static const attendancePeriod = '/attendance-period'; // extra: AttendancePeriod
  static const notifications = '/notifications';
  static const editProfile = '/edit-profile'; // extra: EmployeeProfile

  // Admin logins (separate bottom navigation)
  static const adminHome = '/admin';
  static const adminApprovals = '/admin/approvals'; // ?tab=attendance
  static const adminEmployees = '/admin/employees';
  static const adminPayroll = '/admin/payroll';
  static const adminMore = '/admin/more';
  static const attendanceHistory = '/attendance-history';
  static const leaveBalances = '/leave-balances';
  static const payrollReport = '/report-payroll';
  static const attendanceReport = '/report-attendance';
  static const directoryReport = '/report-directory';
  static const monthlySummary = '/report-monthly';
  static const analytics = '/analytics';
  static const departmentsMaster = '/master-departments';
  static const banksMaster = '/master-banks';
  static const holidaysMaster = '/master-holidays';
  static const usersMaster = '/master-users';
  static const companySettings = '/master-company';
  static const statutoryRates = '/master-rates';
  static const auditLog = '/audit-log';
  static const chatbotAdmin = '/master-chatbot';
  static const assistant = '/assistant'; // help chatbot, every role
  static const attendanceReview = '/attendance-review'; // /{periodId}
  static const employeeDetail = '/employee-detail'; // extra: EmployeeSummary
  static const employeeForm = '/employee-form'; // extra: EmployeeSummary to edit, none = new
  static const payrollRecord = '/payroll-record'; // /{payrollId}
  static const generatePayroll = '/generate-payroll';
  static const salaryRelease = '/salary-release';
  static const yearEnd = '/year-end';

  // School features. Parent logins have their own bottom navigation:
  static const parentHome = '/parent';
  static const parentMessages = '/parent/messages';
  static const parentAnnouncements = '/parent/announcements';
  static const parentFees = '/parent/fees';
  static const parentAccount = '/parent/account';
  // Shared school pages (parents and staff; the API decides what each may see)
  static const schoolChat = '/school/chat'; // /{conversationId}
  static const schoolChild = '/school/child'; // /{studentId}?date=yyyy-MM-dd
  // Staff (class teachers and admins)
  static const schoolMessages = '/school/messages';
  static const schoolAnnouncements = '/school/announcements';
  static const schoolAttendance = '/school/attendance'; // ?date=
  static const schoolMyClass = '/school/my-class';
  // Admins
  static const schoolFees = '/school/fees';
  static const schoolInvoice = '/school/invoice'; // /{invoiceId}
  static const schoolClasses = '/school/classes';
  static const schoolChildren = '/school/children';
  static const schoolParents = '/school/parents';

  static const _employeeOnly = [dashboard, payslips, leave, attendance, profile,
      applyLeave, attendancePeriod, editProfile];
  static const _adminOnly = [adminHome, attendanceReview, employeeDetail, employeeForm,
      attendanceHistory, leaveBalances, payrollReport, attendanceReport, directoryReport,
      monthlySummary, analytics, departmentsMaster, banksMaster, holidaysMaster, usersMaster,
      companySettings, statutoryRates, auditLog, chatbotAdmin,
      payrollRecord, generatePayroll, salaryRelease, yearEnd];

  /// Home screen for the signed-in role.
  static String homeFor(Session s) => s.isAdmin ? adminHome : s.isParent ? parentHome : dashboard;

  /// Bottom-navigation tabs. These must be opened with go(), never push(): pushing one puts a
  /// second copy of its tab shell on the stack and the navigator fails (duplicate page key).
  static const _tabs = [
    parentHome, parentMessages, parentAnnouncements, parentFees, parentAccount,
    adminHome, adminApprovals, adminEmployees, adminPayroll, adminMore,
    dashboard, payslips, leave, attendance, profile,
  ];

  static bool isTab(String location) => _tabs.contains(Uri.parse(location).path);

  /// Opens [location]: switches tab for bottom-navigation pages, otherwise pushes the page.
  static void open(GoRouter router, String location) =>
      isTab(location) ? router.go(location) : router.push(location);

  /// Pages a parent login may open.
  static const _parentPages = [parentHome, schoolChat, schoolChild, notifications, changePassword, assistant];
  static const _adminSchool = [schoolFees, schoolInvoice, schoolClasses, schoolChildren, schoolParents];

  /// The app screen for a page link from a notification (web paths, e.g. "/parent/fees",
  /// "/parent/child/5?date=2026-11-21", "/school/messages?c=12"). Null = no matching screen.
  static String? fromWebLink(Session s, String? link) {
    if (link == null || link.isEmpty) return null;
    final uri = Uri.parse(link);
    final p = uri.pathSegments;
    final date = uri.queryParameters['date'];
    if (p.length >= 3 && p[0] == 'parent' && p[1] == 'child') {
      return '$schoolChild/${p[2]}${date != null ? '?date=$date' : ''}';
    }
    if (uri.path == '/parent/fees') return s.isParent ? parentFees : null;
    if (uri.path == '/school/fees') return s.isAdmin ? schoolFees : null;
    if (uri.path == '/parent/announcements') return s.isParent ? parentAnnouncements : schoolAnnouncements;
    if (uri.path == '/school/messages') {
      final c = uri.queryParameters['c'];
      return c != null ? '$schoolChat/$c' : (s.isParent ? parentMessages : schoolMessages);
    }
    if (uri.path == '/school/attendance') return s.isParent ? null : '$schoolAttendance${date != null ? '?date=$date' : ''}';
    return null;
  }

  /// Whether [location] belongs to the other role's part of the app.
  static bool isWrongArea(Session s, String location) {
    bool under(String root) => location == root || location.startsWith('$root/');
    if (s.isParent) return !_parentPages.any(under);
    if (under(parentHome)) return true;
    return s.isAdmin
        ? _employeeOnly.any(under)
        : _adminOnly.any(under) || _adminSchool.any(under);
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  // Bridge Riverpod auth state to GoRouter's refreshListenable.
  final auth = ValueNotifier<Session?>(ref.read(authControllerProvider));
  ref.listen<Session?>(authControllerProvider, (_, next) => auth.value = next);
  ref.onDispose(auth.dispose);

  return GoRouter(
    initialLocation: Routes.dashboard,
    refreshListenable: auth,
    redirect: (context, state) {
      final session = auth.value;
      final location = state.matchedLocation;
      final isPublic =
          location == Routes.login || location == Routes.forgotPassword;

      if (session == null) return isPublic ? null : Routes.login;
      if (session.mustChangePassword) {
        return location == Routes.changePassword ? null : Routes.changePassword;
      }
      if (isPublic) return Routes.homeFor(session);
      // Admins get the admin screens, employees the self-service screens.
      // (The API enforces this too; this just avoids dead-end pages.)
      if (Routes.isWrongArea(session, location)) return Routes.homeFor(session);

      // Pages that need an object passed in `extra` (lost if the app is
      // restored from the background): fall back to their list.
      if (location == Routes.attendancePeriod && state.extra is! AttendancePeriod) {
        return Routes.attendance;
      }
      if (location == Routes.editProfile && state.extra is! EmployeeProfile) {
        return Routes.profile;
      }
      if (location == Routes.employeeDetail && state.extra is! EmployeeSummary) {
        return Routes.adminEmployees;
      }
      return null;
    },
    routes: [
      GoRoute(
        path: Routes.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: Routes.forgotPassword,
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: Routes.changePassword,
        builder: (context, state) => const ChangePasswordScreen(),
      ),
      GoRoute(
        path: Routes.applyLeave,
        builder: (context, state) => const ApplyLeaveScreen(),
      ),
      GoRoute(
        path: Routes.attendancePeriod,
        builder: (context, state) =>
            AttendancePeriodScreen(period: state.extra! as AttendancePeriod),
      ),
      GoRoute(
        path: Routes.notifications,
        builder: (context, state) => const NotificationsScreen(),
      ),
      // School: shared and staff pages
      GoRoute(
        path: '${Routes.schoolChat}/:id',
        builder: (context, state) => ChatScreen(conversationId: int.parse(state.pathParameters['id']!)),
      ),
      GoRoute(
        path: '${Routes.schoolChild}/:id',
        builder: (context, state) => ChildDayScreen(
          childId: int.parse(state.pathParameters['id']!),
          date: state.uri.queryParameters['date'],
        ),
      ),
      GoRoute(path: Routes.assistant, builder: (context, state) => const AssistantScreen()),
      GoRoute(path: Routes.chatbotAdmin, builder: (context, state) => const ChatbotAdminScreen()),
      GoRoute(path: Routes.schoolMessages, builder: (context, state) => const ConversationsScreen()),
      GoRoute(path: Routes.schoolAnnouncements, builder: (context, state) => const AnnouncementsScreen()),
      GoRoute(
        path: Routes.schoolAttendance,
        builder: (context, state) => SchoolAttendanceScreen(date: state.uri.queryParameters['date']),
      ),
      GoRoute(path: Routes.schoolMyClass, builder: (context, state) => const MyClassScreen()),
      GoRoute(path: Routes.schoolFees, builder: (context, state) => const AdminFeesScreen()),
      GoRoute(path: Routes.schoolClasses, builder: (context, state) => const ClassesScreen()),
      GoRoute(path: Routes.schoolChildren, builder: (context, state) => const ChildrenScreen()),
      GoRoute(path: Routes.schoolParents, builder: (context, state) => const ParentsScreen()),
      GoRoute(
        path: '${Routes.schoolInvoice}/:id',
        builder: (context, state) => InvoiceScreen(invoiceId: int.parse(state.pathParameters['id']!)),
      ),
      // Parent logins: their own bottom navigation
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => ParentShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: Routes.parentHome, builder: (context, state) => const ParentHomeScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: Routes.parentMessages, builder: (context, state) => const ConversationsScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: Routes.parentAnnouncements, builder: (context, state) => const AnnouncementsScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: Routes.parentFees, builder: (context, state) => const ParentFeesScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: Routes.parentAccount, builder: (context, state) => const ParentAccountScreen()),
          ]),
        ],
      ),
      GoRoute(
        path: '${Routes.attendanceReview}/:id',
        builder: (context, state) =>
            AttendanceReviewScreen(periodId: int.parse(state.pathParameters['id']!)),
      ),
      GoRoute(
        path: Routes.employeeDetail,
        builder: (context, state) =>
            EmployeeDetailScreen(employee: state.extra! as EmployeeSummary),
      ),
      GoRoute(
        path: Routes.attendanceHistory,
        builder: (context, state) => const AttendanceHistoryScreen(),
      ),
      GoRoute(
        path: Routes.leaveBalances,
        builder: (context, state) => const LeaveBalancesScreen(),
      ),
      GoRoute(path: Routes.payrollReport, builder: (context, state) => const PayrollReportScreen()),
      GoRoute(path: Routes.attendanceReport, builder: (context, state) => const AttendanceReportScreen()),
      GoRoute(path: Routes.directoryReport, builder: (context, state) => const DirectoryReportScreen()),
      GoRoute(path: Routes.monthlySummary, builder: (context, state) => const MonthlySummaryScreen()),
      GoRoute(path: Routes.analytics, builder: (context, state) => const AnalyticsScreen()),
      GoRoute(
          path: Routes.departmentsMaster,
          builder: (context, state) => const MasterListScreen(kind: MasterKind.departments)),
      GoRoute(path: Routes.banksMaster, builder: (context, state) => const MasterListScreen(kind: MasterKind.banks)),
      GoRoute(path: Routes.holidaysMaster, builder: (context, state) => const HolidaysScreen()),
      GoRoute(path: Routes.usersMaster, builder: (context, state) => const UsersScreen()),
      GoRoute(path: Routes.companySettings, builder: (context, state) => const CompanySettingsScreen()),
      GoRoute(path: Routes.statutoryRates, builder: (context, state) => const StatutoryRatesScreen()),
      GoRoute(path: Routes.auditLog, builder: (context, state) => const AuditLogScreen()),
      GoRoute(
        path: Routes.employeeForm,
        builder: (context, state) =>
            EmployeeFormScreen(employee: state.extra as EmployeeSummary?),
      ),
      GoRoute(
        path: '${Routes.payrollRecord}/:id',
        builder: (context, state) =>
            PayrollRecordScreen(payrollId: int.parse(state.pathParameters['id']!)),
      ),
      GoRoute(
        path: Routes.generatePayroll,
        builder: (context, state) => const GeneratePayrollScreen(),
      ),
      GoRoute(
        path: Routes.salaryRelease,
        builder: (context, state) => const SalaryReleaseScreen(),
      ),
      GoRoute(
        path: Routes.yearEnd,
        builder: (context, state) => const YearEndScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AdminHomeShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
              path: Routes.adminHome,
              builder: (context, state) => const AdminDashboardScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: Routes.adminApprovals,
              builder: (context, state) {
                final tab = state.uri.queryParameters['tab'] == 'attendance' ? 1 : 0;
                return ApprovalsScreen(key: ValueKey(tab), initialTab: tab);
              },
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: Routes.adminEmployees,
              builder: (context, state) => const EmployeesScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: Routes.adminPayroll,
              builder: (context, state) => const PayrollScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: Routes.adminMore,
              builder: (context, state) => const AdminMoreScreen(),
            ),
          ]),
        ],
      ),
      GoRoute(
        path: Routes.editProfile,
        builder: (context, state) =>
            EditProfileScreen(profile: state.extra! as EmployeeProfile),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => HomeShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
              path: Routes.dashboard,
              builder: (context, state) => const DashboardScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: Routes.payslips,
              builder: (context, state) => const PayslipsScreen(),
              routes: [
                GoRoute(
                  path: ':id',
                  builder: (context, state) => PayslipDetailScreen(
                    payslipId: int.parse(state.pathParameters['id']!),
                  ),
                ),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: Routes.leave,
              builder: (context, state) => const LeaveScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: Routes.attendance,
              builder: (context, state) => const AttendanceScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: Routes.profile,
              builder: (context, state) => const ProfileScreen(),
            ),
          ]),
        ],
      ),
    ],
  );
});
