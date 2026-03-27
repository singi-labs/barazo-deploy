# Security Hardening Guide

Security configuration for a production Barazo deployment on a Linux VPS.

The Docker Compose templates ship with secure defaults (non-root containers, two-network segmentation, no unnecessary exposed ports). This guide covers the server-level hardening that complements those defaults.

## SSH Configuration

### Disable Root Login and Password Authentication

Edit `/etc/ssh/sshd_config`:

```
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
MaxAuthTries 3
ClientAliveInterval 300
ClientAliveCountMax 2
```

Restart SSH:

```bash
sudo systemctl restart sshd
```

**Before disabling root login**, verify you can SSH in as your deploy user (`barazo`) with key-based auth.

### Change Default SSH Port (Optional)

Reduces automated scan noise. Not a security measure on its own.

```
Port 2222
```

If you change the SSH port, update your firewall rules accordingly.

## Firewall (UFW)

```bash
# Install
sudo apt install ufw

# Default policy: deny all incoming, allow outgoing
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Allow SSH (use your port if changed)
sudo ufw allow 22/tcp comment 'SSH'

# Allow HTTP and HTTPS (required for Caddy)
sudo ufw allow 80/tcp comment 'HTTP'
sudo ufw allow 443/tcp comment 'HTTPS'
sudo ufw allow 443/udp comment 'HTTP/3 QUIC'

# Enable firewall
sudo ufw enable

# Verify
sudo ufw status verbose
```

**Expected output:** only ports 22, 80, 443 (TCP), and 443 (UDP) open.

### Docker and UFW

Docker manipulates iptables directly, which can bypass UFW rules. To prevent Docker from exposing ports that UFW blocks, create `/etc/docker/daemon.json`:

```json
{
  "iptables": false
}
```

Then restart Docker:

```bash
sudo systemctl restart docker
```

**Note:** With `iptables: false`, you must ensure the host firewall allows traffic to Docker's published ports (80, 443). The UFW rules above handle this. Test after applying to confirm services remain accessible.

## Automatic Security Updates

```bash
sudo apt install unattended-upgrades
sudo dpkg-reconfigure -plow unattended-upgrades
```

This enables automatic installation of security patches. Kernel updates may require a reboot -- consider enabling automatic reboots during a maintenance window:

Edit `/etc/apt/apt.conf.d/50unattended-upgrades`:

```
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "04:00";
```

## Docker Security

### Container Defaults (Already Configured)

The `docker-compose.yml` ships with these security measures:

- **Non-root containers:** All Barazo images run as non-root users
- **No privileged mode:** No containers use `--privileged` or `cap_add`
- **Restart policy:** `unless-stopped` on all services (recovers from crashes, stops on manual `docker compose down`)
- **Health checks:** All services have Docker health checks with appropriate intervals and retries

### Resource Limits

Uncomment the resource limits in `docker-compose.yml` to prevent any single service from consuming all server resources:

```yaml
# Recommended limits for CX32 (4 vCPU, 8 GB RAM)
services:
  postgres:
    mem_limit: 2g
    cpus: 1.5
  valkey:
    mem_limit: 512m
    cpus: 0.5
  tap:
    mem_limit: 512m
    cpus: 0.5
  barazo-api:
    mem_limit: 2g
    cpus: 1.5
  barazo-web:
    mem_limit: 1g
    cpus: 0.5
  caddy:
    mem_limit: 256m
    cpus: 0.25
```

### Read-Only Filesystems (Optional)

For additional isolation, enable read-only root filesystems on containers that don't need write access beyond their volumes:

```yaml
services:
  valkey:
    read_only: true
    tmpfs:
      - /tmp
  caddy:
    read_only: true
    tmpfs:
      - /tmp
```

### Docker Socket Protection

Never mount the Docker socket (`/var/run/docker.sock`) into any container. None of the Barazo services require it.

**Exception: cAdvisor** -- The monitoring stack includes cAdvisor, which requires read-only access to `/var/run` (containing the Docker socket) and `/sys` to collect per-container metrics. This is a deliberate, documented exception:
- cAdvisor is a widely-used, Google-maintained monitoring tool
- The mount is read-only (`:ro`) -- cAdvisor does not write to the socket
- cAdvisor runs with a read-only root filesystem
- No other monitoring container has socket access

### Image Updates

Keep base images updated. Dependabot is configured in the repo for automated image update PRs. On the server:

```bash
# Pull latest pinned versions
docker compose pull

# Prune old images
docker image prune -f
```

## Network Segmentation

The Compose file uses two-network segmentation:

```
Internet -> [80/443] -> Caddy (frontend network)
                          |
                     barazo-web (frontend network)
                          |
                     barazo-api (frontend + backend networks)
                          |
                 PostgreSQL, Valkey, Tap (backend network only)
```

- **PostgreSQL and Valkey are not reachable from the internet** -- they are on the `backend` network only
- **Only Caddy exposes ports** (80, 443) -- no other service is directly accessible
- **barazo-api bridges both networks** -- it receives HTTP requests via Caddy and connects to the database

Do not add `ports:` to any service other than Caddy.

## Caddy Security

### Headers (Already Configured)

Caddy automatically enables:

- **HSTS** (Strict-Transport-Security) -- enforced by default
- **HTTP to HTTPS redirect** -- automatic

### Admin API

The Caddy admin API is disabled in the Caddyfile (`admin off`). This prevents runtime configuration changes via HTTP.

### Internal Endpoints

The `/api/health/ready` endpoint is blocked at the Caddy level (returns 403). This endpoint exposes readiness state and should only be accessed from within the Docker network for orchestration purposes.

## Database Security

### Role Separation

Barazo uses three PostgreSQL roles with least-privilege access:

| Role | Privileges | Used By |
|------|-----------|---------|
| `barazo_migrator` | DDL (CREATE, ALTER, DROP) | Schema changes (reserved for beta) |
| `barazo_app` | DML (SELECT, INSERT, UPDATE, DELETE) | API server |
| `barazo_readonly` | SELECT only | Search, public endpoints, reporting |

The API server connects with the database user configured in `DATABASE_URL`. On startup, it runs pending Drizzle migrations using a dedicated single-connection client, then opens the main connection pool. In a future hardening phase, migration will use a separate `barazo_migrator` role with DDL privileges, while `barazo_app` will be restricted to DML only.

### Connection Security

PostgreSQL is on the backend network only. It is not exposed to the host or the internet. The `DATABASE_URL` uses Docker's internal DNS (`postgres:5432`).

Do not add `ports:` to the PostgreSQL service in `docker-compose.yml`.

### Password Strength

Generate all database passwords with:

```bash
openssl rand -base64 24
```

This produces a 32-character password with high entropy.

## Valkey (Redis) Security

### Authentication

Valkey requires a password (`--requirepass`). The password is set via `VALKEY_PASSWORD` in `.env`.

### Dangerous Commands Disabled

The following commands are renamed to empty strings (effectively disabled):

- `FLUSHALL` -- prevents accidental cache wipe
- `FLUSHDB` -- prevents accidental database wipe
- `CONFIG` -- prevents runtime configuration changes
- `DEBUG` -- prevents debug information leaks
- `KEYS` -- prevents expensive keyspace scans in production

### Network Isolation

Like PostgreSQL, Valkey is on the backend network only and not exposed to the host.

## Secrets Management

### Environment Variables

- All secrets are in `.env` (never in `docker-compose.yml` or committed to git)
- `.env` is in `.gitignore`
- `.env.example` uses `CHANGE_ME` placeholders

### File Permissions

```bash
# Restrict .env to owner only
chmod 600 .env

# Restrict backup encryption key
chmod 600 barazo-backup-key.txt
```

### Backup Encryption

Backups must be encrypted before off-server storage. See [Backup & Restore](backups.md) for setup with `age`.

## Checklist

Use this as a post-deployment verification:

- [ ] SSH: root login disabled, password auth disabled
- [ ] Firewall: only 22, 80, 443 (TCP), 443 (UDP), and 51820 (UDP, WireGuard) open
- [ ] Unattended upgrades enabled
- [ ] Resource limits set in `docker-compose.yml`
- [ ] No `CHANGE_ME` in `.env`: `grep CHANGE_ME .env` returns nothing
- [ ] `.env` file permissions: `ls -la .env` shows `-rw-------`
- [ ] PostgreSQL not exposed: `curl localhost:5432` connection refused
- [ ] Valkey not exposed: `curl localhost:6379` connection refused
- [ ] `/api/health/ready` returns 403 externally
- [ ] Caddy admin API disabled: confirmed `admin off` in Caddyfile
- [ ] Backup encryption configured and tested
- [ ] Docker images pinned to specific versions (not `:latest`)
