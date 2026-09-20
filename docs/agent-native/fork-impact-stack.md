# WP02-WP08 fork impact ledger

| Upstream area | Change and reason | Regression evidence | Upstream candidate |
|---|---|---|---|
| User, bot, sessions and transfer authentication | Native marker and rejection of legacy credentials; preserve ordinary identities | Access tests plus unchanged human tests | Generic bot-key strict parsing may be upstreamable |
| Open-room enrollment | Native integrations require explicit grants | Native grant/no-inheritance tests | Fork-specific |
| Message revisions and SQLite triggers | Observe every committed message/membership write, including bulk writes; no implicit invocation | Transaction rollback and direct rich-text tests | Revision primitive potentially generic |
| Rails schema dumper | Preserve only migration-owned agent triggers while retaining FTS-compatible Ruby dumps | Parallel test DB cloning and trigger tests | Narrow SQLite utility potentially generic |
| Active Storage controller boundary | Native bytes require current room/owner authorization, not reusable signed URLs | Native file routes and security tests | Authorization improvement potentially generic |
| Routes and controller concerns | Separate bearer machine API from session/CSRF human operations | All contract routes plus request tests | Fork-specific |
| Human message attachment presentation | Route native upload links through authenticated download | Human/file regressions and workspace tests | Fork-specific |
| Startup and deployment preflight | Explicit experimental enablement, epoch review before services, restore-incomplete guard | Portable supervisor/preflight and image smoke | Generic startup pieces potentially upstreamable |
| Existing job/push machinery | Durable native intents and permission recheck, generic content-free payloads | Notification tests and pending device gate | Generic deduplication/revalidation ideas |
| Additive agent models/services/views/client/maintenance | Isolated namespaced implementation, no framework upgrade or external runtime embedding | Native/Ruby/Python/HTTP qualification | Fork-only |

The base Gemfile.lock and Ruby/Rails pins are unchanged. The native schema is additive. SQL triggers are deliberately maintained with migrations and serialized into schema clones; tests must cover any future rebuild of the touched SQLite tables. Not every upstream change will merge without review. Update this ledger when source boundaries change.
