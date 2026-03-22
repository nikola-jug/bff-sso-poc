#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"

echo "==> Building Spring Boot JARs..."

for module in spring-boot-auth-server spring-boot-bff spring-boot-resource-server; do
  echo "    Building $module"
  "$ROOT/$module/mvnw" -f "$ROOT/$module/pom.xml" clean package -DskipTests -q
done

echo "==> Building Docker images..."
docker compose -f "$ROOT/docker-compose.yaml" build

echo "==> Starting all services..."
docker compose -f "$ROOT/docker-compose.yaml" up -d

wait_for_healthy() {
  local timeout=300
  local interval=5
  local elapsed=0
  printf "==> Waiting for services to be healthy"
  while [ $elapsed -lt $timeout ]; do
    local status
    status=$(docker compose -f "$ROOT/docker-compose.yaml" ps --format json 2>/dev/null)
    if echo "$status" | grep -q '"Health":"unhealthy"'; then
      echo ""
      echo "ERROR: One or more services are unhealthy:"
      docker compose -f "$ROOT/docker-compose.yaml" ps
      exit 1
    fi
    if ! echo "$status" | grep -q '"Health":"starting"'; then
      echo " done."
      return 0
    fi
    printf "."
    sleep $interval
    elapsed=$((elapsed + interval))
  done
  echo ""
  echo "ERROR: Timed out after ${timeout}s waiting for services to become healthy."
  docker compose -f "$ROOT/docker-compose.yaml" ps
  exit 1
}

wait_for_healthy

cat <<EOF
==> Done. All services are healthy.

    Angular UI:          https://angular-ui-web
    Auth Server:         https://spring-boot-auth-server:9000
    Keycloak:            https://oidc-identity-provider:8443
    Web BFF:             https://spring-boot-web-bff:8080
    Mobile BFF:          https://spring-boot-mobile-bff:8082
    Mailpit (SMTP UI):   http://localhost:8025

    NOTE: Ensure /etc/hosts maps container hostnames to 127.0.0.1:
    127.0.0.1 spring-boot-auth-server
    127.0.0.1 spring-boot-web-bff
    127.0.0.1 spring-boot-mobile-bff
    127.0.0.1 spring-boot-resource-server
    127.0.0.1 oidc-identity-provider
    127.0.0.1 angular-ui-web
EOF