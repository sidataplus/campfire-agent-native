# WP01 fork-impact ledger

Baseline: `ed0f9a5dba396a2f70e62328c9079929d5df9b46`. Preserve upstream identity/authentication, chats, search, storage semantics, notifications, existing bot API and migrations except the explicit changes below.

| Upstream surface | WP01 change | Required regression / intake trigger |
|---|---|---|
| `Dockerfile` | Mounted-volume entrypoint, bounded defaults, proxy ports, util-linux; unchanged gem lock | Secret-free build, root-volume startup and all service UIDs |
| `bin/boot` | Preflight plus ordered process supervisor | Redis/migration failure, stop, unexpected child exit, process groups |
| `bin/start-app` | Exec server only; preparation moves to supervisor | Workers never precede database preparation |
| `config/puma.rb` | Loopback bind in explicit proxy profile | Thrust target and Action Cable upgrade |
| `config/redis.conf` | Loopback and protected mode | No exposed Redis; app/cache/job connectivity |
| `app/controllers/first_runs_controller.rb` | Body-only owner gate, rate limit before verification, no-store/error handling | Secret omission/type/query rejection, CSRF, throttling, repeat setup |
| `app/models/first_run.rb` | Account/admin/room in one transaction | Singleton race and validation rollback |
| `app/views/first_runs/show.html.erb` | Add setup-secret partial only | Accessible first-run form; secret never prefilled |
| `config/routes.rb` | Add two health routes; retain `/up` | Human routes unchanged; auth-free generic health |

Additive implementation: `lib/campfire/{deployment,bootstrap,process_supervisor,readiness}.rb`, deployment initializer, health controller, setup partial, tests, CI scripts, `.env.example`, Railway/Compose profiles and these documents.

The initializer deliberately overrides production proxy/security configuration before middleware construction. Upstream changes to initializer ordering, SSL middleware, HostAuthorization, session cookies, Action Cable or Thrust configuration require renewed image/proxy tests.

The existing database singleton index and SQLite immediate transaction mode are relied upon, not replaced. Changes to FirstRun, account uniqueness, User validation, room membership callbacks or transaction handling require setup/rollback/race tests.

No agent marker, bearer endpoint, grant model, event log, invocation, run, approval or execution permission is added. WP02 must separately qualify legacy-bot bypasses, ambient open-room grants and file authorization; WP01 is not a claim that those later boundaries are solved.

No Buzz implementation is copied. The upstream MIT license remains unchanged. The baseline/pinned Rails alpha is not upgraded. Upstream CI remains present; an additive qualification workflow compares the exact unchanged baseline with the fork and tests the container profile.
