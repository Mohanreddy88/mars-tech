import 'dart:async';
import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/application/auth_controller.dart';
import '../network/api_client.dart';
import '../router/app_router.dart';

/// Shows the in-app banner for alerts that arrive while the app is open.
final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// Phone alerts through Firebase Cloud Messaging.
///
/// * After sign-in the phone's token is sent to the API (`POST notification/devices`), so the
///   server can alert this user; signing out removes it (AuthController.logout passes [token]).
/// * App closed or in the background: Android shows the alert itself; tapping it opens the
///   Notifications screen.
/// * App open: a banner with "View".
///
/// Does nothing when Firebase isn't set up for this build (no google-services.json), so the app
/// still runs without it.
class PushNotifications {
  PushNotifications(this._ref);

  final Ref _ref;
  bool _ready = false;
  String? _token;
  String? _registeredFor;   // "<api base url>|<user>" the token was last sent for

  /// This phone's push token (null until Firebase is ready and permission is granted).
  String? get token => _token;

  Future<void> start() async {
    try {
      await Firebase.initializeApp();
    } catch (e) {
      debugPrint('Push notifications off: Firebase is not set up for this build ($e)');
      return;
    }
    _ready = true;
    final messaging = FirebaseMessaging.instance;

    // Android 13+ and iOS ask the user once
    final settings = await messaging.requestPermission();
    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      debugPrint('Push notifications: permission denied by the user.');
    }

    try {
      _token = await messaging.getToken();
      _ref.read(pushTokenProvider.notifier).state = _token;
    } catch (e) {
      debugPrint('Push notifications: no token ($e)');
    }
    messaging.onTokenRefresh.listen((t) {
      _token = t;
      _ref.read(pushTokenProvider.notifier).state = t;
      _registeredFor = null;
      unawaited(_register());
    });

    // Alert tapped while the app was in the background, or opened the app from closed
    FirebaseMessaging.onMessageOpenedApp.listen((m) => _openFor(m.data['link'] as String?));
    final initial = await messaging.getInitialMessage();
    if (initial != null) {
      // Let the router settle on its first screen before moving on
      Future.delayed(const Duration(milliseconds: 600), () => _openFor(initial.data['link'] as String?));
    }

    // Alert while the app is open: Android doesn't show it, so show a banner
    FirebaseMessaging.onMessage.listen((m) {
      final n = m.notification;
      if (n == null) return;
      scaffoldMessengerKey.currentState
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text([n.title, n.body].whereType<String>().where((s) => s.isNotEmpty).join('\n')),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
          action: SnackBarAction(label: 'View', onPressed: () => _openFor(m.data['link'] as String?)),
        ));
    });

    // Register now if already signed in, and after every sign-in
    unawaited(_register());
    _ref.listen(authControllerProvider, (prev, next) {
      if (next == null) {
        _registeredFor = null;
      } else {
        unawaited(_register());
      }
    });
  }

  /// Sends the token to the API for the signed-in user (once per user and server).
  Future<void> _register() async {
    final session = _ref.read(authControllerProvider);
    final token = _token;
    if (!_ready || session == null || token == null) return;
    final dio = _ref.read(dioProvider);
    final key = '${dio.options.baseUrl}|${session.username}';
    if (_registeredFor == key) return;
    try {
      await dio.post<void>('notification/devices', data: {
        'token': token,
        'platform': Platform.isIOS ? 'ios' : 'android',
      }, options: Options(sendTimeout: const Duration(seconds: 10), receiveTimeout: const Duration(seconds: 10)));
      _registeredFor = key;
      debugPrint('Push notifications: phone registered for ${session.username}.');
    } catch (e) {
      debugPrint('Push notifications: registering the phone failed ($e); will retry on next sign-in.');
    }
  }

  /// Opens the screen the alert is about (school alerts carry a page link), else Notifications.
  void _openFor(String? link) {
    final session = _ref.read(authControllerProvider);
    if (session == null) return;   // the login screen comes first
    Routes.open(_ref.read(routerProvider), Routes.fromWebLink(session, link) ?? Routes.notifications);
  }
}

final pushNotificationsProvider = Provider<PushNotifications>((ref) => PushNotifications(ref));

/// This phone's push token (null until Firebase gives one). Kept apart from
/// [pushNotificationsProvider], which watches the sign-in state: sign-out reads the token
/// here, so the auth controller doesn't depend on a provider that depends on it.
final pushTokenProvider = StateProvider<String?>((ref) => null);
