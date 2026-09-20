# WP01 qualification and evidence

Status at implementation: **candidate; production qualification incomplete**. A written test or workflow is not a passing result.

## Local evidence

Portable tests were run with Ruby 3.3.8 in the implementation environment. This is not the pinned application Ruby 3.4.10 and does not qualify Rails. The portable suite exercises strict configuration, matching VAPID keys, secret drift, storage symlinks, body-secret helpers and subprocess ordering/failures. Record the final count and output in the PR.

Contract checks run with Python plus the pinned documentation validator dependencies. They check the assembled frozen OpenAPI document, schema/operation parity, references, fixtures and terminal states. They do not execute any server endpoint.

The implementation environment has no Docker and could not retrieve the full Git-pinned Rails dependency set. Upstream/fork Rails suites, actual image builds, security scans and Docker smoke are therefore **not claimed as locally run**.

## Automated qualification

```sh
ruby -Itest -e 'Dir["test/standalone/*_test.rb"].sort.each { |f| require_relative f }'
python3 script/ci/check-wp01.py
python3 -m venv /tmp/wp01-contracts
/tmp/wp01-contracts/bin/pip install -r docs/agent-native/contracts/requirements.txt
/tmp/wp01-contracts/bin/python script/ci/validate-contracts.py
bin/rails db:setup test
bin/rails test:system
bin/brakeman
bin/rubocop
docker build --tag campfire:wp01 .
python3 script/ci/wp01-container-smoke.py campfire:wp01
```

The existing upstream CI remains intact. `WP01 qualification` adds portable/contract checks, a Docker build and synthetic mounted-volume/proxy/setup/restart test, plus tests and a build of the exact unchanged upstream baseline. The source checker refuses a Gemfile.lock drift or changed framework/runtime pins.

The Docker smoke creates and removes only uniquely named disposable test containers/volumes. It never attaches to an existing production volume. It checks missing-volume failure, health-host restrictions, CSRF, setup-secret denial, transactional rollback, one administrator, secure session cookies, WebSocket origin/upgrade, UID 1000, persistence across replacement, bootstrap-secret removal, secret drift and native-flag rejection. It records one idle resource observation, not a benchmark or monthly cost estimate.

Review checks on the actual PR head. If Actions is disabled or awaits approval in the new fork, enable/approve the workflow through the repository's normal administration before merging. An empty check list is not success.

## Remaining manual release gates

- Real Railway ingress: HTTPS/redirects, forwarded headers, WebSockets and persistent redeploy.
- Ordinary human rooms/DMs/search/files and existing bot regression outcomes reviewed against the baseline.
- Actual Web Push subscription and delivery on target desktop and mobile/PWA devices.
- Application-aware backup, off-volume copy, restore and rollback rehearsal.
- Dependency/image vulnerability review, recorded digests and security finding disposition.
- Idle and representative human load observations before assigning operational budgets.

No production deployment, native agent execution, A7s/Orca/Rungbee migration, protocol server conformance or WP02-WP08 acceptance is implied by this PR.
