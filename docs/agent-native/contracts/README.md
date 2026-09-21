# Frozen V1 design contract

Contract version **0.1.0**, wire namespace **1**. WP01 froze this specification; WP02–WP08 add the corresponding implementation and selected server/client qualification. The operation inventory is not, by itself, proof of complete endpoint conformance or production readiness.

The source is the user-approved `agent-campfire-implementation-plan-v0.1.0.zip`. `freeze.json` records its archive SHA-256, original file hashes and canonical semantic hashes. JSON whitespace is normalized. The OpenAPI document is stored as a readable operation catalog plus one shared JSON Schema definition set to avoid duplicating all 64 schemas.

Run `python script/ci/validate-contracts.py` from the repository root after installing `requirements.txt`. It writes the assembled OpenAPI 3.1.1 document to `tmp/wp01/openapi.json`, which is JSON/YAML input for OpenAPI tooling. The assembled document must have exactly the source OpenAPI's canonical semantic hash. The catalog does not change API semantics.

The validator checks local references, JSON Schema validity, exact OpenAPI/schema parity, positive/negative examples, unique operation IDs, path parameters, authentication separation, durable-write idempotency, the 49-operation inventory and closed terminal states. It is not a full OpenAPI specification validator and does not execute a server endpoint. The stack's Rails tests, Python fixture parity, and independent HTTP smoke provide separate evidence for selected behavior; see the per-commit CI artifacts.

All fixture records are synthetic. No live credentials or patient data are included.

## Change control

Changes to canonical hashes require an explicit contract revision and review of compatibility, affected fixtures and clients. Do not silently update hashes merely to pass CI. The original acceptance catalog and implementation plan remain design evidence; scenarios require corresponding executed evidence before they are marked passed.

Campfire owns collaboration state and authenticated human intent. External runtimes own admission, execution, domain authorization and effect receipts. A replayed conversation, edited message or agent mention must never become a new human instruction. At-least-once ingestion and idempotent effect admission remain separate. See the [stack](../stack.md), [hardening review](../hardening-review.md) and [remaining release gates](../release-gates.json) for implementation and qualification boundaries.
