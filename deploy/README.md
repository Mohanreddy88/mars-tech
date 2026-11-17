# HRMS on Hostinger VPS (marstech.tech)

Stack: **Caddy** (HTTPS, auto Let's Encrypt) → **app** (nginx + Angular + .NET API) → **PostgreSQL 16**.
All in Docker; DB is not exposed to the internet. Railway deployment is untouched.

## Live server (deployed 2026-11-17)
| Item | Value |
|------|-------|
| Site | https://marstech.tech and https://marshrms.com — same app (`www.` redirects to apex) |
| VPS | Hostinger KVM 2 — `189.72.155.35`, Ubuntu 22.04, 2 vCPU / 8 GB / 100 GB, 4 GB swap |
| SSH | `ssh root@189.72.155.35` (key-based; add keys in hPanel → VPS → SSH keys) |
| Code on server | `/opt/hrms` (clone of this repo) |
| Secrets | `/opt/hrms/deploy/.env` on the server only — DB password, JWT key, SMTP password |
| DNS | both domains: `A @`, `A www` (or `CNAME www`), `A uat`, `A *`, `A *.uat` → `189.72.155.35`; Hostinger mail MX/SPF/DKIM records unchanged |
| Email links | `FrontendUrl` (env `FRONTEND_URL` in `.env` / `.env.uat`) — default https://marshrms.com / https://uat.marshrms.com |
| Email | Hostinger SMTP `smtp.hostinger.com:587` as `support@marstech.tech` |
| HTTPS | Let's Encrypt via Caddy, renews automatically |
| Firewall | ufw: SSH, 80, 443 only |
| Backups | cron 02:30 daily → `/opt/hrms-backups` (14 days) |
| Companies | one database per company (`hrms_<code>`), list in `hrms_master`; portal https://admin.marshrms.com |

**Deploy an update:** push to `main`, then `ssh root@189.72.155.35 'cd /opt/hrms/deploy && bash deploy.sh'`

**Change the email password:** edit `SMTP_PASSWORD='...'` in `/opt/hrms/deploy/.env` (keep the single quotes), then `docker compose up -d app`.

The sections below describe how this server was set up, for rebuilding it from scratch.

## 1. DNS (Hostinger hPanel → Domains → marstech.tech → DNS / Nameservers)
| Type | Name | Points to        | TTL |
|------|------|------------------|-----|
| A    | @    | `<VPS IPv4>`     | 300 |
| A    | www  | `<VPS IPv4>`     | 300 |

Delete any existing A/AAAA/CNAME records for `@` and `www` that point elsewhere (e.g. Hostinger parking).
Check: `nslookup marstech.tech` should return the VPS IP.

## 2. VPS OS
hPanel → VPS → OS & Panel → **Ubuntu 24.04 (plain OS)**. Note the root password / add your SSH key.

## 3. Install (on the VPS as root)
```bash
ssh root@<VPS IP>
git clone https://github.com/Mohanreddy88/mars-tech.git /opt/hrms
bash /opt/hrms/deploy/setup-vps.sh      # installs Docker, firewall, swap, generates .env
nano /opt/hrms/deploy/.env              # optional: SMTP/Brevo email settings
cd /opt/hrms/deploy && bash deploy.sh   # builds & starts (first build ~5-10 min)
```
> The repo is public, so no token is needed. **Never commit `deploy/.env` or `HrmsApi/appsettings.Development.json`** (both are git-ignored).

Open https://marstech.tech → login `admin` / `Admin@123` → **change the password immediately**.

On first start the empty DB schema is created automatically from the EF model (`DB_AUTO_CREATE=true`)
and leave types + admin user are seeded.

## 4. Updates
Automatic — see "Auto-deploy" below. Manual fallback on the VPS: `cd /opt/hrms/deploy && bash deploy.sh`

## 5. Backups (nightly 02:30, 14 days kept in /opt/hrms-backups)
```bash
chmod +x /opt/hrms/deploy/backup.sh
(crontab -l 2>/dev/null; echo "30 2 * * * /opt/hrms/deploy/backup.sh >> /var/log/hrms-backup.log 2>&1") | crontab -
```
Every database is dumped separately: `db-<database>-<stamp>.dump` (`hrms_master`, `hrms` = demo, `hrms_esync`, …),
so one company can be restored without touching the others:
```bash
docker compose exec -T db pg_restore -U hrms -d hrms_esync --clean < /opt/hrms-backups/db-hrms_esync-XXXX.dump
```

## Useful commands
```bash
docker compose ps
docker compose logs -f app      # API / nginx logs
docker compose logs -f caddy    # HTTPS certificate issues
docker compose restart app
docker compose exec db psql -U hrms -d hrms
```

## Companies (multi-tenant)
One app, one database per company. The API picks the database from the host name
(`HrmsApi/Platform/TenantResolutionMiddleware.cs`): `esync.marshrms.com` → company `esync` → `hrms_esync`;
the bare domain → company `demo` (the original database); `admin.` → Super Admin portal.

- Settings (compose env): `Tenancy__Enabled=true`, `Tenancy__BaseDomains` (`TENANT_DOMAINS`), `SUPERADMIN_PASSWORD`.
- New company = portal → **New company** (creates the database, runs migrations, saves company details,
  creates the admin). On every start the app migrates every company database.
- HTTPS for company addresses: Caddy `on_demand_tls` issues a certificate on the first visit, but only after
  asking the app (`/api/platform/domain-check`) that the name is the portal or a registered company.
- Suspend (portal) blocks a company's logins and API; data is kept. Activate reverses it.
- Super Admin password lost: `docker compose exec db psql -U hrms -d hrms_master -c 'DELETE FROM "PlatformUsers"'`,
  set a new `SUPERADMIN_PASSWORD` in `.env`, `docker compose up -d app` (recreated on start).

## Troubleshooting
- **HTTPS not working** → DNS not pointing to VPS yet, or ports 80/443 blocked. Check `docker compose logs caddy`.
- **New company address shows a certificate error** → wildcard DNS `*` (or `*.uat`) missing, or the company
  code is not registered. `docker compose logs caddy | grep -i on_demand`.
- **Build killed / out of memory** → confirm swap: `swapon --show`.
- **App can't reach DB** → `docker compose logs db`; passwords in `.env` must not change after first start
  (Postgres keeps the original password in the `pgdata` volume).

## UAT environment (https://uat.marstech.tech)
Separate stack on the same VPS: own database, uploads and image. Deploys from the **`uat`** branch.

| | Production | UAT |
|---|---|---|
| URL | https://marstech.tech | https://uat.marstech.tech |
| Branch | `main` | `uat` |
| Server folder | `/opt/hrms` | `/opt/hrms-uat` |
| Compose | `docker-compose.yml` + `.env` | `docker-compose.uat.yml` + `.env.uat` |
| Deploy | `bash deploy.sh` | `bash deploy-uat.sh` |

DNS: `A uat → 189.72.155.35`. The production Caddy serves both sites; it reaches the UAT app over the
shared Docker network `web` (alias `uat-app`). UAT pages send `X-Robots-Tag: noindex`.

**Workflow:** push to `uat` → `ssh root@189.72.155.35 'cd /opt/hrms-uat/deploy && bash deploy-uat.sh'` →
testers sign off on uat.marstech.tech → merge `uat` into `main` → `bash deploy.sh` in `/opt/hrms/deploy`.

UAT logs: `cd /opt/hrms-uat/deploy && docker compose -f docker-compose.uat.yml --env-file .env.uat logs -f app`

### Auto-deploy (UAT and production)
```
push to uat ──auto──▶ uat.marstech.tech   (testers sign off)
merge uat → main (manual approval) ──auto──▶ marstech.tech
```
A cron job on the VPS runs `deploy/auto-deploy.sh uat` and `deploy/auto-deploy.sh prod` every 2 minutes.
Each checks its branch (`uat` / `main`) and rebuilds only when there is a new commit — changes go live in
~5-10 minutes. Production takes a DB + uploads backup (`backup.sh`) before every deploy. Only one deploy
runs at a time. A failed commit is not retried until you push a newer one; the site keeps running the
previous version.

- Logs: `tail -f /var/log/hrms-uat-deploy.log` / `tail -f /var/log/hrms-prod-deploy.log`
- Pause one: `crontab -e` and comment out its `auto-deploy.sh` line
- `main` is protected on GitHub: direct pushes and force pushes are rejected, changes arrive only via Pull Request.

**Release:** on GitHub open a Pull Request **base `main` ← compare `uat`** (https://github.com/Mohanreddy88/mars-tech/compare/main...uat) and click **Merge**. Production deploys automatically.

**Roll back production:** `git revert` the bad commit on `main` and push (auto-deploys), or restore the DB
backup taken just before the release (see Backups).
