# WP01 deployment, upgrade and rollback

Status: qualification candidate. Do not infer production readiness from the presence of a Railway file or passing static tests.

## Secrets and prerequisites

Prepare a private `.env` (already ignored by the upstream repository) from `.env.example`. Set file mode 0600. Never commit the populated file, paste it into chat, place setup secrets in query strings, or regenerate values on every build.

Generate independent `SECRET_KEY_BASE` (at least 64 bytes), `CAMPFIRE_RECOVERY_EPOCH` (32-128 URL-safe characters) and `CAMPFIRE_BOOTSTRAP_SECRET` (32-4096 bytes) using a cryptographically secure generator. For example, Ruby `SecureRandom.hex(64)` is suitable for the Rails key and `SecureRandom.hex(32)` for the other two. Use the existing upstream VAPID generation helper, or a P-256 generator producing the uncompressed public point and 32-byte private scalar in URL-safe Base64. Preflight checks that the pair matches mathematically.

Set the exact HTTPS origin as `CAMPFIRE_PUBLIC_URL`, without a path, credentials, query or fragment. The approved ingress must terminate TLS, overwrite forwarded headers, restrict access to the HTTP backend and preserve WebSocket upgrades. `assume_ssl` is an explicit trust in that ingress, not TLS on the internal listener.

Do not configure `DISABLE_SSL`, `TLS_DOMAIN`, `THRUSTER_TLS_DOMAIN`, `DATABASE_URL`, or a runtime `SECRET_KEY_BASE_DUMMY`. Keep `SKIP_TELEMETRY=true`. Native feature flags remain false and cannot be enabled in this release.

## Railway profile

Use `railway.json`, one non-sleeping service and one volume mounted at `/rails/storage`. Set `CAMPFIRE_PROXY_MODE=railway` and the variables above. Do not override the image entrypoint or start command. There is no pre-deploy command: Railway does not mount this volume during build/pre-deploy. Migrations run in the actual service startup before workers.

The container begins briefly as root only to initialize ownership of the mounted runtime directory. It does not recursively change ownership of the image or follow storage symlinks. It then uses `setpriv` to run preflight, migrations and every service as UID/GID 1000. The entrypoint rejects a missing mount; an accidentally ephemeral database must not appear healthy.

Railway's assigned `PORT` becomes the Thrust HTTP listener. Before Thrust starts, the supervisor preserves it as `CAMPFIRE_LISTEN_PORT`. `THRUSTER_TARGET_PORT` selects the separate loopback Puma listener, default 3001. Thrust then replaces its child's `PORT` with the target port. Both listeners must be unprivileged and differ from each other and Redis port 6379.

The public hostname is explicitly allowed. `healthcheck.railway.app`, localhost and 127.0.0.1 are exceptions only on `/up`, `/healthz` and `/readyz`. An allowed health hostname does not confer access to chat or setup.

Create the first administrator over HTTPS using the private setup secret. Remove `CAMPFIRE_BOOTSTRAP_SECRET` after success. No bootstrap credential is needed on subsequent starts with an existing administrator. An incomplete old account without an administrator fails startup and needs private repair or a known-good restore; the server will not reopen setup publicly.

Check `/readyz`, the login/setup flow, secure cookies, file upload/download, Action Cable, notification subscription and an actual notification on the target mobile/browser. A container smoke test cannot substitute for the Railway ingress and device checks.

## Generic Docker profile

`docker compose up --build -d` uses the private `.env`, a named volume and a loopback-only host port. Place a trusted TLS-terminating reverse proxy in front of `127.0.0.1:8080`. The proxy is operator infrastructure, not a second mandatory application service. Do not expose port 8080 directly to the Internet or publish Puma/Redis ports. Configure `CAMPFIRE_PROXY_MODE=external` and the exact public HTTPS origin.

The default worker counts are one web worker and one job worker; permitted overrides are 1-8. Measure before increasing them. This is a single-machine SQLite topology, not a horizontally scalable deployment.

## Health and diagnosis

`/up` is preserved. `/healthz` reports process liveness. `/readyz` checks an accessible database, the expected account table, no pending migrations, writable storage and Redis ping. Responses contain only generic status and use `Cache-Control: no-store`. Readiness is not a promise that every background job, push provider or native integration is healthy.

An unexpected child exit ends the service with failure so the platform can restart it. INT/TERM initiate bounded group termination. Failed preparation prevents serving. Logs identify failed stages without printing environment values. Thrust request logging is disabled because upstream bot-key URLs are secret-bearing; Rails retains its existing scrubbing plus bootstrap parameter filtering.

## Persistent secret guard

`storage/.campfire-secret-fingerprints.json` stores SHA-256 fingerprints, not raw keys, for `SECRET_KEY_BASE` and the VAPID pair. Ordinary restart checks these under a file lock. Unplanned regeneration fails closed; it must not silently invalidate sessions or notification subscriptions. Keep backups of the actual keys outside the volume.

For deliberate rotation, stop every instance, back up the complete volume and old secrets, plan user/session/push-subscription invalidation, and remove only the fingerprint file through a private operator session after updating the intended keys. Restart once and verify the new pins and affected workflows. Removing this guard merely to bypass an unexplained mismatch is not a recovery procedure.

The recovery epoch is deployment-held and deliberately not pinned in that file. WP01 validates its presence/shape but **does not implement native replay recovery or epoch reconciliation**, which are later packages. Never describe this preliminary setting as proof of rollback detection.

## Backup and rollback

Before upgrade, use the existing application-aware backup preparation and retain an off-volume copy of the complete state, including SQLite and `storage/files`, plus separate secrets. Do not copy a live SQLite main file alone. Platform volume snapshots supplement, not replace, an application-aware restore rehearsal.

No database schema migration is added in WP01. Record old/new immutable image digests, baseline commit and environment contract before upgrade. A failed migration must stop startup. A volume-mounted replacement can cause interruption; do not promise zero downtime.

A rollback to an earlier fork image must retain compatible secrets and the mounted state. A rollback to unmodified upstream is not equivalent: it removes the setup gate, changes listener/entrypoint behavior and bypasses these native safety checks. Keep ingress private until the rollback profile has been verified. Restore a database/files snapshot only when required; do not roll back healthy data merely to roll back an image.

Before any later native-enabled release, complete the independent runtime-journal/epoch reconciliation design and restore/no-replay drill. WP01 never grants authority to replay historical instructions.

## Qualification evidence

Retain the CI source SHA, Gemfile.lock identity, Ruby/framework versions, build logs, actual image and base-image digests, dependency/security reports, smoke report, manual browser/device checks and rollback drill. Docker base tags and apt feeds are mutable; this change does not claim bit-for-bit reproducibility, signed images, an SBOM or successful clinical-data qualification.

Sources reviewed: upstream Campfire at `ed0f9a5dba396a2f70e62328c9079929d5df9b46`; Thruster README at `v0.1.23`; Railway volume, pre-deploy and healthcheck documentation on 2026-09-20. Recheck platform behavior at deployment.
