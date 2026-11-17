# mars-tech — HRMS Payroll System

HRMS web app (Angular UI + .NET 8 API + PostgreSQL), self-hosted on a Hostinger VPS with
automatic UAT and production deployments.

| Folder | What |
|--------|------|
| [`hrms-ui/`](hrms-ui/) | Angular frontend |
| [`HrmsApi/`](HrmsApi/) | .NET 8 Web API (+ `HrmsApi.Tests`) |
| [`deploy/`](deploy/) | Docker / Caddy / scripts for the VPS — full ops guide in [`deploy/README.md`](deploy/README.md) |

## Environments

| | Production | UAT |
|---|---|---|
| URLs | https://marstech.tech · https://marshrms.com | https://uat.marstech.tech · https://uat.marshrms.com |
| Git branch | `main` (protected) | `uat` |
| Deploys | automatically when a PR `uat → main` is merged | automatically on every push to `uat` |
| Database | production data (backed up nightly + before every release) | separate UAT database |
| Server folder | `/opt/hrms` | `/opt/hrms-uat` |

Both domains serve the same apps; `www.` redirects to the bare domain. HTTPS is automatic (Let's Encrypt via Caddy).

## Companies (clients) and the Super Admin portal

One app serves every client company; **each company has its own database**, chosen from the web address:

| Address | What | Database |
|---|---|---|
| https://admin.marshrms.com | **Super Admin portal** — create, edit, suspend companies | `hrms_master` (company list, Super Admin accounts) |
| https://esync.marshrms.com | company "esync" | `hrms_esync` |
| https://marshrms.com | company "demo" (the original database) | `hrms` |

UAT works the same under `uat.`: `admin.uat.marshrms.com`, `esync.uat.marshrms.com` (own UAT databases).

**New client:** log in to the portal → **New company** → company name, web address, logo/colour, first admin
→ **Create company**. The database, tables, company details and admin account are created in seconds; the
admin gets an email with a link to set their password (the portal also shows a one-time temporary password).
HTTPS for the new address is issued automatically on its first visit (up to a minute).

Super Admin login: user `superadmin`, first password from `SUPERADMIN_PASSWORD` in the server `.env` / `.env.uat`
(change it under **My account**). Company logins and Super Admin logins are separate; a login only works on the
address where it was made.

## Release process

```
code ──push──▶ uat branch ──auto (~5-10 min)──▶ uat.marstech.tech     (test here)
                    │
     Pull Request uat → main   (you review + click Merge on GitHub)
                    ▼
               main branch ──auto (~5-10 min)──▶ marstech.tech / marshrms.com
                                                  (DB backup taken first)
```

1. Commit and push to **`uat`**: `git checkout uat && git pull && … && git push`
2. Test on https://uat.marstech.tech
3. Release: open https://github.com/Mohanreddy88/mars-tech/compare/main...uat → **Create pull request** → **Merge**
4. Production updates itself. Never push to `main` directly — GitHub rejects it (ruleset `protect-main`).

If a build fails, the site keeps running the previous version; fix and push again.
Logs: `ssh root@189.72.155.35 'tail -20 /var/log/hrms-prod-deploy.log'` (or `hrms-uat-deploy.log`).

## Database changes
Schema changes use **EF Core migrations**: every database (production, UAT, each client) is updated
automatically when the new version starts. After changing a model, create a migration in `HrmsApi/`
(exact command in [CLAUDE.md](CLAUDE.md#database-changes--ef-core-migrations-postgresql)), commit it, and push to `uat`.
Never edit a migration that has already been released; add a new one.

## Server

| Item | Value |
|------|-------|
| VPS | Hostinger KVM 2 — `189.72.155.35` (Ubuntu 22.04) |
| SSH | `ssh root@189.72.155.35` — key-based only |
| DNS | Hostinger hPanel, both domains: `A @`, `A www`, `A uat`, `A *` (companies + portal), `A *.uat` → `189.72.155.35` |
| Email | Hostinger SMTP `smtp.hostinger.com:587` as `support@marstech.tech` |
| Secrets | only on the server: `/opt/hrms/deploy/.env` and `/opt/hrms-uat/deploy/.env.uat` |

### Working from a new PC
1. `git clone https://github.com/Mohanreddy88/mars-tech.git`
2. Create an SSH key: `ssh-keygen -t ed25519` and add the `.pub` contents in
   hPanel → VPS → Settings → SSH keys (or append it to `/root/.ssh/authorized_keys` from a PC that already has access).
3. Local API development: copy `HrmsApi/appsettings.Development.example.json` to
   `appsettings.Development.json` and fill in your local values (this file is git-ignored).

## Security rules
- This repository is **public**. Never commit passwords, API keys, `.env` files or `appsettings.Development.json`.
- Change the default `admin` / `Admin@123` login on the original (demo) database. Companies created in the
  portal never get that default login.
- Change the Super Admin password after the first login (portal → My account).
