# Administration Guide

Day-to-day administration of a running Barazo instance.

## Monitoring

### Service Status

```bash
# Check all services
docker compose ps

# Check specific service
docker compose ps barazo-api
```

All services should show `healthy` status.

### Logs

```bash
# All services
docker compose logs -f

# Specific service (last 100 lines, follow)
docker compose logs -f --tail 100 barazo-api

# Specific service without follow
docker compose logs --tail 50 postgres
```

### Smoke Test

Run the smoke test to verify everything is working:

```bash
./scripts/smoke-test.sh https://your-domain.com
```

### Resource Usage

```bash
docker stats --no-stream
```

### Grafana Dashboard

The monitoring stack (Prometheus + Grafana) provides real-time dashboards and alerting for all Singi Labs VPSes. Access it at `https://monitoring.singi.dev`.

Available dashboards:
- **Singi Labs -- VPS Overview**: All VPSes at a glance (CPU, RAM, disk, network, container metrics)
- **Node Exporter Full**: Deep per-VPS host metrics
- **Docker Container & Host**: Per-container resource usage

The monitoring stack runs from a separate repo: [singi-labs/monitoring](https://github.com/singi-labs/monitoring). See its README for setup, maintenance, and adding new VPSes.

### Prometheus Targets

Check that all scrape targets are healthy:

```bash
# From the VPS
curl -s http://localhost:9090/api/v1/targets | python3 -m json.tool | grep -E '"health"|"job"'

# Reload config after editing prometheus.yml
curl -X POST http://localhost:9090/-/reload
```

## Backups

### Automated Backups (Recommended)

Set up a daily backup via cron:

```bash
crontab -e
```

Add this line (runs daily at 2 AM):

```
0 2 * * * cd /path/to/barazo-deploy && ./scripts/backup.sh --encrypt >> /var/log/barazo-backup.log 2>&1
```

Requires `BACKUP_PUBLIC_KEY` in your `.env` file.

### Manual Backup

```bash
./scripts/backup.sh              # Unencrypted (local storage only)
./scripts/backup.sh --encrypt    # Encrypted (safe for off-server storage)
```

Backups are saved to `./backups/` with timestamps. Old backups are automatically cleaned up after 7 days (configurable via `BACKUP_RETAIN_DAYS`).

### Restore

```bash
./scripts/restore.sh backups/barazo-backup-20260214-020000.sql.gz
```

See [Backup & Restore](backups.md) for full documentation.

## Common Tasks

### Restart a Service

```bash
docker compose restart barazo-api
```

### Stop Everything

```bash
docker compose down      # Stops containers (preserves data)
docker compose down -v   # Stops containers AND deletes all data
```

### Connect to Database

```bash
docker compose exec postgres psql -U barazo
```

### View Caddy Access Logs

```bash
docker compose logs caddy
```

### Force SSL Certificate Renewal

Caddy renews certificates automatically. If you need to force renewal:

```bash
docker compose restart caddy
```

### Update Images Without Restart

```bash
docker compose pull        # Pull new images
docker compose up -d       # Restart only changed services
```

## Troubleshooting

### Service Won't Start

```bash
# Check the logs
docker compose logs <service-name>

# Check if port is already in use
sudo lsof -i :80
sudo lsof -i :443
```

### Out of Disk Space

```bash
# Check disk usage
df -h

# Clean up Docker resources
docker system prune -f          # Remove stopped containers, unused images
docker volume prune -f          # Remove unused volumes (careful!)
```

### High Memory Usage

Check which service is consuming memory:

```bash
docker stats --no-stream
```

Consider enabling resource limits in `docker-compose.yml` (uncomment the `mem_limit` lines).

### Database Is Slow

Connect to PostgreSQL and check for long-running queries:

```bash
docker compose exec postgres psql -U barazo -c "SELECT pid, now() - query_start AS duration, query FROM pg_stat_activity WHERE state = 'active' ORDER BY duration DESC LIMIT 5;"
```
