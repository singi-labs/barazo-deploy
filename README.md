<div align="center">

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/singi-labs/.github/main/assets/logo-dark.svg">
  <source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/singi-labs/.github/main/assets/logo-light.svg">
  <img alt="Barazo Logo" src="https://raw.githubusercontent.com/singi-labs/.github/main/assets/logo-dark.svg" width="120">
</picture>

# Barazo Deploy

**Docker Compose templates for self-hosting Barazo forums.**

[![Status: Alpha](https://img.shields.io/badge/status-alpha-orange)]()
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Validate](https://github.com/singi-labs/barazo-deploy/actions/workflows/validate-compose.yml/badge.svg)](https://github.com/singi-labs/barazo-deploy/actions/workflows/validate-compose.yml)

</div>

---

## Overview

Everything you need to self-host a [Barazo](https://github.com/singi-labs) forum. Includes Docker Compose templates for development, production (single community), and global aggregator deployments. Automatic SSL via Caddy, backup/restore scripts, and network segmentation out of the box.

---

## Docker Compose Templates

| File | Purpose |
|------|---------|
| `docker-compose.dev.yml` | Local development -- infrastructure services only (PostgreSQL, Valkey, Tap). Run API and Web separately with `pnpm dev`. |
| `docker-compose.yml` | Production single-community deployment with automatic SSL via Caddy. Full stack. |
| `docker-compose.global.yml` | Global aggregator override -- layers on top of `docker-compose.yml` with higher resource limits and PostgreSQL tuning for indexing all communities network-wide. |

---

## Services

| Service | Image | Description |
|---------|-------|-------------|
| PostgreSQL 16 | `pgvector/pgvector:pg16` | Primary database with pgvector for full-text and optional semantic search |
| Valkey 8 | `valkey/valkey:8-alpine` | Redis-compatible cache for sessions, rate limiting, and queues |
| Tap | `ghcr.io/bluesky-social/indigo/tap:latest` | AT Protocol firehose consumer, filters `forum.barazo.*` records |
| Barazo API | `ghcr.io/singi-labs/barazo-api` | AppView backend (Fastify, REST API, firehose indexing) |
| Barazo Web | `ghcr.io/singi-labs/barazo-web` | Next.js frontend |
| Caddy | `caddy:2-alpine` | Reverse proxy with automatic SSL via Let's Encrypt, HTTP/3 support |

Production uses two-network segmentation: PostgreSQL and Valkey sit on the `backend` network only and are unreachable from Caddy or the frontend. Only ports 80 and 443 are exposed externally.

---

## Image Tags

Barazo API and Web images are published to [GitHub Container Registry](https://github.com/orgs/singi-labs/packages) (`ghcr.io/singi-labs/*`).

| Tag | Meaning | When to use |
|-----|---------|-------------|
| `:latest` | Latest stable release | **Production.** Self-hosters should pin to this or a specific version. |
| `:1.0.0`, `:1.0`, `:1` | Semver release tags | **Production.** Pin to a major or minor version for controlled upgrades. |
| `:edge` | Latest build from `main` | **Staging/testing only.** Rebuilt on every push to `main`. May contain breaking changes. |
| `:staging-{N}` | Immutable per-build tag | **Debugging.** Trace a specific staging deploy to its build number. |
| `:sha-{hash}` | Git commit SHA | **Debugging.** Trace an image to its exact source commit. |

**For self-hosters:** Use `:latest` or pin to a semver tag in your `.env`:

```bash
BARAZO_API_VERSION=1.0.0
BARAZO_WEB_VERSION=1.0.0
```

The production `docker-compose.yml` reads these variables (defaults to `latest` if unset).

---

## Deployment Modes

**Development:**

Infrastructure services only. Run API and Web locally with `pnpm dev`.

```bash
cp .env.example .env.dev
docker compose -f docker-compose.dev.yml up -d
```

Services exposed on the host: PostgreSQL (5432), Valkey (6379), Tap (2480).

**Production -- Single Community:**

Full stack deployment for one forum community with automatic SSL.

```bash
cp .env.example .env
# Edit .env: set COMMUNITY_DOMAIN, passwords, COMMUNITY_DID, OAuth settings
docker compose up -d
```

The forum will be available at `https://<COMMUNITY_DOMAIN>` once Caddy obtains the SSL certificate.

**Global Aggregator:**

Indexes all Barazo communities across the AT Protocol network.

```bash
cp .env.example .env
# Edit .env: set COMMUNITY_MODE=global, domain, passwords
docker compose -f docker-compose.yml -f docker-compose.global.yml up -d
```

**Minimum requirements:**

| Mode | CPU | RAM | Storage | Bandwidth |
|------|-----|-----|---------|-----------|
| Single Community | 2 vCPU | 4 GB | 20 GB SSD | 1 TB/month |
| Global Aggregator | 4 vCPU | 8 GB | 100 GB SSD | 5 TB/month |

---

## Scripts

| Script | Description |
|--------|-------------|
| `scripts/backup.sh` | Creates a compressed PostgreSQL backup with timestamp. Supports optional encryption via [age](https://github.com/FiloSottile/age) (`--encrypt` flag). Automatically cleans up backups older than `BACKUP_RETAIN_DAYS` (default: 7). |
| `scripts/restore.sh` | Restores a PostgreSQL backup from a `.sql.gz` or `.sql.gz.age` file. Stops the API and Web during restore, then restarts them. Supports encrypted backups via `BACKUP_PRIVATE_KEY_FILE`. |
| `scripts/smoke-test.sh` | Validates a running Barazo instance. Checks Docker service health, database connectivity, API endpoints, frontend response, SSL certificate, and HTTPS redirect. Works locally or against a remote URL. |

---

## Environment Variables

All variables are documented in [`.env.example`](.env.example). Key groups:

| Group | Variables | Notes |
|-------|-----------|-------|
| Community Identity | `COMMUNITY_NAME`, `COMMUNITY_DOMAIN`, `COMMUNITY_DID`, `COMMUNITY_MODE` | `COMMUNITY_MODE` is `single` or `global` |
| Database | `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`, `DATABASE_URL` | Change default passwords before production use |
| Cache | `VALKEY_PASSWORD`, `VALKEY_URL` | Password required in production |
| AT Protocol | `TAP_RELAY_URL`, `TAP_ADMIN_PASSWORD`, `RELAY_URL` | Default relay: `bsky.network` |
| OAuth | `OAUTH_CLIENT_ID`, `OAUTH_REDIRECT_URI` | Set to your forum's public URL |
| Frontend | `API_INTERNAL_URL`, `NEXT_PUBLIC_SITE_URL` | `API_INTERNAL_URL` for SSR (default: `http://localhost:3000`); browser uses relative URLs |
| Search | `EMBEDDING_URL`, `AI_EMBEDDING_DIMENSIONS` | Optional semantic search via Ollama or compatible API |
| Encryption | `AI_ENCRYPTION_KEY` | AES-256-GCM key for BYOK API key encryption at rest |
| Cross-Posting | `FEATURE_CROSSPOST_FRONTPAGE` | Frontpage cross-posting toggle |
| Plugins | `PLUGINS_ENABLED`, `PLUGIN_REGISTRY_URL` | Plugin system toggle and registry |
| Monitoring | `GLITCHTIP_DSN`, `LOG_LEVEL` | GlitchTip/Sentry error reporting |
| Backups | `BACKUP_PUBLIC_KEY` | age public key for encrypted backups |

---

## Quick Start

```bash
git clone https://github.com/singi-labs/barazo-deploy.git
cd barazo-deploy

# Configure
cp .env.example .env
nano .env   # Set domain, passwords, community DID, OAuth

# Start all services
docker compose up -d

# Verify
docker compose ps           # All services should show "healthy"
./scripts/smoke-test.sh     # Run smoke tests
```

---

## Documentation

Detailed guides are in the [`docs/`](docs/) directory:

- [Installation](docs/installation.md) -- step-by-step setup
- [Configuration](docs/configuration.md) -- all configuration options
- [Administration](docs/administration.md) -- managing your forum
- [Backups](docs/backups.md) -- backup and restore procedures
- [Upgrading](docs/upgrading.md) -- version upgrade process

---

## Related Repositories

| Repository | Description | License |
|------------|-------------|---------|
| [barazo-api](https://github.com/singi-labs/barazo-api) | AppView backend (Fastify, firehose, REST API) | AGPL-3.0 |
| [barazo-web](https://github.com/singi-labs/barazo-web) | Forum frontend (Next.js, Tailwind) | MIT |
| [barazo-lexicons](https://github.com/singi-labs/barazo-lexicons) | AT Protocol lexicon schemas + generated types | MIT |
| [barazo-website](https://github.com/singi-labs/barazo-website) | Marketing + documentation site | MIT |

---

## Community

- **Website:** [barazo.forum](https://barazo.forum)
- **Discussions:** [GitHub Discussions](https://github.com/orgs/singi-labs/discussions)
- **Issues:** [Report bugs](https://github.com/singi-labs/barazo-deploy/issues)

---

## License

**MIT**

See [LICENSE](LICENSE) for full terms.

---

(c) 2026 Barazo
