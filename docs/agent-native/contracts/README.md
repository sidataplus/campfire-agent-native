# Frozen V1 design contract

Contract version **0.1.0**, wire namespace **1**. These describe planned APIs, not endpoints implemented by WP01.

The source is the user-approved `agent-campfire-implementation-plan-v0.1.0.zip`. `freeze.json` records its archive SHA-256, original file hashes and canonical semantic hashes. JSON whitespace is normalized. The OpenAPI document is stored as a readable operation catalog plus one shared JSON Schema definition set to avoid duplicating all 64 schemas.

Run `python script/ci/validate-contracts.py` from the repository root after installing `requirements.txt`. It writes the assembled OpenAPI 3.1.1 document to `tmp/wp01/openapi.json`, which is valid JSON/YAML input for OpenAPI tooling. The assembled document must have exactly the source OpenAPI's canonical semantic hash. The catalog does not change API semantics.

The validator ports the approved pack's contract checks: local references, JSON Schema validity, exact OpenAPI/schema parity, positive/negative examples, unique operation IDs, path parameters, authentication separation, durable-write idempotency, the 49-operation inventory and closed terminal states. It is not a full OpenAPI specification validator and does not replace SDK-independent server conformance in later packages.

All fixture records are synthetic. No credential or patient data is included.

## Change control

Changes to the canonical hashes require an explicit contract revision and review of compatibility, affected fixtures and clients. Do not silently update hashes just to make CI green. The original acceptance catalog and implementation plan remain design evidence; WP01 does not mark their native-runtime scenarios as passed.

Campfire owns collaboration state and authenticated human intent. External runtimes own admission, execution, domain authorization and effect receipts. The server must never treat a replayed conversation, edited message or agent mention as a new human instruction. At-least-once event ingestion and idempotent effect admission remain separate. These semantics are requirements for WP02-WP08, not capabilities delivered by this contract snapshot.
