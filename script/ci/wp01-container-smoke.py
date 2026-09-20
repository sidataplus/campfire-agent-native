#!/usr/bin/env python3
"""Exercise the built image with synthetic data and disposable Docker volumes only."""
from __future__ import annotations

import base64
import html.parser
import http.client
import http.cookies
import json
import os
from pathlib import Path
import secrets
import subprocess
import sys
import tempfile
import time
import urllib.parse

IMAGE = sys.argv[1] if len(sys.argv) > 1 else "campfire:wp01"
NAME = "campfire-wp01-" + secrets.token_hex(6)
VOLUME = NAME + "-storage"
ORIGIN = "https://campfire.example.test"
REPORT = Path("tmp/wp01/container-report.json")
checks = []
containers = []


def docker(*args, check=True, timeout=240):
    return subprocess.run(["docker", *args], check=check, capture_output=True, text=True, timeout=timeout)


def record(name, condition):
    checks.append({"name": name, "passed": bool(condition)})
    if not condition:
        raise AssertionError(name)
    print("PASS:", name, flush=True)


class FormParser(html.parser.HTMLParser):
    def __init__(self):
        super().__init__()
        self.csrf = None

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == "input" and attrs.get("name") == "authenticity_token":
            self.csrf = attrs.get("value")


class Browser:
    def __init__(self, port):
        self.port = port
        self.cookies = {}

    def request(self, method, path, data=None, host="campfire.example.test", headers=None):
        connection = http.client.HTTPConnection("127.0.0.1", self.port, timeout=10)
        request_headers = {
            "Host": host,
            "X-Forwarded-Proto": "https",
            "Origin": ORIGIN,
            "User-Agent": "Mozilla/5.0 Chrome/140.0.0.0 Safari/537.36",
            "Cookie": "; ".join(f"{k}={v}" for k, v in self.cookies.items()),
        }
        if headers:
            request_headers.update(headers)
        if data is not None:
            data = urllib.parse.urlencode(data)
            request_headers["Content-Type"] = "application/x-www-form-urlencoded"
        connection.request(method, path, body=data, headers=request_headers)
        response = connection.getresponse()
        status, response_headers = response.status, response.getheaders()
        body = response.read().decode("utf-8", errors="replace") if status != 101 else ""
        connection.close()
        for name, value in response_headers:
            if name.lower() == "set-cookie":
                cookie = http.cookies.SimpleCookie()
                cookie.load(value)
                self.cookies.update({k: morsel.value for k, morsel in cookie.items()})
        return status, response_headers, body


def write_env(path, values):
    path.write_text("".join(f"{k}={v}\n" for k, v in values.items()), encoding="utf-8")
    path.chmod(0o600)


def start(name, envfile, volume=VOLUME, *, need_browser=True):
    command = ["run", "-d", "--name", name, "--env-file", str(envfile), "-p", "127.0.0.1::8765"]
    if volume:
        command += ["--mount", f"type=volume,src={volume},dst=/rails/storage"]
    docker(*command, IMAGE)
    containers.append(name)
    if not need_browser:
        return None
    port = int(docker("port", name, "8765/tcp").stdout.strip().split(":")[-1])
    return Browser(port)


def wait_ready(browser, name):
    deadline = time.monotonic() + 180
    while time.monotonic() < deadline:
        if docker("inspect", "--format", "{{.State.Running}}", name).stdout.strip() != "true":
            raise AssertionError("Container exited before readiness")
        try:
            if browser.request("GET", "/readyz")[0] == 200:
                return
        except (OSError, http.client.HTTPException):
            pass
        time.sleep(1)
    raise AssertionError("Readiness timed out")


def expect_exit(name, envfile, *, volume, message):
    start(name, envfile, volume=volume, need_browser=False)
    status = docker("wait", name, timeout=90).stdout.strip()
    logs = docker("logs", name).stdout + docker("logs", name).stderr
    record(message, status != "0")
    return logs


def runner(name, code):
    return docker("exec", "--user", "1000:1000", name, "bin/rails", "runner", code).stdout


with tempfile.TemporaryDirectory() as temporary:
    envfile = Path(temporary) / "runtime.env"
    key_code = ('k=OpenSSL::PKey::EC.generate("prime256v1"); '
                'puts JSON.generate({public: Base64.urlsafe_encode64(k.public_key.to_octet_string(:uncompressed), padding: false), '
                'private: Base64.urlsafe_encode64(k.private_key.to_s(2).rjust(32, "\\0"), padding: false)})')
    keys = json.loads(docker("run", "--rm", "--entrypoint", "ruby", IMAGE,
                             "-ropenssl", "-rbase64", "-rjson", "-e", key_code).stdout)
    environment = {
        "CAMPFIRE_PROXY_MODE": "railway", "CAMPFIRE_PUBLIC_URL": ORIGIN,
        "SECRET_KEY_BASE": secrets.token_hex(64), "CAMPFIRE_RECOVERY_EPOCH": secrets.token_hex(32),
        "CAMPFIRE_BOOTSTRAP_SECRET": secrets.token_hex(32),
        "VAPID_PUBLIC_KEY": keys["public"], "VAPID_PRIVATE_KEY": keys["private"],
        "PORT": "8765", "CAMPFIRE_PUMA_PORT": "3001", "WEB_CONCURRENCY": "1", "JOB_CONCURRENCY": "1",
        "CAMPFIRE_AGENT_ENABLED": "false", "CAMPFIRE_AGENT_DISPATCH_ENABLED": "false", "SKIP_TELEMETRY": "true",
    }
    write_env(envfile, environment)
    docker("volume", "create", VOLUME)
    try:
        logs = expect_exit(NAME + "-no-volume", envfile, volume=None, message="Missing persistent volume fails closed")
        record("Missing-volume diagnostic is actionable", "Mount a persistent volume" in logs)
        browser = start(NAME, envfile)
        wait_ready(browser, NAME)
        record("Fresh mounted database becomes ready", True)
        record("Process liveness is unauthenticated", browser.request("GET", "/healthz")[0] == 200)
        record("Legacy health route is preserved", browser.request("GET", "/up")[0] == 200)
        record("Railway health host works", browser.request("GET", "/readyz", host="healthcheck.railway.app")[0] == 200)
        record("Health host cannot access setup", browser.request("GET", "/first_run", host="healthcheck.railway.app")[0] == 403)
        record("Unapproved Host is rejected", browser.request("GET", "/first_run", host="evil.example.test")[0] == 403)
        status, headers, form = browser.request("GET", "/first_run")
        record("Setup is served without HTTPS redirect loops", status == 200)
        record("Setup is uncacheable", any(k.lower() == "cache-control" and "no-store" in v for k, v in headers))
        record("Setup never discloses bootstrap secret", environment["CAMPFIRE_BOOTSTRAP_SECRET"] not in form)
        parser = FormParser()
        parser.feed(form)
        record("Setup preserves CSRF form protection", bool(parser.csrf))
        fields = {"user[name]": "WP01 operator", "user[email_address]": "wp01@example.test", "user[password]": "synthetic-wp01-password"}
        status, _, _ = browser.request("POST", "/first_run", {**fields, "bootstrap_secret": environment["CAMPFIRE_BOOTSTRAP_SECRET"]})
        record("Correct setup secret does not bypass CSRF", status == 422)
        fields["authenticity_token"] = parser.csrf
        status, _, _ = browser.request("POST", "/first_run", fields)
        record("Missing bootstrap secret cannot claim administrator", status == 403)
        status, _, _ = browser.request("POST", "/first_run", {**fields, "bootstrap_secret": "x" * 64})
        record("Incorrect bootstrap secret is rejected", status == 403)
        status, _, _ = browser.request("POST", "/first_run", {**fields, "user[name]": "", "bootstrap_secret": environment["CAMPFIRE_BOOTSTRAP_SECRET"]})
        record("Invalid administrator does not consume setup", status == 422)
        record("Failed setup leaves no account", "WP01_ACCOUNTS=0" in runner(NAME, 'puts "WP01_ACCOUNTS=#{Account.count}"'))
        status, headers, _ = browser.request("POST", "/first_run", {**fields, "bootstrap_secret": environment["CAMPFIRE_BOOTSTRAP_SECRET"]})
        record("Correct owner can create first administrator", status in {302, 303})
        session_headers = [v.lower() for k, v in headers if k.lower() == "set-cookie" and "session_token=" in v]
        record("Human authentication cookie is Secure and HttpOnly", bool(session_headers) and all("secure" in v and "httponly" in v for v in session_headers))
        status, _, _ = browser.request("POST", "/first_run", {**fields, "bootstrap_secret": environment["CAMPFIRE_BOOTSTRAP_SECRET"]})
        record("Completed setup cannot create another account", status in {302, 303})
        record("Exactly one administrator exists", "WP01_ADMINS=1" in runner(NAME, 'puts "WP01_ADMINS=#{User.where(role: :administrator).count}"'))
        ws_headers = {"Connection": "Upgrade", "Upgrade": "websocket", "Sec-WebSocket-Key": base64.b64encode(os.urandom(16)).decode(), "Sec-WebSocket-Version": "13", "Sec-WebSocket-Protocol": "actioncable-v1-json"}
        record("Authenticated Action Cable upgrades through Thrust", browser.request("GET", "/cable", headers=ws_headers)[0] == 101)
        record("Cross-origin Action Cable is rejected", browser.request("GET", "/cable", headers={**ws_headers, "Origin": "https://evil.example.test"})[0] != 101)
        runner(NAME, 'ActiveStorage::Blob.create_and_upload!(io: StringIO.new("wp01-persistent"), filename: "wp01-persistence.txt", content_type: "text/plain")')
        rows = docker("top", NAME, "-eo", "uid,pid,comm").stdout.splitlines()[1:]
        record("All service processes run as UID 1000", bool(rows) and all(row.split()[0] == "1000" for row in rows))
        metrics = docker("stats", "--no-stream", "--format", "{{json .}}", NAME).stdout.strip()
        docker("stop", "--time", "30", NAME)
        docker("rm", NAME)
        environment.pop("CAMPFIRE_BOOTSTRAP_SECRET")
        write_env(envfile, environment)
        browser = start(NAME + "-restart", envfile)
        wait_ready(browser, NAME + "-restart")
        record("Restart works after removing bootstrap secret", True)
        text = runner(NAME + "-restart", 'abort "lost admin" unless User.where(role: :administrator).count == 1; abort "lost file" unless ActiveStorage::Blob.find_by!(filename: "wp01-persistence.txt").download == "wp01-persistent"; puts "WP01_PERSISTENT"')
        record("SQLite records and uploaded bytes survive replacement", "WP01_PERSISTENT" in text)
        docker("stop", "--time", "30", NAME + "-restart")
        changed = {**environment, "SECRET_KEY_BASE": secrets.token_hex(64)}
        write_env(envfile, changed)
        logs = expect_exit(NAME + "-changed-secret", envfile, volume=VOLUME, message="Regenerated instance secret is rejected")
        record("Secret-drift error does not echo the secret", changed["SECRET_KEY_BASE"] not in logs)
        write_env(envfile, {**environment, "CAMPFIRE_AGENT_ENABLED": "true"})
        expect_exit(NAME + "-native", envfile, volume=VOLUME, message="Native enable flag is rejected in WP01")
        REPORT.parent.mkdir(parents=True, exist_ok=True)
        REPORT.write_text(json.dumps({"scope": "Docker smoke; synthetic data; not Railway qualification", "checks": checks, "single_idle_observation": json.loads(metrics)}, indent=2) + "\n")
    except Exception:
        REPORT.parent.mkdir(parents=True, exist_ok=True)
        REPORT.write_text(json.dumps({"checks": checks, "completed": False}, indent=2) + "\n")
        for container in containers:
            result = docker("logs", container, check=False)
            logs = result.stdout + result.stderr
            for key in ("SECRET_KEY_BASE", "VAPID_PRIVATE_KEY", "CAMPFIRE_BOOTSTRAP_SECRET"):
                value = environment.get(key)
                if value:
                    logs = logs.replace(value, "[FILTERED]")
            print(logs[-16000:], file=sys.stderr)
        raise
    finally:
        for container in containers:
            docker("rm", "--force", container, check=False)
        docker("volume", "rm", VOLUME, check=False)
