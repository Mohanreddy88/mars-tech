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

## Server

| Item | Value |
|------|-------|
| VPS | Hostinger KVM 2 — `189.72.155.35` (Ubuntu 22.04) |
| SSH | `ssh root@189.72.155.35` — key-based only |
| DNS | Hostinger hPanel, both domains: `A @`, `A www`, `A uat` → `189.72.155.35` |
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
- Change the default `admin` / `Admin@123` login on every new database.
