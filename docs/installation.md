# Installation Guide

Step-by-step guide to deploying a Barazo forum on your own server.

## Prerequisites

- **VPS or dedicated server** with a public IP address
  - Minimum: 2 vCPU, 4 GB RAM, 20 GB SSD (Hetzner CX22 recommended)
  - Linux (Ubuntu 22.04+ or Debian 12+ recommended)
- **Domain name** with a DNS A record pointing to your server's IP
- **Docker** v24+ and **Docker Compose** v2
- **SSH access** to your server

## 1. Install Docker

If Docker is not already installed:

```bash
# Install Docker (official script)
curl -fsSL https://get.docker.com | sh

# Add your user to the docker group (avoids sudo for docker commands)
sudo usermod -aG docker $USER

# Log out and back in for group change to take effect
exit
# SSH back in

# Verify
docker --version
docker compose version
```

## 2. Clone the Repository

```bash
git clone https://github.com/singi-labs/barazo-deploy.git
cd barazo-deploy
```

## 3. Configure Environment

```bash
cp .env.example .env
nano .env  # or your preferred editor
```

**Required variables to set:**

| Variable | What to set |
|----------|-------------|
| `COMMUNITY_NAME` | Your forum's display name |
| `COMMUNITY_DOMAIN` | Your domain (e.g., `forum.example.com`) |
| `POSTGRES_PASSWORD` | Strong random password |
| `VALKEY_PASSWORD` | Strong random password |
| `TAP_ADMIN_PASSWORD` | Strong random password |
| `DATABASE_URL` | Update the password to match `POSTGRES_PASSWORD` |
| `OAUTH_CLIENT_ID` | `https://your-domain.com` |
| `OAUTH_REDIRECT_URI` | `https://your-domain.com/api/auth/callback` |
| `NEXT_PUBLIC_SITE_URL` | `https://your-domain.com` |

Generate passwords with:

```bash
openssl rand -base64 24
```

## 4. Start Services

```bash
docker compose up -d
```

This starts all 6 services: PostgreSQL, Valkey, Tap, API, Web, and Caddy.

First startup may pull several Docker images (allow a few minutes on slower connections).

## 5. Verify Installation

```bash
# Check all services are running
docker compose ps

# Run smoke test
./scripts/smoke-test.sh https://your-domain.com
```

All services should show `healthy` status. Caddy automatically obtains an SSL certificate from Let's Encrypt on first request.

Visit `https://your-domain.com` in your browser. You should see the Barazo forum.

## 6. First-Time Setup

The first user to complete the setup wizard becomes the community administrator. Open your forum URL and follow the on-screen instructions to:

1. Sign in with your AT Protocol account (Bluesky)
2. Set community name and description
3. Create initial categories
4. Configure moderation settings

## Troubleshooting

**Caddy fails to obtain SSL certificate:**

- Verify your DNS A record points to the server's IP: `dig +short your-domain.com`
- Ensure ports 80 and 443 are open in your firewall
- Check Caddy logs: `docker compose logs caddy`

**Services fail to start:**

- Check logs: `docker compose logs`
- Verify `.env` has no syntax errors
- Ensure all required variables are set (no `CHANGE_ME` remaining)

**Database connection errors:**

- Verify `DATABASE_URL` password matches `POSTGRES_PASSWORD`
- Check PostgreSQL logs: `docker compose logs postgres`

See also: [Troubleshooting](administration.md#troubleshooting) in the Administration Guide.

## Staging Environment

The staging environment runs at `staging.barazo.forum` and is used for integration testing, OAuth validation, and firehose testing before production deploys. It uses `:latest` Docker images that auto-update on new releases.

### Setup

```bash
# Clone the repo on your staging VPS
git clone https://github.com/singi-labs/barazo-deploy.git
cd barazo-deploy

# Copy the staging template and fill in secrets
cp .env.staging .env
nano .env  # Replace all CHANGE_ME values with real secrets
```

Generate secrets:

```bash
openssl rand -base64 24   # For POSTGRES_PASSWORD, VALKEY_PASSWORD, TAP_ADMIN_PASSWORD
openssl rand -base64 32   # For SESSION_SECRET
```

### Start Staging

```bash
docker compose -f docker-compose.yml -f docker-compose.staging.yml up -d
```

The staging overlay applies:
- `:latest` image tags (auto-updates on new releases)
- `NODE_ENV=staging` and `LOG_LEVEL=debug`
- Relaxed rate limits for testing

### Seed Test Data

After the first deployment (or after a reset), populate the database with test data:

```bash
./scripts/seed-staging.sh
```

This creates 5 categories, 5 test users, 10 topics, and 18 replies. Use `--minimal` to seed only categories.

### Reset Staging

To wipe all staging data and start fresh:

```bash
./scripts/reset-staging.sh
```

This drops and recreates the database, flushes the cache, and restarts all services. The schema is applied automatically on startup. Run `seed-staging.sh` afterward to repopulate test data.

### Smoke Test

```bash
./scripts/smoke-test.sh https://staging.barazo.forum
```

### Staging vs. Production Differences

| Setting | Staging | Production |
|---------|---------|------------|
| Image tags | `:latest` | Pinned versions (`:2.5.3`) |
| `NODE_ENV` | `staging` | `production` |
| `LOG_LEVEL` | `debug` | `info` |
| Rate limits | Relaxed (1000 req/min) | Standard |
| Database | `barazo_staging` | `barazo` |
| SSL | Automatic (Let's Encrypt staging) | Automatic (Let's Encrypt) |
