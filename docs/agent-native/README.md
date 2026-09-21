# Agent Campfire: WP01

This fork is a general-purpose collaboration surface for external notification integrations, deterministic bots and agents. A7s, Orca-ai and Rungbee are reference use cases, not dependencies.

**WP01 implements baseline and deployment safety only. Native agent APIs, identities, runs and dispatch are not implemented or enabled.** The frozen V1 design is a contract for subsequent work, not a list of working endpoints.

## Review map

- [Baseline manifest](baseline.json): exact upstream, framework and Git dependency pins, intake exception and release gates.
- [Deployment and rollback](wp01-operations.md): Railway and generic TLS-proxy Docker profiles.
- [Fork-impact ledger](fork-impact.md): the upstream paths changed and their regression responsibilities.
- [Frozen contracts](contracts/README.md): 64 schemas, 49 operations, fixtures, state machines and semantic hash guard.
- [Qualification](qualification.md): commands, actual evidence and remaining manual gates.

## Implemented boundary

```text
mounted volume checked / root-owned permissions initialized
    -> privilege drop to UID/GID 1000
    -> environment and persistent-secret preflight
    -> bundled loopback Redis ready
    -> db:prepare on mounted storage
    -> first-administrator configuration check
    -> workers + Thrust/Puma
```

An unexpected web/worker/Redis exit stops the other process groups and returns nonzero. A migration or bootstrap-check failure never starts web/workers. A deployment must use one replica, keep the persistent volume and preserve its instance secrets.

The first administrator is created through the existing setup form plus an owner-supplied body-only secret. The existing account singleton constraint and one database transaction make account/admin/room creation atomic. The secret is never rendered or stored as a URL. After setup, remove the bootstrap secret from deployment configuration. Ordinary upstream sign-in and invite-code behavior remain in place.

Invite codes are bearer invitations, not an unrestricted public signup page. Keep them private and rotate a disclosed code. WP01 does not add SSO, approval-based invitations, native credential administration or clinical-data governance.

## Development

Ordinary local Rails development remains the upstream workflow. The production `bin/boot` and Docker profile intentionally require the new deployment contract. Tests without a configured setup secret preserve upstream developer setup behavior; production always requires the gate.

Do not set either native feature flag to true: production startup rejects it. No Orca action authority or A7s execution capability is granted by installing this fork.
