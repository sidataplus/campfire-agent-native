from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
import re

from .client import Client
from .journal import Journal
from .worker import stable_key


@dataclass(frozen=True)
class RunObservation:
    external_id: str
    title: str
    state: str
    source_revision: int
    reconciliation_reference: str


class ProjectionBridge:
    """Called by an existing runtime. Reporting a run never launches it."""
    def __init__(self, client: Client, journal: Journal, room_id: str):
        info = client.doctor()
        journal.bind(info["instance"]["instance_id"], info["instance"]["stream_epoch"])
        self.client, self.journal, self.room_id = client, journal, room_id
        self.profile_id = info["profile"]["id"]

    def report(self, observation: RunObservation) -> str:
        if not observation.external_id or not 1 <= len(observation.title) <= 100 or observation.source_revision < 1:
            raise ValueError("Invalid external run observation")
        key = stable_key(f"projection:{self.profile_id}:{observation.external_id}:{observation.source_revision}")
        mapping = "projection:" + observation.external_id
        previous = self.journal.replay_write(self.client, key)
        if previous is not None:
            run_id = previous["resource"]["id"]
            self.journal.set(mapping, {"id": run_id, "revision": observation.source_revision})
            return run_id
        known = self.journal.get(mapping)
        if known is None:
            if observation.state not in {"queued", "running", "waiting_for_human", "paused"}:
                raise ValueError("Publish an initial nonterminal observation before a terminal outcome")
            result = self.journal.write(self.client, "POST", "/api/agent/v1/runs", {
                "room_id": self.room_id, "external_run_id": observation.external_id, "title": observation.title,
                "state": observation.state, "source_revision": observation.source_revision, "owner_generation": 1,
                "context": {"references": [], "include_current_request": False},
                "reconciliation_reference": observation.reconciliation_reference}, key=key)
            run_id = result["resource"]["id"]
        else:
            if observation.source_revision <= known["revision"]:
                raise ValueError("External revisions must increase")
            run_id = known["id"]
            run = self.client.request("GET", f"/api/agent/v1/runs/{run_id}")
            self.journal.write(self.client, "PATCH", f"/api/agent/v1/runs/{run_id}", {
                "state": observation.state, "source_revision": observation.source_revision,
                "owner_generation": run["owner_generation"]}, key=key, etag=run["etag"])
        self.journal.set(mapping, {"id": run_id, "revision": observation.source_revision})
        return run_id


@dataclass(frozen=True)
class ServiceObservation:
    service: str
    state: str
    observed_at: str


class OrcaReadOnlyBridge:
    """Accepts an operator-approved summary from Orca's owner process, not its writable journal."""
    def __init__(self, client: Client, journal: Journal, room_id: str):
        info = client.doctor()
        journal.bind(info["instance"]["instance_id"], info["instance"]["stream_epoch"])
        self.client, self.journal, self.room_id = client, journal, room_id
        self.profile_id = info["profile"]["id"]

    def report(self, observation: ServiceObservation):
        if not re.fullmatch(r"[A-Za-z0-9_. -]{1,80}", observation.service):
            raise ValueError("Service display name must be a bounded public identifier")
        if observation.state not in {"unknown", "queued", "running", "draining", "stopped", "failed"}:
            raise ValueError("Unknown observation must not be interpreted as spare capacity")
        if datetime.fromisoformat(observation.observed_at.replace("Z", "+00:00")).tzinfo is None:
            raise ValueError("Observation timestamp must carry a timezone")
        key = stable_key(f"orca-report:{self.profile_id}:{observation.service}:{observation.observed_at}")
        return self.journal.write(self.client, "POST", f"/api/agent/v1/rooms/{self.room_id}/messages", {
            "body_text": f"ORCA {observation.service}: reported {observation.state} at {observation.observed_at}. This is read-only observation.",
            "client_message_id": key}, key=key)


def conversation_binding(instance_id: str, room_id: str, profile_id: str, run_id: str | None = None) -> str:
    """Opaque runtime session key; no shared memory or task scheduler is implied."""
    return stable_key(f"conversation:{instance_id}:{room_id}:{profile_id}:{run_id or 'conversation'}")
