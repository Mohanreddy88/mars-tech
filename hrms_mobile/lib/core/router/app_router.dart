import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/application/auth_controller.dart';
import '../../features/auth/data/session.dart';
import '../../features/auth/presentation/change_password_screen.dart';
import '../../features/auth/presentation/forgot_password_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/dashboard/presentation/dashboard_screen.dart';
import '../../features/home/home_shell.dart';
import '../../features/home/coming_soon_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';

class Routes {
  Routes._();

  static const login = '/login';
  static const forgotPassword = '/forgot-password';
  static const changePassword = '/change-password';
  static const dashboard = '/dashboard';
  static const payslips = '/payslips';
  static const leave = '/leave';
  static const attendance = '/attendance';
  static const profile = '/profile';
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
      if (isPublic) return Routes.dashboard;
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
              builder: (context, state) => const ComingSoonScreen(
                title: 'Payslips',
                icon: Icons.receipt_long_outlined,
              ),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: Routes.leave,
              builder: (context, state) => const ComingSoonScreen(
                title: 'Leave',
                icon: Icons.beach_access_outlined,
              ),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: Routes.attendance,
              builder: (context, state) => const ComingSoonScreen(
                title: 'Attendance',
                icon: Icons.event_available_outlined,
              ),
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
