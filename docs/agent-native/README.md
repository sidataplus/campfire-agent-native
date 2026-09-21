# Agent Campfire: implementation candidate

This fork is a general-purpose collaboration surface for external notification integrations, deterministic bots and task-capable agents. A7s, Orca-ai and Rungbee are reference use cases, not dependencies.

**The WP01–WP08 stack contains the native implementation. Native features remain disabled by default, and the candidate is not production-qualified.** A passing contract validator does not mean every server behavior or live integration has been qualified. Review per-commit CI evidence and the explicit release gates.

## Implementation and review map

| Package | Implementation | Pull request |
|---|---|---|
| WP01 | Pinned baseline, secure boot/proxy/bootstrap and contract freeze | [#1](https://github.com/sidataplus/campfire-agent-native/pull/1) |
| WP02 | Native identities, effective permissions, bounded conversation/file APIs | [#2](https://github.com/sidataplus/campfire-agent-native/pull/2) |
| WP03 | Transactional events, replay and explicit human invocations | [#3](https://github.com/sidataplus/campfire-agent-native/pull/3) |
| WP04 | Owned runs, isolated follow-ups, semantic activity and artifacts | [#4](https://github.com/sidataplus/campfire-agent-native/pull/4) |
| WP05 | Human questions/approvals, controls and runtime receipts | [#5](https://github.com/sidataplus/campfire-agent-native/pull/5) |
| WP06 | Human supervision UI, administration and notification intents | [#6](https://github.com/sidataplus/campfire-agent-native/pull/6) |
| WP07 | Python client/CLI, deterministic worker and runtime bridges | [#7](https://github.com/sidataplus/campfire-agent-native/pull/7) |
| WP08 | Authenticated snapshots, recovery quarantine and qualification | [#8](https://github.com/sidataplus/campfire-agent-native/pull/8) |

Review bottom-up. Each PR targets its predecessor; retarget the next child to main only after its parent is merged and ancestry is reconciled. No PR is an instruction to deploy or migrate a live integration.

Start with [stack boundaries](stack.md), the [hardening review](hardening-review.md), [release gates](release-gates.json), [integration handoffs](../../integrations/README.md), and the [Python client](../../clients/python/README.md). The [baseline manifest](baseline.json), [WP01 operations](wp01-operations.md), [fork-impact ledger](fork-impact.md), [WP01 qualification record](qualification.md), and [frozen contracts](contracts/README.md) retain baseline-specific details.

## Authority and reliability

Campfire owns collaboration state, explicit human requests and authenticated intent. External runtimes own admission, execution, domain authorization, private credentials and canonical execution journals. Notification-only integrations need not read history or create runs; short interactions need not become tasks.

A conversation read, message edit, reaction or agent-authored mention never becomes a new human invocation. Run follow-ups bind to an exact run and source revision. Human approval is not execution; cancellation is a request until the runtime acknowledges its actual outcome. A previously approved action admits at most one operation, and repeat delivery uses stable idempotency identity.

## Deployment boundary

The single-service, single-volume profile preserves the ordered startup boundary:

```text
mounted volume checked / narrowly scoped ownership initialization
    -> privilege drop to UID/GID 1000
    -> environment and persistent-secret preflight
    -> bundled loopback Redis ready
    -> db:prepare on mounted storage
    -> first-administrator and recovery checks
    -> workers + Thrust/Puma
```

Preserve stable instance secrets and use one replica. Initial setup requires an owner-held body-only secret; remove it after administrator creation. Existing human sign-in and private invite-code behavior remain in place. No SSO or clinical-data governance is implied.

Native enablement requires explicit experimental configuration and recovery reconciliation. Installing the fork grants no Orca action authority and does not start A7s or select Rungbee's frontend. A snapshot is authenticated, not encrypted: backup encryption and custody of the original instance key are separate operator responsibilities.

## Remaining qualification

The live A7s owner callback and pilot require its actual source integration. Real Railway ingress/redeployment, target-device push and accessibility, operator off-volume restore/rollback, representative load/24-hour soak, and release-image security review remain tracked explicitly. Orca consequential commands are deferred and disabled; its ClickClack deployment remains unchanged. Rungbee has compatibility fixtures, not a production migration.
