#!/usr/bin/env python3
"""Disposable local Rails HTTP qualification, including an SDK-independent client."""
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "clients/python"))
from agent_campfire_client import Client, Journal
from agent_campfire_client.worker import ReferenceWorker


def main():
    env = {**os.environ, "RAILS_ENV": "test", "CAMPFIRE_AGENT_ENABLED": "true", "CAMPFIRE_AGENT_DISPATCH_ENABLED": "true", "AGENT_NATIVE_CI_FIXTURE": "true"}
    with tempfile.TemporaryDirectory(prefix="agent-native-http-") as directory:
        seedfile = Path(directory) / "fixture.json"
        def seed(operation):
            result = subprocess.run(["bin/rails", "runner", "script/ci/native-seed.rb", str(seedfile), operation], cwd=ROOT, env=env,
                                    check=True, capture_output=True, text=True, timeout=90)
            return json.loads(result.stdout.strip().splitlines()[-1]) if operation != "setup" else None
        seed("setup")
        config = json.loads(seedfile.read_text())
        with socket.socket() as probe:
            probe.bind(("127.0.0.1", 0))
            port = probe.getsockname()[1]
        origin = f"http://127.0.0.1:{port}"
        log = open(Path(directory) / "server.log", "w+")
        server = subprocess.Popen(["bin/rails", "server", "-b", "127.0.0.1", "-p", str(port), "-P", str(Path(directory) / "server.pid")], cwd=ROOT, env=env, stdout=log, stderr=subprocess.STDOUT)
        journal = None
        checks = []
        def check(name, condition):
            if not condition: raise AssertionError(name)
            checks.append(name)
            print("PASS:", name, flush=True)
        # Independent transport: deliberately does not call the first-party client.
        def raw(method, path, payload=None, key=None):
            headers = {"Authorization": "Bearer " + config["token"], "Accept": "application/json"}
            data = None
            if payload is not None:
                headers["Content-Type"] = "application/json"
                data = json.dumps(payload).encode()
            if key: headers["Idempotency-Key"] = key
            request = urllib.request.Request(origin + path, data=data, headers=headers, method=method)
            try:
                with urllib.request.urlopen(request, timeout=15) as response:
                    return response.status, json.load(response)
            except urllib.error.HTTPError as error:
                return error.code, json.loads(error.read())
        try:
            for _ in range(90):
                if server.poll() is not None: raise AssertionError("Rails server exited before readiness")
                try:
                    if urllib.request.urlopen(origin + "/healthz", timeout=1).status == 200: break
                except OSError:
                    time.sleep(1)
            else: raise AssertionError("Rails HTTP readiness timed out")
            status, instance = raw("GET", "/api/agent/v1/instance")
            check("Independent client reads native instance", status == 200 and instance["native_dispatch_enabled"])
            status, profile = raw("GET", "/api/agent/v1/self")
            check("Independent client reads native identity", status == 200 and profile["id"] == config["profile_id"])
            path = f"/api/agent/v1/rooms/{config['room_id']}/messages"
            payload = {"body_text": "Synthetic independent HTTP client", "client_message_id": str(uuid.uuid4())}
            key = str(uuid.uuid4())
            status, created = raw("POST", path, payload, key)
            check("Independent client creates message", status == 201)
            status, replayed = raw("POST", path, payload, key)
            check("Duplicate mutation returns same resource", status == 201 and replayed["replayed"] and replayed["resource"] == created["resource"])
            status, _ = raw("POST", path, {**payload, "creator_id": config["human_id"]}, str(uuid.uuid4()))
            check("Unknown authority field is rejected", status == 422)
            status, _ = raw("GET", "/api/agent/v1/rooms/999999999999/messages")
            check("Unassigned room is inaccessible", status == 404)
            client = Client(origin, config["token"], allow_loopback_http=True, retries=0)
            journal = Journal(Path(directory) / "worker")
            worker = ReferenceWorker(client, journal, "http-qualification")
            seed("status")
            worker.tick()
            check("Interactive invocation executes one synthetic effect", journal.effect_count() == 1)
            seed("task")
            worker.tick()
            runs = client.request("GET", "/api/agent/v1/runs")["items"]
            check("Task invocation creates a completed owned run", any(run["state"] == "completed" for run in runs) and journal.effect_count() == 2)
            journal.close()
            journal = Journal(Path(directory) / "worker")
            worker = ReferenceWorker(client, journal, "http-qualification")
            worker.tick()
            check("Restart does not repeat admitted effects", journal.effect_count() == 2)
            seed("ask")
            worker.tick()
            answer = seed("respond")
            worker.tick()
            run = client.request("GET", f"/api/agent/v1/runs/{answer['run_id']}")
            check("Human question response has admission and outcome", run["state"] == "completed" and journal.effect_count() == 4)
            seed("ask")
            worker.tick()
            control = seed("cancel")
            before = client.request("GET", f"/api/agent/v1/runs/{control['run_id']}")
            check("Cancellation intent does not fake completion", before["state"] == "waiting_for_human")
            worker.tick()
            after = client.request("GET", f"/api/agent/v1/runs/{control['run_id']}")
            check("Runtime acknowledges cancellation separately", after["state"] == "cancelled")
            report = ROOT / "tmp/agent-stack/native-http-report.json"
            report.parent.mkdir(parents=True, exist_ok=True)
            report.write_text(json.dumps({"scope": "synthetic localhost Rails HTTP; not external-runtime or production qualification", "checks": checks}, indent=2) + "\n")
        finally:
            if journal: journal.close()
            server.terminate()
            try: server.wait(timeout=15)
            except subprocess.TimeoutExpired:
                server.kill(); server.wait()
            log.close()


if __name__ == "__main__":
    main()
