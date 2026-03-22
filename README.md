# Backend-for-Frontend Reference Architecture

OAuth2/OIDC security reference implementation using Spring Boot BFF, Angular, Keycloak, and an in-house Authorization Server.

## Prerequisites

- Docker and Docker Compose
- [mkcert](https://github.com/FiloSottile/mkcert) for locally-trusted TLS certificates
- Java 21 and Maven (for building Spring Boot JARs)

## First-time setup

### 1. Install mkcert and generate certificates

```bash
brew install mkcert
mkcert -install
```

Generate a single certificate covering all service hostnames, placed in the top-level `certs/` directory:

```bash
mkcert -cert-file certs/cert.pem -key-file certs/key.pem \
  spring-boot-web-bff spring-boot-mobile-bff spring-boot-auth-server \
  spring-boot-resource-server oidc-identity-provider angular-ui-web \
  localhost 127.0.0.1 10.0.2.2
```

Also copy the mkcert root CA into `certs/` so Spring Boot Docker images can import it into their JVM trust stores, and so mobile emulators/simulators can trust it:

```bash
cp "$(mkcert -CAROOT)/rootCA.pem" certs/rootCA.pem
```

The `certs/` directory is git-ignored — every developer generates their own.

### 2. Add /etc/hosts entries

The browser and services need to resolve Docker container hostnames. Add the following to `/etc/hosts`:

```
127.0.0.1  spring-boot-web-bff
127.0.0.1  spring-boot-mobile-bff
127.0.0.1  spring-boot-auth-server
127.0.0.1  spring-boot-resource-server
127.0.0.1  oidc-identity-provider
127.0.0.1  angular-ui-web
```

## Starting the stack

From the project root, run:

```bash
./start.sh
```

This builds all Spring Boot JARs, builds Docker images, starts all services, and waits for health checks.

## Stopping and resetting

```bash
./stop.sh    # Stop containers, preserve volumes
./reset.sh   # Stop containers and wipe all volumes (clean slate)
```

## Accessing the application

| Service | URL |
|---|---|
| Angular UI | https://localhost |
| Web BFF (OAuth2 client) | https://spring-boot-web-bff:8080 |
| Mobile BFF (OAuth2 client) | https://spring-boot-mobile-bff:8082 |
| Authorization Server | https://spring-boot-auth-server:9000 |
| Keycloak | https://oidc-identity-provider:8443 |
| Mailpit (SMTP UI) | http://localhost:8025 |
| Resource Server | internal only (BFF proxies to it) |

## Resetting Keycloak

Keycloak imports the realm JSON on first startup. To re-import after changing `bff-realm.json`, wipe the Keycloak database volume:

```bash
./reset.sh
./start.sh
```

Or selectively:

```bash
cd keycloak-idp
docker compose down
docker volume rm keycloak-idp_external-oidc-provider-db-volume 2>/dev/null || true
docker compose up -d --build
```

## Mobile app

See [`ionic-mobile/README.md`](ionic-mobile/README.md) for Android and iOS setup instructions.
