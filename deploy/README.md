# HRMS on Hostinger VPS (marstech.tech)

Stack: **Caddy** (HTTPS, auto Let's Encrypt) → **app** (nginx + Angular + .NET API) → **PostgreSQL 16**.
All in Docker; DB is not exposed to the internet. Railway deployment is untouched.

## Live server (deployed 2026-11-17)
| Item | Value |
|------|-------|
| Site | https://marstech.tech (`www` redirects to apex) |
| VPS | Hostinger KVM 2 — `189.72.155.35`, Ubuntu 22.04, 2 vCPU / 8 GB / 100 GB, 4 GB swap |
| SSH | `ssh root@189.72.155.35` (key-based; add keys in hPanel → VPS → SSH keys) |
| Code on server | `/opt/hrms` (clone of this repo) |
| Secrets | `/opt/hrms/deploy/.env` on the server only — DB password, JWT key, SMTP password |
| DNS | `A @ → 189.72.155.35`; `CNAME www → marstech.tech`; Hostinger mail MX/SPF/DKIM records unchanged |
| Email | Hostinger SMTP `smtp.hostinger.com:587` as `support@marstech.tech` |
| HTTPS | Let's Encrypt via Caddy, renews automatically |
| Firewall | ufw: SSH, 80, 443 only |
| Backups | cron 02:30 daily → `/opt/hrms-backups` (14 days) |

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
Push to `main` locally, then on the VPS: `cd /opt/hrms/deploy && bash deploy.sh`

## 5. Backups (nightly 02:30, 14 days kept in /opt/hrms-backups)
```bash
chmod +x /opt/hrms/deploy/backup.sh
(crontab -l 2>/dev/null; echo "30 2 * * * /opt/hrms/deploy/backup.sh >> /var/log/hrms-backup.log 2>&1") | crontab -
```
Restore: `docker compose exec -T db pg_restore -U hrms -d hrms --clean < /opt/hrms-backups/db-XXXX.dump`

## Useful commands
```bash
docker compose ps
docker compose logs -f app      # API / nginx logs
docker compose logs -f caddy    # HTTPS certificate issues
docker compose restart app
docker compose exec db psql -U hrms -d hrms
```

## Troubleshooting
- **HTTPS not working** → DNS not pointing to VPS yet, or ports 80/443 blocked. Check `docker compose logs caddy`.
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

### UAT auto-deploy
Every push to the `uat` branch is deployed automatically within ~2 minutes (+ build time, ~3-8 min).
A cron job on the VPS runs `deploy/auto-deploy-uat.sh` every 2 minutes; it pulls and rebuilds only when
`origin/uat` has a new commit. A failed commit is not retried until you push a newer one.

- Log: `tail -f /var/log/hrms-uat-deploy.log`
- Pause: `crontab -e` and comment out the `auto-deploy-uat.sh` line
