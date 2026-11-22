# CLAUDE.md

Guidance for Claude Code in this repo. Human-facing overview: [README.md](README.md); ops details: [deploy/README.md](deploy/README.md).

## Project
HRMS payroll system: `hrms-ui/` (Angular, prod build `npm run build:prod`), `HrmsApi/` (.NET 8, EF Core;
PostgreSQL in deployment, SQL Server locally). The test project `HrmsApi/HrmsApi.Tests` sits inside the API folder
and is excluded from the API csproj.
`hrms_mobile/` is the Flutter app "Mars HRMS" (`com.marstech.hrms`; Riverpod, Dio, go_router) — employee and admin
screens — calling the same API; it is not part of the server deploy (excluded in `.dockerignore`). Server: debug =
`http://10.0.2.2:64559/api` (local API from the emulator), `--dart-define=API_BASE_URL=...` fixes one, release builds ask
for the company code → `https://<code>.marshrms.com/api`. Release/Play Store and Firebase steps: `hrms_mobile/README.md`.
Flutter SDK on this PC is not on PATH: `C:\Users\HP\Downloads\flutter_windows_3.50.0-stable\flutter\bin\flutter.bat`.
When an API response changes, update the matching model in `hrms_mobile/lib/features/*/data/`. Never commit keystores,
`key.properties` (upload key is in `%USERPROFILE%\.android-keys\`) or `google-services.json`.
Auth: login/refresh return an access token + rotating refresh token (`/api/auth/refresh`, hash on `Users`, revoked by
a new login, password reset/admin password set, `/api/auth/logout`). Push: `DeviceTokens` + `PushService` (FCM), off
until `FIREBASE_CREDENTIALS_JSON` is set in the server `.env` files.

## Branches and releases (the user's chosen process — keep it)
- **Never commit or push to `main`.** It's protected by GitHub ruleset `protect-main` (PR required, no force push).
- Work on **`uat`** (or a feature branch merged into `uat`). Every push to `uat` auto-deploys to UAT.
- Production releases happen only when the **user** merges a Pull Request `uat → main` on GitHub
  (https://github.com/Mohanreddy88/mars-tech/compare/main...uat). Don't merge PRs for the user unless asked.
- End commit messages with the attribution line required by the session.

## Deployment (Hostinger VPS 189.72.155.35, Ubuntu 22.04, `ssh root@189.72.155.35`)
- Prod: `/opt/hrms` on `main`, compose project `hrms` (`deploy/docker-compose.yml` + `deploy/.env`):
  services `db` (Postgres 16), `app` (nginx + Angular + API), `caddy` (HTTPS for all domains).
- UAT: `/opt/hrms-uat` on `uat`, compose project `hrms-uat` (`deploy/docker-compose.uat.yml` + `deploy/.env.uat`),
  own DB `hrms_uat`; reached by prod Caddy over external docker network `web` (alias `uat-app`).
- Domains (option B, both serve the same apps): `marstech.tech`, `marshrms.com`, their `www.` (redirect), `uat.`,
  and wildcards `*.` / `*.uat.` for company addresses + `admin.` portal (Caddy on-demand TLS).
- Public website: static files in `website/` (no build), copied into the app image and served by the app's nginx for
  host `marshrms.com` / `uat.marshrms.com` (first server block in `deploy/nginx.conf`); `/api/` still reaches the API
  (contact form `POST /api/public/contact`), old app paths redirect to `demo.<host>`. The demo company's address is
  `demo.marshrms.com` (`TenancyOptions.UrlFor`); `marstech.tech` bare still opens the app. WhatsApp number: `website/assets/js/site.js`.
  Routing lives in `deploy/Caddyfile`; validate before releasing:
  `docker run --rm -v "$PWD/Caddyfile:/etc/caddy/Caddyfile:ro" caddy:2-alpine caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile`
- Auto-deploy: root crontab runs `/opt/hrms/deploy/auto-deploy.sh uat|prod` every 2 min; it polls `origin/uat` /
  `origin/main`, runs `deploy-uat.sh` / `deploy.sh` (prod runs `backup.sh` first). Logs:
  `/var/log/hrms-uat-deploy.log`, `/var/log/hrms-prod-deploy.log`. Failed commits aren't retried until a newer push.
- `deploy.sh` recreates Caddy when the Caddyfile changed — but a release that changes `deploy.sh` itself runs the
  old copy, so recreate Caddy manually in that case (`docker compose up -d --no-deps --force-recreate caddy`).
- Backups: nightly 02:30 + pre-release, `/opt/hrms-backups`, 14 days — every database dumped separately.
- Email: Hostinger SMTP (`smtp.hostinger.com:587`, `support@marstech.tech`) set via `SMTP_*` in the server `.env` files.
  Email links use `FrontendUrl` (env `FRONTEND_URL`, defaults https://marshrms.com / https://uat.marshrms.com).
- Server git clones use `core.fileMode=false` (scripts are chmod +x'd on the server).

## API access rules
Logins are `Admin` or `Employee` (also legacy `User`). Every endpoint that manages company data must carry
`[Authorize(Roles = "Admin")]` (approvals may use `UserAccess.Approvers`); `[Authorize]` alone lets any employee in.
Employee self-service goes through `/api/selfservice/*`; elsewhere check ownership with `UserAccess`
(`CurrentEmployeeIdAsync`, `CanAccessEmployeeAsync`) and never trust an `employeeId` sent by a non-admin client.
School features (per company, `CompanySettings.SchoolFeaturesEnabled`, endpoints carry `[RequiresSchoolFeatures]`):
classes, children, parents, announcements, parent ↔ teacher/office conversations (many per child, each with a subject;
parents or staff start them, staff close them, a reply reopens), attendance (check-in/out, parents'
absence/pickup notes), daily reports with photos, monthly fees (invoices, sibling discount, receipts, parents'
"I've paid" claims confirmed by the office). School dates use Malaysia time (`SchoolClock`). Phone numbers are
stored as +60… (`PhoneNumbers`). The mobile app has the parent area and staff school screens. `Parent` logins are managed under
School → Parents (hidden from Master → Users); class teachers are employees named on a class. Decide access with
`SchoolViewer` (admin / class teacher / parent) loaded from the database, never from ids the client sends. Live
updates: SignalR hub `/api/hubs/chat` (groups include the company; nginx `location ^~ /api/hubs/`).
Help chatbot (`/api/assistant`, `AssistantController`): no AI — keyword matching (`BotMatcher`) over admin-written
`BotFaqs` (audience All/Parent/Employee; Master → Chatbot on web, More → Chatbot on mobile); unanswered questions are
logged in `BotUnanswered`. Answer buttons use shared action keys (`BotActions`) that web and mobile map to their pages.
Optional AI answers (Claude, `Services/AssistantAi.cs` + read-only `AssistantTools` scoped to the asking user): need a
key — the company's own (Chatbot → Connect AI; tested, stored AES-GCM-encrypted via `SecretBox` with a key derived from
`Jwt:Key`, so rotating JWT_SECRET_KEY means reconnecting) or the server's `ANTHROPIC_API_KEY` env fallback
(`Assistant__Model`, `Assistant__DailyLimitPerUser` optional) — **and** the company switch `AssistantAiEnabled`. Clear general FAQ matches stay free; any AI failure
falls back to the FAQ answer. Usage per question in `BotAiUsage`. Tools must never return another user's data.
Tools are offered by role (parent / employee / class teacher / admin); `suggest_page` adds a page button (keys in
`BotActions`, mapped by both clients) and `offer_download` a file button (whitelisted API paths, fetched with the token).

## Secrets — the repo is PUBLIC
Never commit `deploy/.env`, `deploy/.env.uat`, `HrmsApi/appsettings.Development.json` or any password/API key.
Secrets live only on the server. Don't print secret values in output; mask them.

## Useful commands (on the VPS)
```bash
cd /opt/hrms/deploy && docker compose ps / logs -f app / logs -f caddy
cd /opt/hrms-uat/deploy && docker compose -f docker-compose.uat.yml --env-file .env.uat logs -f app
docker compose exec db psql -U hrms -d hrms        # prod DB shell
```

## Companies (multi-tenant) — see README "Companies"
One app, **one PostgreSQL database per company**, chosen from the host name (`HrmsApi/Platform/`):
`<code>.marshrms.com` → `hrms_<code>`, bare domain → company `demo` (original DB), `admin.<domain>` → Super Admin
portal (`/api/platform/*`, master DB `hrms_master`, `PlatformDbContext`). `HrmsDbContext` connects to the current
company's database via `ITenantContext`; background work must set the company (see `BackgroundEmailService`).
Login tokens carry a `tenant` claim and only work on the issuing company. Never query across companies.

## Database changes = EF Core migrations (PostgreSQL)
The API applies pending migrations on startup (`Program.cs`, `Data/DatabaseMigrator.cs`), so every database —
prod, UAT and each client — updates itself on deploy. A failed migration stops the app; `deploy/wait-healthy.sh`
then marks the deploy FAILED (prod has a backup from just before). Never edit an applied migration; add a new one.
Databases created before migrations existed are "baselined" automatically (InitialCreate recorded as applied).
Migrations are PostgreSQL-only; local SQL Server dev still uses EnsureCreated (`DB_AUTO_CREATE=true`).

After changing a model / `HrmsDbContext`, from `HrmsApi/` (bash):
```bash
dotnet tool restore
UsePostgreSQL=true ConnectionStrings__DefaultConnection="Host=localhost;Database=design;Username=x;Password=x" \
ASPNETCORE_ENVIRONMENT=Production JWT_SECRET_KEY=design-time-only-key-not-used-anywhere-1234567890 \
dotnet ef migrations add <DescriptiveName> --context HrmsDbContext
```
Company tables → `--context HrmsDbContext` (Migrations/). Master DB (companies, Super Admins) →
`--context PlatformDbContext -o Migrations/Platform`. Both are applied on startup (master first, then every company).
Review the generated file (watch for drops/renames that lose data), commit it with the model change, push to `uat`.
