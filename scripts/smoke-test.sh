#!/usr/bin/env bash
# Barazo Smoke Test
#
# Validates that a running Barazo instance is healthy.
# Run after deployment or upgrade to verify all services are working.
#
# Usage:
#   ./scripts/smoke-test.sh                              # Test local (docker compose ps)
#   ./scripts/smoke-test.sh https://forum.example.com    # Test remote URL
#
# Exit codes:
#   0  All checks passed
#   1  One or more checks failed

set -euo pipefail

COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.yml}"
REMOTE_URL="${1:-}"
PASSED=0
FAILED=0

pass() {
  echo "  PASS: $1"
  PASSED=$((PASSED + 1))
}

fail() {
  echo "  FAIL: $1"
  FAILED=$((FAILED + 1))
}

echo "Barazo Smoke Test"
echo "================="
echo ""

# --- Docker Compose checks (local only) ---
if [ -z "$REMOTE_URL" ]; then
  echo "Local deployment checks:"

  # Check all services are running
  SERVICES=$(docker compose -f "$COMPOSE_FILE" ps --format json 2>/dev/null || echo "")
  if [ -z "$SERVICES" ]; then
    fail "Docker Compose services not running"
  else
    for SERVICE in postgres valkey barazo-api barazo-web caddy; do
      STATUS=$(docker compose -f "$COMPOSE_FILE" ps --format json "$SERVICE" 2>/dev/null | grep -o '"Health":"[^"]*"' | head -1 || echo "")
      if echo "$STATUS" | grep -q "healthy"; then
        pass "$SERVICE is healthy"
      elif docker compose -f "$COMPOSE_FILE" ps --format json "$SERVICE" 2>/dev/null | grep -q "running"; then
        pass "$SERVICE is running (no healthcheck)"
      else
        fail "$SERVICE is not running or unhealthy"
      fi
    done
  fi

  echo ""

  # Check PostgreSQL connection
  echo "Database checks:"
  if docker compose -f "$COMPOSE_FILE" exec -T postgres pg_isready -U "${POSTGRES_USER:-barazo}" &>/dev/null; then
    pass "PostgreSQL is accepting connections"
  else
    fail "PostgreSQL is not accepting connections"
  fi

  # Check Valkey connection
  if docker compose -f "$COMPOSE_FILE" exec -T valkey valkey-cli -a "${VALKEY_PASSWORD:-}" ping 2>/dev/null | grep -q "PONG"; then
    pass "Valkey is responding"
  else
    fail "Valkey is not responding"
  fi

  echo ""
fi

# --- HTTP checks ---
if [ -n "$REMOTE_URL" ]; then
  BASE_URL="$REMOTE_URL"
  echo "Remote deployment checks ($BASE_URL):"
else
  # App ports are not published to the host -- only Caddy (port 80) is.
  # Route local HTTP checks through Caddy, which proxies /api/* -> barazo-api
  # and everything else -> barazo-web.
  BASE_URL="http://localhost"
  echo "HTTP checks (via Caddy on localhost):"
fi

# API health
echo ""
echo "API checks:"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/api/health" 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "200" ]; then
  pass "API health endpoint returns 200"
else
  fail "API health endpoint returned $HTTP_CODE (expected 200)"
fi

# API health/ready should be blocked externally (403 from Caddy) or 200 internally
if [ -n "$REMOTE_URL" ]; then
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/api/health/ready" 2>/dev/null || echo "000")
  if [ "$HTTP_CODE" = "403" ]; then
    pass "/api/health/ready blocked externally (403)"
  else
    fail "/api/health/ready returned $HTTP_CODE (expected 403)"
  fi
fi

# Frontend
echo ""
echo "Frontend checks:"
if [ -n "$REMOTE_URL" ]; then
  HOMEPAGE=$(curl -s "$BASE_URL" 2>/dev/null || echo "")
else
  HOMEPAGE=$(curl -s "$BASE_URL" 2>/dev/null || echo "")
fi

if echo "$HOMEPAGE" | grep -qi "barazo\|html"; then
  pass "Frontend returns HTML content"
else
  fail "Frontend did not return expected HTML"
fi

# SSL check (remote only)
if [ -n "$REMOTE_URL" ] && [[ "$REMOTE_URL" == https://* ]]; then
  echo ""
  echo "SSL checks:"
  DOMAIN=$(echo "$REMOTE_URL" | sed 's|https://||' | sed 's|/.*||')
  SSL_EXPIRY=$(echo | openssl s_client -servername "$DOMAIN" -connect "$DOMAIN:443" 2>/dev/null | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2 || echo "")
  if [ -n "$SSL_EXPIRY" ]; then
    pass "SSL certificate valid (expires: $SSL_EXPIRY)"
  else
    fail "Could not verify SSL certificate"
  fi

  # HTTPS redirect
  HTTP_REDIRECT=$(curl -s -o /dev/null -w "%{redirect_url}" "http://$DOMAIN" 2>/dev/null || echo "")
  if [[ "$HTTP_REDIRECT" == https://* ]]; then
    pass "HTTP redirects to HTTPS"
  else
    fail "HTTP does not redirect to HTTPS"
  fi
fi

# --- Summary ---
echo ""
echo "================="
TOTAL=$((PASSED + FAILED))
echo "Results: $PASSED/$TOTAL passed"

if [ "$FAILED" -gt 0 ]; then
  echo ""
  echo "$FAILED check(s) failed. Review the output above."
  exit 1
fi

echo "All checks passed."
