# Configuration Reference

All Barazo environment variables with descriptions, defaults, and examples.

## Community Identity

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `COMMUNITY_NAME` | Yes | `"My Community"` | Display name for your forum |
| `COMMUNITY_DOMAIN` | Yes | -- | Domain name (e.g., `forum.example.com`). Used by Caddy for SSL. |
| `COMMUNITY_DID` | No | -- | AT Protocol DID. Created automatically during first setup. |
| `COMMUNITY_MODE` | No | `single` | `single` for one community, `global` for aggregator mode |
| `HOSTING_MODE` | No | `selfhosted` | `selfhosted`, `saas` |

## Database (PostgreSQL)

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `POSTGRES_USER` | Yes | -- | PostgreSQL superuser name |
| `POSTGRES_PASSWORD` | Yes | -- | PostgreSQL superuser password |
| `POSTGRES_DB` | Yes | -- | Database name |
| `POSTGRES_PORT` | No | `5432` | Host port mapping (dev compose only) |
| `DATABASE_URL` | Yes | -- | Connection string for the API. Format: `postgresql://user:pass@postgres:5432/dbname` |
| `MIGRATION_DATABASE_URL` | No | -- | Connection string for schema changes (DDL role, if using role separation). Reserved for beta -- not used in alpha. |

## Cache (Valkey)

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `VALKEY_PASSWORD` | Prod: Yes | -- | Valkey authentication password. Dangerous commands are disabled. |
| `VALKEY_PORT` | No | `6379` | Host port mapping (dev compose only) |
| `VALKEY_URL` | No | Auto | Connection URL for the API. Auto-constructed in compose. |

## AT Protocol

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `RELAY_URL` | No | `wss://bsky.network` | Bluesky relay URL for firehose |
| `TAP_ADMIN_PASSWORD` | Yes | -- | Tap admin API password |
| `TAP_PORT` | No | `2480` | Host port mapping (dev compose only) |
| `OAUTH_CLIENT_ID` | Yes | -- | Your forum's public URL (e.g., `https://forum.example.com`) |
| `OAUTH_REDIRECT_URI` | Yes | -- | OAuth callback URL (e.g., `https://forum.example.com/api/auth/callback`) |

## Frontend

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `API_INTERNAL_URL` | No | `http://localhost:3000` | Internal API URL for server-side rendering. Set to `http://barazo-api:3000` in Docker. |
| `NEXT_PUBLIC_SITE_URL` | Yes | -- | Public site URL (e.g., `https://forum.example.com`) |

## Image Versions

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `BARAZO_API_VERSION` | No | `latest` | API Docker image tag. Pin to a specific version in production (e.g., `1.2.3`). |
| `BARAZO_WEB_VERSION` | No | `latest` | Web Docker image tag. Pin to a specific version in production. |

## Search

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `EMBEDDING_URL` | No | -- | Enables hybrid semantic search. Example: `http://ollama:11434/api/embeddings` |
| `AI_EMBEDDING_DIMENSIONS` | No | `768` | Vector dimensions (must match your embedding model) |

## Encryption

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `AI_ENCRYPTION_KEY` | Conditional | -- | AES-256-GCM key for encrypting BYOK API keys at rest. Required if BYOK features are used. Generate: `openssl rand -base64 32` |

## Cross-Posting

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `FEATURE_CROSSPOST_FRONTPAGE` | No | `false` | Enable Frontpage cross-posting (Bluesky cross-posting is always available) |

## Plugins

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `PLUGINS_ENABLED` | No | `true` | Set to `false` to disable all plugins |
| `PLUGIN_REGISTRY_URL` | No | `https://registry.npmjs.org` | npm registry URL for plugin installation |

## Monitoring

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `GLITCHTIP_DSN` | No | -- | GlitchTip/Sentry DSN for error reporting |
| `LOG_LEVEL` | No | `info` | Pino log level: `trace`, `debug`, `info`, `warn`, `error`, `fatal` |

## Backups

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `BACKUP_PUBLIC_KEY` | No | -- | age public key for encrypting backups. Generate: `age-keygen -o key.txt` |
| `BACKUP_DIR` | No | `./backups` | Directory for backup files |
| `BACKUP_RETAIN_DAYS` | No | `7` | Days to keep old backups before cleanup |
