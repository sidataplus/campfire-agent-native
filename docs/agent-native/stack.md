# Implementation stack

Review in order; do not merge a child against `main` while its prerequisites are still pending.

| Package | Branch | Base |
|---|---|---|
| WP01 | feat/wp01-baseline-boot-safety | main |
| WP02 | feat/wp02-native-access | WP01 |
| WP03 | feat/wp03-events-invocations | WP02 |
| WP04 | feat/wp04-runs-activity | WP03 |
| WP05 | feat/wp05-decisions-controls | WP04 |
| WP06 | feat/wp06-human-workspace | WP05 |
| WP07 | feat/wp07-clients-integrations | WP06 |
| WP08 | feat/wp08-recovery-qualification | WP07 |

WP02 isolates native credentials from legacy human/bot surfaces. WP03 records explicit invocations and transactional observations. WP04 projects external work without scheduling it. WP05 separates human intent from runtime admission/outcomes. WP06 adds the human workspace and permission-checked notification intents. WP07 provides a durable client/fixture worker and optional runtime bridges. WP08 supplies authenticated application-aware snapshots, quarantined restore, recovery/retention operations and qualification procedures.

The stack is a general-purpose protocol, not an A7s-specific application. Notification-only integrations need not read history or create runs. Short interactions need not become tasks. Agent runtime sessions, scientific state, infrastructure authority and execution journals remain external.

## Review and evidence

`Agent stack qualification` runs all Rails/native/system/security/style/portable/contract/Python/HTTP groups independently and preserves their logs. Failing groups remain failures. The source artifact contains only committed repository files; the evidence artifact must never contain live tokens or database contents. Synthetic private fixture files stay in temporary directories and are removed.

The frozen contract still describes 49 operations and 64 resource schemas. Routing and static fixture parity are necessary but insufficient; live HTTP smoke covers selected end-to-end paths. Real device, Railway, recovery-operator, sustained-load and external-runtime qualifications are separate gates recorded in `release-gates.json`.

As prerequisites merge, retarget the next child to `main` after confirming it includes the merged base. Do not squash a parent and then blindly merge duplicate historical changes in a child: reconcile branch ancestry explicitly. No PR authorizes a production deployment or migration.
