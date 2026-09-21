# Native Python client and reference worker

Python 3.11+; no runtime dependencies outside the standard library. The package exposes a bounded HTTPS client, owner-only token files, no redirect following, explicit write keys, a durable SQLite inbox/outbox and a deterministic fixture worker. No bot command can submit a human approval.

```sh
uv run --project clients/python agent-campfire --url https://chat.example.org --token-file /private/campfire.token doctor
uv run --project clients/python agent-campfire --url https://chat.example.org --token-file /private/campfire.token rooms
uv run --project clients/python agent-campfire --url https://chat.example.org --token-file /private/campfire.token reference-worker --state-dir /private/campfire-reference --ticks 0
PYTHONPATH=clients/python python -m unittest discover -s clients/python/tests -v
```

Token files must be mode 0600/0400 and state directories 0700. Never put a token in an argument or URL. One process owns a journal. `doctor` is read-only; starting `reference-worker` explicitly enrolls a consumer at the current event boundary. Send a new request through the human workspace after enrollment: `status`, `task`, `ask`, or `fail`. Other input receives only a synthetic availability response. The worker has no model, shell, network tools or infrastructure privileges.

Register an integration with notification/interactive/task modes; request the frozen common scopes needed by those operations, including events/invocations/runs/actions/receipts/activity and messages. Declare `reference.continue` in `action_types`, and cancel/follow-up capabilities. Grant a test room and its human operators explicitly. Production remains off by default and requires the later experimental/recovery gate.

Inbound event rows and cursor advance commit together before acknowledgement. Outbound requests persist their original body, precondition and key before transmission. A lost acknowledgement reuses that exact request. Synthetic effects have permanent operation IDs inside the fixture journal; this demonstrates deduplication and does **not** make exactly-once claims about external systems.

An instance/epoch change stops the worker. Preserve its journal and reconcile with the runtime owner; deleting the journal to bypass the error is unsafe. A history-expired or access-changed server response similarly requires state-only resynchronization, not replaying old conversations as instructions.

The CLI currently exposes doctor, rooms and the reference worker. All other frozen operations are available through `Client.request`, `Client.upload`, and the language-neutral OpenAPI contract. The live HTTP CI uses a separate urllib client as well as this SDK to prevent an SDK-only contract assumption. Real A7s/Orca/Rungbee qualification is separate.
