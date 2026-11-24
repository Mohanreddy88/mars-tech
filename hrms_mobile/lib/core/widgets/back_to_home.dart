import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../router/app_router.dart';

/// Back arrow for the admin bottom-tab pages (Approvals, Employees, Payroll, More).
/// They open from Home's tiles by switching tab, so there is no page to pop back to;
/// this returns to Home like the back arrow on every other page.
class BackToHomeButton extends StatelessWidget {
  const BackToHomeButton({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
        icon: const BackButtonIcon(),
        tooltip: 'Back',
        onPressed: () => context.go(Routes.adminHome),
      );
}
