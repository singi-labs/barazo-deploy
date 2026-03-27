# Staging Environment

**URL:** https://staging.barazo.forum
**Host:** Hetzner VPS (46.225.136.40)
**Deploy user:** `deploy`
**Deploy path:** `/opt/barazo`

## Automated Deployment

Pushes to `main` in `barazo-api` or `barazo-web` automatically trigger a staging deploy.

### Flow

```
Push to main (api or web)
  -> repository_dispatch event -> barazo-deploy
       -> Checkout all repos (deploy, lexicons, api, web)
       -> Build Docker images (amd64 only)
       -> Push to ghcr.io/singi-labs/*
       -> SSH to staging VPS:
            1. Save current image digests (for rollback)
            2. Check .env.example for new required vars
            3. docker compose pull (api + web only)
            4. docker compose up -d
            5. Watch logs for 30s -- grep crash patterns
            6. Check Docker healthcheck status (API + Web)
            7. If unhealthy: auto-rollback to previous digests
```

### Trigger Repos

Both `barazo-api` and `barazo-web` have `.github/workflows/deploy-staging.yml` that fire a `repository_dispatch` event to `barazo-deploy` on push to `main`.

The dispatch payload includes the triggering repo name and the exact commit SHA, so the deploy workflow builds the correct version.

### Manual Trigger

Go to **Actions > Deploy to Staging > Run workflow** in the `barazo-deploy` repo. You can override the API and Web branch/tag refs.

### Rollback Behavior

Before deploying, the workflow saves the current running image digests. If post-deploy checks fail (crash patterns in logs or health endpoints returning non-200), the workflow:

1. Pulls the previously-saved image digests
2. Tags them as `:latest`
3. Runs `docker compose up -d` to restore the previous version
4. Reports the failure in the workflow summary

### Crash Pattern Detection

The log check greps for these patterns (case-insensitive):

- `FATAL`
- `ECONNREFUSED`
- `missing env`
- `ERR_MODULE_NOT_FOUND` / `Cannot find module`
- `segfault`
- `OOMKilled`

### Env Var Drift Detection

The workflow compares variable names in `.env.example` against the staging `.env` file. Missing vars are reported as warnings but do not block deployment (they may be optional).

## Required Secrets

| Secret | Scope | Purpose |
|--------|-------|---------|
| `STAGING_SSH_KEY` | GitHub org secret | Ed25519 SSH private key for `deploy` user |
| `DEPLOY_PAT` | GitHub org secret | PAT with `repo` scope for cross-repo dispatch |

### Setting Up Secrets

```bash
# Generate SSH keypair
ssh-keygen -t ed25519 -f barazo-staging-deploy -C "github-actions-staging"

# Add public key to VPS
ssh root@staging.barazo.forum "cat >> /home/deploy/.ssh/authorized_keys" < barazo-staging-deploy.pub

# Add private key as org secret: STAGING_SSH_KEY
# Create GitHub PAT (repo scope), add as org secret: DEPLOY_PAT
```

## Deploy User Setup

```bash
ssh root@staging.barazo.forum

# Create deploy user
useradd -m -s /bin/bash deploy
usermod -aG docker deploy

# SSH access
mkdir -p /home/deploy/.ssh
chmod 700 /home/deploy/.ssh
chown -R deploy:deploy /home/deploy/.ssh
# Add GitHub Actions public key to /home/deploy/.ssh/authorized_keys
chmod 600 /home/deploy/.ssh/authorized_keys

# Link deploy path
ln -s /opt/barazo /home/deploy/barazo
```

## Diagnostics

Use the `/staging-status` Claude Code skill for quick SSH-based triage:

```
/staging-status
```

This checks container health, recent logs, disk/memory usage, missing env vars, and image versions.

## Monitoring

This VPS is the monitoring hub for all Singi Labs VPSes. It runs Prometheus, Grafana, node_exporter, and cAdvisor locally, and scrapes remote VPSes over WireGuard.

| Component | Purpose |
|-----------|---------|
| Prometheus | Scrapes and stores metrics (30-day retention) |
| Grafana | Dashboards and alerting at `monitoring.singi.dev` |
| node_exporter | Host CPU, RAM, disk, network metrics |
| cAdvisor | Per-container resource metrics |
| WireGuard | VPN tunnel to remote VPSes (10.10.0.0/24) |
| socat | Port forwards from localhost to WireGuard IPs for Prometheus |

The monitoring stack runs from a separate repo: [singi-labs/monitoring](https://github.com/singi-labs/monitoring). See its README for full setup instructions, WireGuard configuration, and how to add new VPSes.

### WireGuard Peers

| VPS | WireGuard IP | Ports forwarded via socat |
|-----|-------------|--------------------------|
| Barazo staging (this VPS) | 10.10.0.1 | n/a (local Docker network) |
| Sifa production | 10.10.0.2 | 9101->9100, 9102->8080 |
| Barazo production (future) | 10.10.0.3 | 9103->9100, 9104->8080 |

## Compose Files

Staging uses the overlay pattern:

```bash
docker compose -f docker-compose.yml -f docker-compose.staging.yml -f docker-compose.monitoring-proxy.yml up -d
```

The staging override (`docker-compose.staging.yml`) sets:
- `:edge` image tags (`:latest` is reserved for stable releases)
- `NODE_ENV: staging`
- `LOG_LEVEL: debug`
- Relaxed rate limits for testing

The monitoring proxy overlay (`docker-compose.monitoring-proxy.yml`) connects Caddy to the monitoring stack's Docker network so it can reverse-proxy Grafana. The monitoring stack itself (Prometheus, Grafana, node_exporter, cAdvisor) runs from a separate repo at `/opt/monitoring`.

## Image Tags

Each deploy produces two tags per image:
- `:edge` -- always points to the most recent staging build
- `:staging-{run_number}` -- immutable tag for traceability

`:latest` is reserved for stable releases pushed by the `docker.yml` workflow on `v*` tags.
