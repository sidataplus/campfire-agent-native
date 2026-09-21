#!/usr/bin/env python3
"""Verify the frozen source/deployment envelope without booting Rails."""
import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
manifest = json.loads((ROOT / "docs/agent-native/baseline.json").read_text())
lock = (ROOT / "Gemfile.lock").read_bytes()
blob = hashlib.sha1(b"blob " + str(len(lock)).encode() + b"\0" + lock).hexdigest()
assert blob == manifest["gemfile_lock_git_blob_sha"], "Gemfile.lock changed; WP01 must not silently update dependencies"
assert (ROOT / ".ruby-version").read_text().strip() == manifest["ruby_version"]
text = lock.decode()
for remote, revision in manifest["git_dependencies"].items():
    assert f"  remote: {remote}\n  revision: {revision}\n" in text, f"Git dependency drift: {remote}"
assert f'rails ({manifest["rails_version"]})' in text
assert f'thruster ({manifest["thruster_version"]}-' in text
railway = json.loads((ROOT / "railway.json").read_text())
assert railway["deploy"]["numReplicas"] == 1
assert railway["deploy"]["healthcheckPath"] == "/readyz"
assert not railway["deploy"].get("preDeployCommand"), "Mounted SQLite migrations cannot run in pre-deploy"
assert "db:prepare" not in (ROOT / "bin/start-app").read_text()
assert 'prepare: [ "bin/rails", "db:prepare" ]' in (ROOT / "bin/boot").read_text()
dockerfile = (ROOT / "Dockerfile").read_text()
assert f'ARG RUBY_VERSION={manifest["ruby_version"]}' in dockerfile
assert 'ENTRYPOINT ["bin/container-entrypoint"]' in dockerfile
assert 'CAMPFIRE_AGENT_ENABLED=false' in dockerfile and 'CAMPFIRE_AGENT_DISPATCH_ENABLED=false' in dockerfile
assert 'mountpoint -q /rails/storage' in (ROOT / "bin/container-entrypoint").read_text()
assert 'setpriv --reuid=1000 --regid=1000 --init-groups --no-new-privs' in (ROOT / "bin/container-entrypoint").read_text()
controller = (ROOT / "app/controllers/first_runs_controller.rb").read_text()
assert controller.index("rate_limit to:") < controller.index("before_action :verify_bootstrap_secret"), "Throttle invalid setup attempts too"
assert 'request.request_parameters["bootstrap_secret"]' in controller
assert 'resource :first_run' in (ROOT / "config/routes.rb").read_text()
assert 'bind 127.0.0.1' in (ROOT / "config/redis.conf").read_text()
assert (ROOT / "MIT-LICENSE").is_file()
assert (ROOT / ".github/workflows/ci.yml").is_file(), "Keep upstream regression/security CI"
print("WP01 source and deployment envelope checks passed; not runtime qualification.")
