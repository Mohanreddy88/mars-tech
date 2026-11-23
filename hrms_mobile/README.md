# Mars HRMS (mobile)

Flutter app for HRMS (Android / iOS), app id **`com.marstech.hrms`**. Same HrmsApi backend as the
Angular web app (`../hrms-ui`). Employees get self-service; **Admin** logins get the admin app
(dashboard, approvals, employees, payroll, reports, master data, audit log).

## First-time setup

1. Install the Flutter SDK (stable), add its `bin` folder to PATH, and run `flutter doctor` until
   Android (and Xcode on macOS, for iOS) show as ready.
2. `cd hrms_mobile && flutter pub get`

Debug builds allow plain `http://` to the local API (`android/app/src/debug/AndroidManifest.xml`);
release builds use HTTPS.

## Which server the app talks to (`lib/core/config/env.dart`)

| Build | Server |
|---|---|
| `flutter run` (debug) | local API from the Android emulator: `http://10.0.2.2:64559/api` |
| `--dart-define=API_BASE_URL=<url>` | that server only (any build) |
| release, no `API_BASE_URL` | **user picks the company** from the registered list on the login screen (search by name; list from `GET /api/public/companies`, the code can still be typed if it does not load) → `https://<code>.marshrms.com/api` (UAT build: `<code>.uat.marshrms.com`), remembered on the phone |
| release + `--dart-define=API_DOMAIN=uat.marshrms.com` | same, against UAT (`<code>.uat.marshrms.com`) |

```bash
flutter run                                                        # local API (emulator)
flutter run --dart-define=API_BASE_URL=http://192.168.x.x:64559/api # phone on Wi-Fi; API: dotnet run --urls http://0.0.0.0:64559
flutter run --dart-define=API_BASE_URL=https://uat.marshrms.com/api # UAT
```

## Sign-in, refresh tokens

Login returns a short access token (`Jwt:ExpiryMinutes`, 8 h) and a **refresh token** (30 days,
`Jwt:RefreshDays`). The API client renews the access token before it expires and after a 401
(`/api/auth/refresh`, rotating), so users stay signed in for weeks. The session ends — and the
login screen explains why — when the refresh token expires, the user signs in on another device
(one login at a time), their password is reset / set by an admin, or the login is disabled.
Sign out calls `/api/auth/logout` (revokes the refresh token and this phone's push registration).

## Release build (Google Play)

Signing uses the **upload key** in `%USERPROFILE%\.android-keys\mars-hrms-upload.jks`, referenced by
`android/key.properties` (git-ignored; contains the password). **Back up both** (e.g. in a password
manager): without them the published app can never be updated. Without `key.properties` a release
build is signed with the debug key (fine for testing, rejected by Google Play).

```bash
# 1. bump version in pubspec.yaml (version: 1.0.1+2 — the +number must increase every upload)
# 2. build the bundle for Google Play (users pick their company at login)
flutter build appbundle --release
#    -> build/app/outputs/bundle/release/app-release.aab   (upload in Play Console)
# test build against UAT instead:
flutter build apk --release --dart-define=API_DOMAIN=uat.marshrms.com
```

Use **Play App Signing** in the Play Console (Google keeps the app signing key; this file is only
the upload key, which Google can reset if it is lost).

iOS: open `ios/Runner.xcworkspace` in Xcode on a Mac, set the team for bundle id
`com.marstech.hrms`, then `flutter build ipa`.

## Push notifications (Firebase Cloud Messaging)

The **server side is done**: the API stores each phone's token (`POST /api/notification/devices`,
table `DeviceTokens`) and pushes every in-app notification (leave/attendance/payroll decisions,
submissions for admins) to that user's phones. It stays **off** until the server has Firebase
credentials. To switch it on:

1. Create a project at https://console.firebase.google.com (one project for all companies).
2. Add an **Android app** with package `com.marstech.hrms` → download `google-services.json` and
   put it at `hrms_mobile/android/app/google-services.json` (git-ignored). For iOS add an Apple app
   (`com.marstech.hrms`), download `GoogleService-Info.plist` and upload an APNs key in Firebase.
3. Project settings → Service accounts → **Generate new private key** (JSON). On the VPS, add it on
   one line to `/opt/hrms/deploy/.env` and `/opt/hrms-uat/deploy/.env.uat`:
   `FIREBASE_CREDENTIALS_JSON='{"type":"service_account",...}'` (single quotes; `jq -c . key.json`
   makes one line), then recreate the app container. The API log says
   `Push notifications are on (Firebase project ...)`.
4. App side — done (`lib/core/push/push_notifications.dart`): after sign-in the phone's FCM token
   goes to `POST notification/devices`; sign-out removes it. Alerts tapped open Notifications; while
   the app is open they show as a banner. Builds without `google-services.json` still run (push off).
   Local API testing: `FIREBASE_CREDENTIALS_FILE` (path to the key JSON) in
   `HrmsApi/appsettings.Development.json`.

## Structure

```
lib/
  main.dart                 restores company + session, starts the app
  app.dart                  MaterialApp.router + theme
  core/
    config/env.dart         server choice (API_BASE_URL / company code)
    network/                Dio client (token, refresh-and-retry), ApiException
    storage/                session + company in secure storage (Keystore / Keychain)
    router/app_router.dart  routes, admin vs employee areas, auth redirects
    theme/, utils/, widgets/
  features/
    auth/ dashboard/ payslips/ leave/ attendance/ notifications/ profile/   employee app
    admin/                  admin app: dashboard, approvals, employees, payroll/, reports/,
                            master/, audit/
    school/                 school features (companies with School features on):
                            parents' area, messages, announcements, attendance, daily reports, fees
  core/push/                Firebase push (phone registration, alert taps)
```

## School features

Shown only when the company has **School features** on (web: Company Settings), from
`GET school/me`:
- **Parent logins** get their own area (`/parent`): Home (children, today's status), My Child
  (arrival / home time, daily report and photos, absence and pickup notes), Messages, News
  (announcements), Fees (invoices, receipts, PDFs), Account.
- **Class teachers** (employees named on a class) get a School block on Home: My Class, Attendance &
  reports (check in / out, absent, parents' notes, daily report with camera photos), Messages,
  Announcements.
- **Admins** get the same under More, plus Fees (month overview, invoice detail, record payment).
  Setting up classes, children, parents, fee items and creating invoices stays on the web.

Chats refresh every few seconds while open (the web uses live SignalR updates). Alerts tapped open
the matching screen (`Routes.fromWebLink`).

Each feature has `data/` (models + repository calling the API), `application/` (Riverpod state)
when needed, and `presentation/` (screens). Tests: `flutter test` (models, rules, routing).

## Notes

- Android build settings: Gradle/Kotlin daemon memory is limited in `android/gradle.properties`
  (16 GB PC + emulator). `android.builtInKotlin=false` is required by plugins such as
  `share_plus`; `file_picker` does not build with it, so leave documents use `image_picker` photos.
- Website-only on purpose: permanent employee delete, company logo upload, statutory rate tables,
  PDF leave documents.
