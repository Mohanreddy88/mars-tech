# HRMS Mobile

Employee self-service app for HRMS, built with Flutter. It uses the same
HrmsApi backend as the Angular web app (`../hrms-ui`).

## First-time setup

The Android and iOS folders are already in the repo, and debug builds already
allow plain `http://` to the local API (`android/app/src/debug/AndroidManifest.xml`).
Release builds must use HTTPS.

1. Install the Flutter SDK (stable), add its `bin` folder to PATH, and run
   `flutter doctor` until Android (and Xcode on macOS, for iOS) show as ready.
2. `cd hrms_mobile && flutter pub get`

## Running

Start HrmsApi locally (`http://localhost:64559`, see the main README). The app
is employee self-service, so sign in with a login that is linked to an employee
(the default `admin` has none). Then:

```bash
# Android emulator: 10.0.2.2 is the host machine (this is the default)
flutter run

# iOS simulator
flutter run --dart-define=API_BASE_URL=http://localhost:64559/api

# Physical phone on the same Wi-Fi: use your PC's LAN IP, and start the API
# listening on all interfaces, e.g. dotnet run --urls http://0.0.0.0:64559
flutter run --dart-define=API_BASE_URL=http://192.168.x.x:64559/api

# Against UAT / a company (the company comes from the host name, as on the web)
flutter run --dart-define=API_BASE_URL=https://uat.marshrms.com/api
flutter run --dart-define=API_BASE_URL=https://<code>.marshrms.com/api
```

## Structure

```
lib/
  main.dart                 restores saved session, starts the app
  app.dart                  MaterialApp.router + theme
  core/
    config/env.dart         API_BASE_URL (--dart-define)
    network/                Dio client (JWT header, 401 -> sign out), ApiException
    storage/                session in secure storage (Keystore / Keychain)
    router/app_router.dart  routes + auth redirects
    theme/, utils/, widgets/
  features/
    auth/                   login, forgot password, change password
    dashboard/              GET /api/selfservice/dashboard
    profile/                account info, change password, sign out
    home/                   bottom-nav shell, placeholder tabs
```

Each feature has `data/` (models + repository calling the API),
`application/` (Riverpod state) when needed, and `presentation/` (screens).

## Status

| Feature | Status | API |
|---|---|---|
| Login / forced password change / sign out | Done | `auth/login`, `selfservice/change-password` |
| Forgot password | Done | `auth/forgot-password` |
| Dashboard | Done | `selfservice/dashboard` |
| Payslips | Placeholder | `selfservice/my-payslips`, `/{id}/download` |
| Leave | Placeholder | `selfservice/my-leave-balance`, `my-leave-requests` |
| Attendance | Placeholder | `selfservice/attendance-periods` |
| Timesheets | Not started | `selfservice/my-timesheets` |
| Notifications | Not started | `notification`, `notification/unread-count` |

## Known gaps (backend)

- **No refresh token yet.** The app signs the user out when the JWT
  expires. Once the API has `/auth/refresh`, add refresh-and-retry in
  `core/network/api_client.dart` (the `onError` handler).
- **Admin accounts** without a linked employee record get "Employee profile
  not found" on the dashboard, because the app is employee-only.
- **Push notifications** need FCM device-token storage on the API.
