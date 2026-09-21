# WP08: recovery, operations and pilot qualification

## Release status

This is a reviewed-code candidate, not a production release. Native features remain off in the image and sample configuration. After automated qualification, an operator may explicitly set `CAMPFIRE_AGENT_EXPERIMENTAL=true` and `CAMPFIRE_AGENT_ENABLED=true` on a disposable instance. Dispatch additionally requires `CAMPFIRE_AGENT_DISPATCH_ENABLED=true` and a completed recovery review. Existing human-only operation retains the WP01 envelope.

A fresh native instance deliberately begins in recovery-required state. In a private application console, an active administrator can record `AgentNative::Maintenance.complete_recovery!(human, evidence_reference: "fresh empty-instance review ...")`. This does not set environment flags or grant any integration access. Register integrations, approve room/operator grants and issue least-privilege tokens separately.

## Application-aware backup

Run as the application UID with the original `SECRET_KEY_BASE` and current `CAMPFIRE_RECOVERY_EPOCH` supplied by the private runtime environment:

```sh
bin/agent-maintenance backup \
  --database /rails/storage/db/production.sqlite3 \
  --files /rails/storage/files \
  --fingerprints /rails/storage/.campfire-secret-fingerprints.json \
  --destination /private-backup/unique-snapshot-directory
bin/agent-maintenance verify --source /private-backup/unique-snapshot-directory
```

The destination must not exist. A read-only SQLite connection creates a consistent `VACUUM INTO` snapshot. The tool copies only immutable blob keys referenced in that snapshot, checks their original checksums and sizes, records SHA-256 file hashes, and authenticates the manifest using an instance-key-derived HMAC. No signing key is stored in the backup. A concurrently purged/missing/changing file aborts the backup; retry during a quiet period. A completed directory is renamed into place only after verification. Keep enough free space for the DB snapshot and referenced bytes.

**Authentication is not encryption.** The backup contains private collaboration records. Encrypt it using your approved backup transport/storage and retain an off-volume copy. A snapshot on the same Railway volume is not disaster recovery. Store the original instance secrets in a separate private recovery location. Never upload backups, token files or chat content as CI artifacts.

## Restore into a new volume only

Stop incoming native work at the runtime boundary first. Preserve every external runtime's journal. Use a new empty destination and supply a newly generated `CAMPFIRE_RECOVERY_EPOCH` through the private environment, while retaining the original instance signing and VAPID keys:

```sh
bin/agent-maintenance restore \
  --source /private-backup/unique-snapshot-directory \
  --destination /rails/storage
```

The tool refuses an existing populated target and a reused recovery epoch. It verifies the authenticated manifest, restores only approved paths, removes restored human sessions, revokes agent credentials, disables profiles, invalidates pending actions/invocations, fences nonterminal run owners and marks their execution state for reconciliation. The new stream epoch makes old cursors unusable. Immutable intent/outcome receipts are retained. An interrupted copy leaves a startup-blocking marker; never delete that marker to guess that a restore completed.

Start with dispatch disabled. Review human principals and private session access, re-enable integrations explicitly, rotate credentials, and reconcile each unfinished run against the authoritative external journal:

```ruby
AgentNative::Maintenance.reconcile_run!(human,
  run_id: "the-stable-run-id", state: "completed", source_revision: 42,
  evidence_reference: "external-runtime-journal/verified-operation-42")
AgentNative::Maintenance.complete_recovery!(human,
  evidence_reference: "operator recovery review with all external journals reconciled")
```

These calls are operator attestations, not automated scientific verification. They never start/retry a task. The adapter must keep its permanent operation/effect journal and perform state-only reenrollment; do not erase deduplication state to bypass an epoch error. The application cannot detect an arbitrary rollback of all its independent evidence; the deployment-held epoch and external journals are mandatory controls.

## Maintenance and diagnostics

`AgentNative::Maintenance.diagnostics` returns bounded, content-free counts, event floor, consumer ingestion lag and stale observations. An old observation does not prove a run is dead. `AgentNative::Notification.drain!` requeues retained notification intents after queue recovery; startup invokes it when native collaboration is enabled.

`AgentNative::Maintenance.prune_events!(human)` removes only a contiguous old prefix while preserving the latest 10,000 events and 30 days of fresh events. Old cursors receive a history-expired error; resynchronization never replays old messages as commands. Do not delete receipts or external operation journals as part of event retention. Schedule maintenance only through your existing operator mechanism; this fork adds no second scheduler or broker.

## Upgrade/rollback

Use immutable reviewed image commits/digests. Back up before migrating and rehearse restore on a disposable volume. Upgrade in the normal mounted startup path, not a Railway pre-deploy step without the volume. Never roll an old executable back over a schema it does not support. Prefer forward fixes; otherwise restore the matching snapshot to a new volume with a new recovery epoch and reconcile externally. No merge/release/deployment is performed by these PRs.

## Manual gates that code cannot certify

Real Railway HTTPS/forwarded-header/WebSocket/redeploy checks; target desktop/mobile/PWA Web Push; accessibility and real-user supervision; off-volume encrypted backup and operator restore/rollback; dependency/image vulnerability disposition and release digests; representative load plus a 24-hour synthetic soak; actual A7s callback wiring/live pilot; separate Orca state-changing authority qualification; Rungbee frontend evaluation. These remain not run until evidence is attached. Container and localhost HTTP tests are not substitutes.
