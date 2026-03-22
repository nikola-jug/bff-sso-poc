# Technical Debt

This document captures known issues, shortcuts, and improvements identified during the PoC phase. None of these are blockers for a demo environment, but they should be addressed before any production deployment.

---

## Bugs

### `OAuth2AuthorizationCleanup` — incorrect SQL and missing error handling
**File:** `spring-boot-auth-server/src/main/java/io/tacta/springbootauthserver/config/OAuth2AuthorizationCleanup.java`

The cleanup query never deletes an authorization record when a refresh token exists but hasn't expired yet — even if the access token is long expired. Records accumulate in `oauth2_authorization` indefinitely.

Current condition (broken):
```sql
DELETE ... WHERE
  (refresh_token_expires_at IS NOT NULL AND refresh_token_expires_at < NOW())
  OR (refresh_token_expires_at IS NULL AND access_token_expires_at IS NOT NULL AND access_token_expires_at < NOW())
```

Correct intent:
```sql
DELETE ... WHERE
  access_token_expires_at < NOW()
  OR (refresh_token_expires_at IS NOT NULL AND refresh_token_expires_at < NOW())
```

Additionally, the method has no error handling — a DB failure is silently swallowed — and no logging of how many rows were purged.

---

### Broken unit tests in both Angular apps
**Files:**
- `angular-ui/src/app/app.spec.ts`
- `ionic-mobile/src/app/app.spec.ts`

Both test files assert an `<h1>` element that does not exist in `app.html`. These tests fail on every run and should either be rewritten to test the router outlet or deleted.

---

### `payment.status.toLowerCase()` without null guard
**Files:**
- `angular-ui/src/app/payments/payments.html`
- `ionic-mobile/src/app/payments/payments.html`

If the API returns a payment without a `status` field, this throws at runtime. Change to `payment.status?.toLowerCase() ?? 'unknown'`.

---

## Security

### Hardcoded client secrets in committed YAML files
**Files:**
- `spring-boot-bff/src/main/resources/application-web.yaml`
- `spring-boot-bff/src/main/resources/application-mobile.yaml`

Client secrets appear as default values in `${VAR:default}` expressions and are committed to version history. In production, these must be removed — require the environment variables with no fallback.

### Hardcoded Keycloak client secrets in realm export
**File:** `keycloak-idp/config/bff-realm.json`

The `"secret"` fields for `spring-boot-web-bff` and `spring-boot-mobile-bff` clients are hardcoded. The realm export is used to bootstrap Keycloak and is checked into source control. In production, inject secrets post-deployment via the Keycloak admin API or environment variables.

### Weak seed user credentials in Auth Server migration
**File:** `spring-boot-auth-server/src/main/resources/db/migration/V4__seed_dev_user.sql`

The dev user `user/password` uses `{noop}` (plaintext). This migration must not run in production. Options: conditionally apply it (e.g., via a separate Flyway location activated by a profile), or remove it entirely and provision users through the admin interface.

### Manual `Set-Cookie` header construction
**File:** `spring-boot-bff/src/main/java/io/tacta/springbootbff/controller/SessionExchangeController.java`

The session cookie is built by hand as a string:
```java
response.addHeader("Set-Cookie", "SESSION=" + cookieValue + "; HttpOnly; Secure; SameSite=None; Path=/");
```
This is fragile and bypasses Spring's cookie API. Replace with `ResponseCookie.from("SESSION", cookieValue).httpOnly(true).secure(true).sameSite("None").path("/").build()`.

### No input validation on `ExchangeRequest`
**File:** `spring-boot-bff/src/main/java/io/tacta/springbootbff/controller/SessionExchangeController.java`

The `code` field is passed directly to a SQL query without any length or format check. Add `@NotBlank @Size(max = 36)` to the record and `@Valid` on the parameter.

### CSRF disabled for mobile profile without documentation
**File:** `spring-boot-bff/src/main/java/io/tacta/springbootbff/config/SecurityConfiguration.java`

CSRF protection is disabled entirely for the mobile profile (`http.csrf(AbstractHttpConfigurer::disable)`). The rationale (mobile apps use deep links, not browser form submissions) should be documented inline. If session cookies are ever used with a web-based mobile wrapper in future, this will need re-evaluation.

---

## Code Quality

### Capacitor event listener not cleaned up
**File:** `ionic-mobile/src/app/app.ts`

`CapacitorApp.addListener('appUrlOpen', ...)` is never removed. The returned `PluginListenerHandle` should be stored and `handle.remove()` called in `ngOnDestroy()`.

### Home component subscription not cleaned up
**File:** `ionic-mobile/src/app/home/home.ts`

`authService.loadProfile().subscribe(...)` in `ngOnInit` has no `takeUntilDestroyed` or unsubscribe call.

### Debug `console.log` statements in production code
**File:** `ionic-mobile/src/app/app.ts` (lines 25, 30, 42)

Three log statements left over from OAuth callback debugging. Remove or guard behind `!environment.production`.

### Debug logging enabled in mobile BFF profile
**File:** `spring-boot-bff/src/main/resources/application-mobile.yaml`

```yaml
logging:
  level:
    org.springframework.security: DEBUG
    org.springframework.cloud.gateway: DEBUG
```
Remove before any non-local deployment.

### `JSON.stringify(err)` on `HttpErrorResponse`
**File:** `ionic-mobile/src/app/auth/auth.service.ts`

`HttpErrorResponse` has circular references; `JSON.stringify` produces `{}`. Use `err.message` or `err.status` instead.

### `double` for monetary amounts
**File:** `spring-boot-resource-server/src/main/java/io/tacta/springbootresourceserver/domain/Payment.java`

`double amount` is subject to floating-point precision loss. Use `BigDecimal`.

### Hardcoded payment data in controller
**File:** `spring-boot-resource-server/src/main/java/io/tacta/springbootresourceserver/controller/PaymentsController.java`

The payments endpoint returns hardcoded in-memory data. A real deployment needs a database-backed repository, and the query must filter by the authenticated user's subject claim.

---

## Testing

All four Spring Boot modules have only a single `contextLoads()` smoke test. Both Angular apps have the broken spec noted above. The most impactful gaps to fill for production:

| Area | What to test |
|---|---|
| `SessionExchangeController` | Expired codes, already-used codes, valid exchange |
| BFF `SecurityConfiguration` | CORS preflight, unauthenticated access returns 401, OAuth2 login redirect |
| Resource Server `SecurityConfiguration` | Auth Server token denied on `/api/payments`, Keycloak token allowed |
| `OAuth2AuthorizationCleanup` | Rows are actually deleted; DB failure is caught and logged |
| Angular `PaymentsComponent` | `status` being null doesn't throw; error state renders |

---

## Performance

### Missing indexes on `oauth2_authorization`
**File:** `spring-boot-auth-server/src/main/resources/db/migration/V2__create_oauth2_schema.sql`

`registered_client_id` is a frequently queried foreign key with no index. Token expiry queries also benefit from a composite index. Add a new Flyway migration:

```sql
CREATE INDEX oauth2_authorization_client_id_idx
    ON oauth2_authorization (registered_client_id);

CREATE INDEX oauth2_authorization_expiry_idx
    ON oauth2_authorization (access_token_expires_at, refresh_token_expires_at);
```

---

## Operational / Infrastructure

### No Docker resource limits
All `docker-compose.yaml` files have no `mem_limit` or CPU caps. Keycloak and Postgres can consume unbounded host memory. Add `deploy.resources.limits` to each service before any shared environment deployment.

### Refresh token TTL is 30 minutes
**File:** `spring-boot-auth-server/src/main/resources/application.yaml`

`refresh-token-time-to-live: 30m` forces re-authentication every 30 minutes. Typical production values are 1–30 days. Increase and pair with refresh token rotation if security policy requires it.

### Keycloak SMTP configured without TLS
**File:** `keycloak-idp/config/bff-realm.json`

`"ssl": "false", "starttls": "false"` works for the local `mailpit` dev server but must not carry forward. Production must enable `starttls` or `ssl` and inject SMTP credentials via environment variables rather than hardcoding them in the realm export.

### POM metadata placeholders
**Files:** `pom.xml` in all Spring Boot modules

`<url/>`, `<licenses><license/></licenses>`, and `<scm>` blocks contain empty placeholders from the Spring Initializr scaffold. Fill in or remove.
