from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys
import time

from .client import ApiError, Client, TransportError, read_token
from .journal import Journal, RecoveryRequired
from .worker import ReferenceWorker


def main() -> int:
    parser = argparse.ArgumentParser(description="Native Agent Campfire client. No human approval commands are exposed.")
    parser.add_argument("--url", required=True)
    parser.add_argument("--token-file", type=Path, required=True)
    parser.add_argument("--allow-loopback-http", action="store_true", help="Synthetic localhost tests only")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("doctor", help="Read instance/profile information without creating anything")
    sub.add_parser("rooms", help="Read the first authorized room page")
    worker = sub.add_parser("reference-worker", help="Run the synthetic fixture worker, never real infrastructure")
    worker.add_argument("--state-dir", type=Path, required=True)
    worker.add_argument("--name", default="reference-worker")
    worker.add_argument("--ticks", type=int, default=1, help="0 runs until interrupted")
    worker.add_argument("--poll-seconds", type=float, default=3)
    args = parser.parse_args()
    journal = None
    try:
        client = Client(args.url, read_token(args.token_file), allow_loopback_http=args.allow_loopback_http)
        if args.command == "doctor":
            print(json.dumps(client.doctor(), indent=2))
        elif args.command == "rooms":
            print(json.dumps(client.request("GET", "/api/agent/v1/rooms"), indent=2))
        else:
            if args.ticks < 0 or not 1 <= args.poll_seconds <= 300:
                raise ValueError("Invalid tick or polling interval")
            journal = Journal(args.state_dir)
            runner = ReferenceWorker(client, journal, args.name)
            tick = 0
            while args.ticks == 0 or tick < args.ticks:
                print(json.dumps(runner.tick()), flush=True)
                tick += 1
                if args.ticks == 0 or tick < args.ticks:
                    time.sleep(args.poll_seconds)
        return 0
    except RecoveryRequired as error:
        print(json.dumps({"error": "recovery_required", "detail": str(error)}), file=sys.stderr)
        return 4
    except ApiError as error:
        print(json.dumps({"error": error.code, "status": error.status}), file=sys.stderr)
        return 3
    except (ValueError, OSError, TransportError) as error:
        print(json.dumps({"error": type(error).__name__, "detail": str(error)}), file=sys.stderr)
        return 2
    except KeyboardInterrupt:
        return 130
    finally:
        if journal is not None:
            journal.close()


if __name__ == "__main__":
    raise SystemExit(main())
