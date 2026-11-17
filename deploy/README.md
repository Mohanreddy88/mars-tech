# HRMS on Hostinger VPS (marstech.tech)

Stack: **Caddy** (HTTPS, auto Let's Encrypt) → **app** (nginx + Angular + .NET API) → **PostgreSQL 16**.
All in Docker; DB is not exposed to the internet. Railway deployment is untouched.

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
