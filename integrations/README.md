# External runtime integration boundary

These are optional adapter entry points, not embedded orchestration or production migrations. The HTTP/JSON contract is authoritative; Python is convenience only. ACP and OpenClaw bridges are deferred.

## A7s

`agent_campfire_client.bridges.ProjectionBridge` accepts `RunObservation` from the existing owner process. The owner supplies stable external run IDs and monotonic revisions; the bridge reports them without creating scientific work. Native human invocations, action evidence and receipts use the same client/journal primitives as the deterministic worker. Specialist contributions use explicitly granted participant identities. P8s remains a tool unless an agent wrapper is deliberately registered.

A7s/Aristaeus source searches through the connected installation returned no accessible repository during this implementation. Consequently this package does **not** claim to import or wire an unseen A7s host API. Its integration code is executable against the common contract and fixtures; wiring the actual owner callbacks and full live A7s pilot remain explicit qualification work. Do not substitute a second shared orchestration service.

## Orca-ai

`OrcaReadOnlyBridge.report(ServiceObservation(...))` accepts an intentionally narrow, operator-approved public status summary. It posts service/state/observation time only, not raw Slurm rows, hostnames, user identities, notes or controller credentials. Unknown state is never interpreted as free capacity. It cannot submit, cancel, reconcile or approve infrastructure actions and never opens the controller's SQLite journal or SSH socket.

The inspected `sidataplus/orca-ai-v2/README.md` describes the owner-process and signed Buzz/MFA boundary. This bridge is **not** a replacement for that proof or the existing ClickClack frontend. The owner must explicitly produce `ServiceObservation`; it is not falsely advertised as Orca's current CLI output schema. Consequential commands and cross-frontend authority remain disabled and require a separate source-audited change in Orca's repository.

## Rungbee and future runtimes

`conversation_binding(instance, room, profile, run=None)` creates deterministic isolated conversation/session references. A persistent conversation can span many separate runs. The reference worker supplies executable short-request, run, question and cancellation fixtures. It neither migrates Rungbee nor selects its final frontend.

Canonical artifacts, execution journals, domain authorization and private credentials remain with each runtime. A receipt proves who asserted an outcome, not independent truth of that outcome.
