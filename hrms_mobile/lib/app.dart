import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/push/push_notifications.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/school/data/school_repository.dart';

class HrmsApp extends ConsumerStatefulWidget {
  const HrmsApp({super.key});

  @override
  ConsumerState<HrmsApp> createState() => _HrmsAppState();
}

class _HrmsAppState extends ConsumerState<HrmsApp> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Back in the app: pick up changes made elsewhere (e.g. School features switched on on the web)
    _lifecycle = AppLifecycleListener(onResume: () {
      ref.invalidate(schoolMeProvider);
      ref.invalidate(schoolUnreadProvider);
    });
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'HRMS',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: scaffoldMessengerKey,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      routerConfig: router,
    );
  }
}
