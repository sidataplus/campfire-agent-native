# Stack hardening review

This review applies to the WP02–WP08 candidate stack. All native features remain off by default. Code review readiness is not approval for production deployment, execution against infrastructure, or integration migration.

## Corrections included

- Parse canonical five-group UUIDs and reject malformed identifiers before database lookups. Deletion uses a bound `id:` condition rather than the overloaded raw-string `exists?` form.
- Canonicalize JSON request fingerprints so object key ordering does not change idempotency identity. A replay still rechecks current token, manifest and room authority.
- Apply the intersection of stored token scopes and the current approved manifest to room, invocation, run and action lists, events, and attachment metadata.
- Preserve consumer sequence/enrollment and authorization-version boundaries. Do not compare second-precision SQLite trigger timestamps with microsecond room-grant timestamps to determine immediate event visibility.
- Revalidate pending follow-ups against their exact run, source message revision, body, participation and reconciliation state before admission.
- Permit at most one accepted runtime admission for a human-approved action, enforced both in the model and by a partial unique database index. Stable request replay returns the original receipt; a different operation cannot reuse the approval.
- Copy database and upload files in binary mode. Recovery regression covers every byte value across multiple copy chunks, authenticates the snapshot, rejects tampering, and confirms restored sessions/actions/runs are quarantined.
- The startup ordering fixture now waits for both service processes to report startup before it sends TERM. It still asserts preparation precedes bootstrap checks and both services. This removes a test scheduling race without changing the supervisor.

## Evidence boundaries

Use per-commit Actions results linked from each PR. The full-stack workflow preserves all group outcomes, including failures, and runs selected native flows through actual HTTP using synthetic data. Its reference worker executes only local synthetic effects.

The binary snapshot is authenticated, **not encrypted**. Off-volume encryption and operator custody of the original instance key remain deployment responsibilities. Restore requires a new independently held recovery epoch and reconciliation; it does not prove every possible rollback is detectable.

A7s live callback wiring, real Railway ingress/redeployment, desktop/mobile push delivery, an operator recovery drill, representative load/24-hour soak, release image vulnerability disposition, and the real-use pilot remain separate gates. Orca command authority is disabled; Rungbee production frontend selection is deferred. See `release-gates.json` and the integration handoffs.
