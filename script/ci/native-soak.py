#!/usr/bin/env python3
"""Bounded read-only observation sampler; never fabricates a production capacity claim."""
import argparse
import json
from pathlib import Path
import statistics
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "clients/python"))
from agent_campfire_client import ApiError, Client, TransportError, read_token

parser = argparse.ArgumentParser()
parser.add_argument("--url", required=True)
parser.add_argument("--token-file", type=Path, required=True)
parser.add_argument("--seconds", type=int, default=60)
parser.add_argument("--interval", type=float, default=3)
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()
if not 1 <= args.seconds <= 86400 or not 1 <= args.interval <= 300:
    parser.error("Bounded duration/interval required")
client = Client(args.url, read_token(args.token_file), retries=0)
latencies, failures = [], {}
started = time.monotonic()
while time.monotonic() - started < args.seconds:
    before = time.monotonic()
    try:
        client.request("GET", "/api/agent/v1/instance")
        latencies.append(time.monotonic() - before)
    except (ApiError, TransportError) as error:
        label = error.code if isinstance(error, ApiError) else "transport"
        failures[label] = failures.get(label, 0) + 1
    time.sleep(min(args.interval, max(0, args.seconds - (time.monotonic() - started))))
report = {"scope": "read-only sampler; combine with separately authorized synthetic worker load", "seconds": time.monotonic() - started,
    "successful_samples": len(latencies), "failures": failures, "median_seconds": statistics.median(latencies) if latencies else None,
    "p95_seconds": sorted(latencies)[max(0, int(len(latencies) * .95) - 1)] if latencies else None}
with args.output.open("x") as output:
    json.dump(report, output, indent=2)
    output.write("\n")
raise SystemExit(1 if failures or not latencies else 0)
