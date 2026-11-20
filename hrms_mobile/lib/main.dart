import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/storage/session_storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Restore any saved session before the first frame so the router
  // can decide immediately between the login screen and the dashboard.
  final sessionStorage = SessionStorage();
  await sessionStorage.load();

  runApp(
    ProviderScope(
      overrides: [sessionStorageProvider.overrideWithValue(sessionStorage)],
      child: const HrmsApp(),
    ),
  );
}
