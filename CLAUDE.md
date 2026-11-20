# CLAUDE.md

Guidance for Claude Code in this repo. Human-facing overview: [README.md](README.md); ops details: [deploy/README.md](deploy/README.md).

## Project
HRMS payroll system: `hrms-ui/` (Angular, prod build `npm run build:prod`), `HrmsApi/` (.NET 8, EF Core;
PostgreSQL in deployment, SQL Server locally). The test project `HrmsApi/HrmsApi.Tests` sits inside the API folder
and is excluded from the API csproj.
`hrms_mobile/` is the Flutter employee app (Riverpod, Dio, go_router) calling the same API; it is not part of the
server deploy (excluded in `.dockerignore`). API base URL via `--dart-define=API_BASE_URL=...` (default
`http://10.0.2.2:64559/api` = local API from the Android emulator; company picked by host name). Flutter SDK on this PC
is not on PATH: `C:\Users\HP\Downloads\flutter_windows_3.50.0-stable\flutter\bin\flutter.bat`. When an API response
changes, update the matching model in `hrms_mobile/lib/features/*/data/`. Never commit keystores, `key.properties`
or `google-services.json`.

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
