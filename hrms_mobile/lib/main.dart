import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/storage/company_store.dart';
import 'core/storage/session_storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Restore the saved company and session before the first frame so the
  // router can decide immediately between the login screen and the app.
  final companyStore = CompanyStore();
  final sessionStorage = SessionStorage();
  await Future.wait([companyStore.load(), sessionStorage.load()]);

  runApp(
    ProviderScope(
      overrides: [
        sessionStorageProvider.overrideWithValue(sessionStorage),
        companyStoreProvider.overrideWithValue(companyStore),
      ],
      child: const HrmsApp(),
    ),
  );
}
