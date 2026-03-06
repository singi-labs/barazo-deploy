# Production Deployment Checklist

Step-by-step checklist for deploying Barazo to production on a Hetzner VPS.

This checklist covers the first production deployment of `barazo.forum`. For self-hosted installations, see [Installation Guide](installation.md).

## Pre-Deployment

### Server Provisioning

- [ ] Provision Hetzner CX32 VPS (4 vCPU, 8 GB RAM, 80 GB SSD)
  - Location: Falkenstein or Helsinki (EU)
  - OS: Ubuntu 24.04 LTS
- [ ] Note the server's IPv4 and IPv6 addresses
- [ ] SSH into the server and verify access: `ssh root@<IP>`

### DNS Configuration

- [ ] Create A record: `barazo.forum` -> server IPv4
- [ ] Create AAAA record: `barazo.forum` -> server IPv6
- [ ] Verify DNS propagation: `dig +short barazo.forum`
- [ ] Verify reverse DNS (optional but recommended for email deliverability): set PTR record in Hetzner Cloud console

### Server Setup

- [ ] Update system packages:
  ```bash
  apt update && apt upgrade -y
  ```
- [ ] Create non-root deploy user:
  ```bash
  adduser barazo
  usermod -aG sudo barazo
  ```
- [ ] Copy SSH key for deploy user:
  ```bash
  su - barazo
  mkdir -p ~/.ssh
  # Add your public key to ~/.ssh/authorized_keys
  chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys
  ```
- [ ] Disable root SSH login (see [Security Hardening Guide](security-hardening.md))
- [ ] Install Docker:
  ```bash
  curl -fsSL https://get.docker.com | sh
  sudo usermod -aG docker barazo
  # Log out and back in
  ```
- [ ] Verify Docker:
  ```bash
  docker --version        # v24+
  docker compose version  # v2+
  ```

## Deployment

### Application Setup

- [ ] Clone deploy repo:
  ```bash
  git clone https://github.com/singi-labs/barazo-deploy.git
  cd barazo-deploy
  ```
- [ ] Create `.env` from template:
  ```bash
  cp .env.example .env
  ```
- [ ] Generate secrets (run each one and paste into `.env`):
  ```bash
  # POSTGRES_PASSWORD
  openssl rand -base64 24
  # VALKEY_PASSWORD
  openssl rand -base64 24
  # TAP_ADMIN_PASSWORD
  openssl rand -base64 24
  # SESSION_SECRET
  openssl rand -base64 32
  # AI_ENCRYPTION_KEY (required for BYOK features)
  openssl rand -base64 32
  ```
- [ ] Configure `.env` with production values:

  | Variable | Value |
  |----------|-------|
  | `COMMUNITY_NAME` | `Barazo` |
  | `COMMUNITY_DOMAIN` | `barazo.forum` |
  | `COMMUNITY_MODE` | `global` |
  | `POSTGRES_PASSWORD` | (generated above) |
  | `VALKEY_PASSWORD` | (generated above) |
  | `DATABASE_URL` | `postgresql://barazo_app:<POSTGRES_PASSWORD>@postgres:5432/barazo` |
  | ~~`MIGRATION_DATABASE_URL`~~ | Not used in alpha. Reserved for beta when migrations are needed. |
  | `TAP_ADMIN_PASSWORD` | (generated above) |
  | `SESSION_SECRET` | (generated above) |
  | `OAUTH_CLIENT_ID` | `https://barazo.forum` |
  | `OAUTH_REDIRECT_URI` | `https://barazo.forum/api/auth/callback` |
  | `NEXT_PUBLIC_SITE_URL` | `https://barazo.forum` |
  | `GLITCHTIP_DSN` | (production GlitchTip DSN) |
  | `AI_ENCRYPTION_KEY` | (generated above) |

- [ ] Pin Docker image versions in `docker-compose.yml`:
  ```yaml
  barazo-api:
    image: ghcr.io/singi-labs/barazo-api:X.Y.Z
  barazo-web:
    image: ghcr.io/singi-labs/barazo-web:X.Y.Z
  ```
- [ ] Verify no `CHANGE_ME` values remain:
  ```bash
  grep -n "CHANGE_ME" .env
  ```

### Start Services

- [ ] Pull images:
  ```bash
  docker compose pull
  ```
- [ ] Start the stack:
  ```bash
  docker compose up -d
  ```
- [ ] Watch startup logs:
  ```bash
  docker compose logs -f
  ```

## Post-Deployment Verification

### Health Checks

- [ ] All containers healthy:
  ```bash
  docker compose ps
  # All services should show "healthy"
  ```
- [ ] API health check:
  ```bash
  curl -s https://barazo.forum/api/health | jq .
  ```
- [ ] Run smoke test:
  ```bash
  ./scripts/smoke-test.sh https://barazo.forum
  ```

### SSL Verification

- [ ] HTTPS works: visit `https://barazo.forum` in browser
- [ ] HTTP redirects to HTTPS: `curl -I http://barazo.forum`
- [ ] Certificate is valid:
  ```bash
  echo | openssl s_client -connect barazo.forum:443 -servername barazo.forum 2>/dev/null | openssl x509 -noout -dates
  ```
- [ ] HSTS header present:
  ```bash
  curl -sI https://barazo.forum | grep -i strict-transport
  ```

### Functional Verification

- [ ] Homepage renders in browser
- [ ] OAuth login redirects to Bluesky correctly
- [ ] API documentation accessible at `https://barazo.forum/docs`
- [ ] `/api/health/ready` blocked externally (returns 403):
  ```bash
  curl -s -o /dev/null -w "%{http_code}" https://barazo.forum/api/health/ready
  ```

### Backup Setup

- [ ] Generate backup encryption keypair:
  ```bash
  sudo apt install age
  age-keygen -o barazo-backup-key.txt
  # Add public key to .env as BACKUP_PUBLIC_KEY
  # Store private key OFF-SERVER (e.g., password manager)
  ```
- [ ] Test backup:
  ```bash
  ./scripts/backup.sh --encrypt
  ls -lh backups/
  ```
- [ ] Set up automated daily backups:
  ```bash
  crontab -e
  ```
  ```
  0 2 * * * cd /home/barazo/barazo-deploy && ./scripts/backup.sh --encrypt >> /var/log/barazo-backup.log 2>&1
  ```
- [ ] Verify backup cron runs (check next day):
  ```bash
  ls -lh backups/
  tail /var/log/barazo-backup.log
  ```

### Monitoring

- [ ] GlitchTip DSN configured and receiving events
- [ ] Test error reporting:
  ```bash
  # Trigger a test error via the API (if endpoint exists)
  # Or check GlitchTip dashboard for startup events
  ```
- [ ] Log output visible:
  ```bash
  docker compose logs --tail=20 barazo-api
  ```

### Security Hardening

- [ ] Complete the [Security Hardening Guide](security-hardening.md) checklist
- [ ] Firewall configured (only 22, 80, 443 open)
- [ ] SSH root login disabled
- [ ] Unattended upgrades enabled

## Ongoing Operations

### Upgrades

See [Upgrade Guide](upgrading.md) for the standard upgrade process:

```bash
# Update image tags in docker-compose.yml, then:
docker compose pull
docker compose up -d
```

### Rollback

If an upgrade causes issues:

```bash
# Revert image tags in docker-compose.yml to previous versions, then:
docker compose pull
docker compose up -d
```

During alpha, the database schema is rebuilt on deploy. If a schema change causes issues, restore from backup (see [Backup & Restore](backups.md)).

### Daily Checks

- [ ] `docker compose ps` -- all services healthy
- [ ] Check GlitchTip for new errors
- [ ] Verify backup ran (check `/var/log/barazo-backup.log`)
