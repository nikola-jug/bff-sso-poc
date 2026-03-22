# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a **Backend-for-Frontend (BFF)** reference architecture with OAuth2/OIDC security. It consists of multiple modules:

- `angular-ui/` — Web client (Angular 21)
- `ionic-mobile/` — Mobile client (Angular 21 + Ionic)
- `spring-boot-bff/` — API Gateway and OAuth2 Client (Spring Boot 4.0.3, Spring Cloud Gateway WebMVC)
- `spring-boot-auth-server/` — OAuth2 Authorization Server (Spring Boot 4.0.3)
- `spring-boot-resource-server/` — Protected resource API (Spring Boot 4.0.3)
- `keycloak-idp/` — Keycloak 26.1 OIDC Identity Provider (Docker)

## Commands

### Angular (angular-ui and ionic-mobile)

```bash
npm start        # Dev server on localhost:4200
npm run build    # Production build
npm run test     # Unit tests (Vitest)
npm run watch    # Build with watch mode
```

### Spring Boot modules (run from each module directory)

```bash
./mvnw spring-boot:run   # Start the application
./mvnw test              # Run tests
./mvnw clean package     # Build JAR
```

### Keycloak / Infrastructure

```bash
# From keycloak-idp/
docker compose -f docker-compose-database.yaml up -d   # Start PostgreSQL
docker compose up -d                                    # Start Keycloak
```

## Architecture

```
Angular Web / Ionic Mobile
        ↓
Spring Boot BFF (confidential OAuth2 client, Spring Cloud Gateway WebMVC, JDBC Session)
      ↙       ↘
Auth Server   Keycloak IDP        →   Resource Server
(in-house     (OIDC provider,         (OAuth2 Resource
 OAuth2 AS,    PostgreSQL-backed)      Server, protected APIs)
 Thymeleaf)
```

**Authentication flow**: Frontends offer two login options, both handled by the BFF (confidential OAuth2 client to both providers):
- **Auth Server login** (`registration: auth-server`) → `https://spring-boot-auth-server:9000`
- **Keycloak login** (`registration: keycloak`) → `https://oidc-identity-provider:8443/realms/bff`

The two providers are **standalone** — the Auth Server does not federate to Keycloak. Keycloak-authenticated users are granted more privileges than Auth Server-authenticated users (`PROVIDER_KEYCLOAK` authority, conveyed by a hardcoded claim in the Keycloak access token). Tokens are exchanged server-side; the frontends only hold a session cookie backed by PostgreSQL via Spring Session JDBC.

**Key technology choices:**
- Spring Cloud Gateway **WebMVC** (not reactive/WebFlux) in the BFF
- Flyway for DB schema management in Auth Server and BFF
- Java 21, Spring Boot 4.0.3, Spring Cloud 2025.1.0
- TypeScript strict mode, Prettier (single quotes, 100-char line width)
- Vitest for Angular unit tests
