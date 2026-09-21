from __future__ import annotations

from datetime import datetime, timedelta, timezone
import json
import secrets
import urllib.parse
import uuid

from .client import ApiError, Client
from .journal import Journal, RecoveryRequired

API = "/api/agent/v1"


def stable_key(value: str) -> str:
    return str(uuid.uuid5(uuid.NAMESPACE_URL, "agent-campfire:" + value))


class ReferenceWorker:
    """Deterministic fixture worker. It has no shell, model, scheduler or infrastructure authority."""
    def __init__(self, client: Client, journal: Journal, name: str = "reference-worker"):
        self.client, self.journal, self.name = client, journal, name
        info = client.doctor()
        self.profile = info["profile"]
        instance = info["instance"]
        journal.bind(instance["instance_id"], instance["stream_epoch"])
        self.identity = instance["instance_id"] + ":" + self.profile["id"]
        if journal.get("consumer") is None:
            enrollment_nonce = journal.get("enrollment_nonce")
            if enrollment_nonce is None:
                enrollment_nonce = secrets.token_urlsafe(24)
                journal.set("enrollment_nonce", enrollment_nonce)
            result = self.send("enroll:" + enrollment_nonce, "POST", API + "/consumers",
                {"name": name, "event_types": ["invocation.created", "action.resolved"], "room_ids": []})
            with journal.transaction():
                journal.set("consumer", result["id"])
                journal.set("cursor", result["cursor"])

    def send(self, phase: str, method: str, path: str, body: dict, etag: str | None = None):
        key = stable_key(self.identity + ":" + phase)
        previous = self.journal.replay_write(self.client, key)
        if previous is not None:
            return previous
        return self.journal.write(self.client, method, path, body, key=key, etag=etag)

    def tick(self) -> dict:
        consumer = self.journal.get("consumer")
        query = urllib.parse.urlencode({"consumer_id": consumer, "cursor": self.journal.get("cursor"), "limit": 100})
        page = self.client.request("GET", API + "/events?" + query)
        self.journal.ingest(page["events"], page["next_cursor"])
        self.send("ack:" + page["next_cursor"], "POST", API + f"/consumers/{consumer}/ack", {"cursor": page["next_cursor"]})
        processed = 0
        for event in self.journal.pending():
            if event["type"] == "invocation.created":
                self.invocation(event["resource"]["id"])
            elif event["type"] == "action.resolved":
                self.action(event["resource"]["id"])
            self.journal.done(event["id"])
            processed += 1
        return {"processed": processed, "synthetic_effects": self.journal.effect_count(), "has_more": page["has_more"]}

    def invocation(self, identifier: str):
        invocation = self.client.request("GET", API + f"/invocations/{identifier}")
        operation = self.journal.operation(identifier)
        if operation is None:
            if invocation["disposition"] != "pending":
                return
            operation = {"id": identifier, "input": invocation, "phase": "received"}
            self.journal.save_operation(identifier, operation)
        frozen = operation["input"]
        if operation["phase"] in {"completed", "waiting"}:
            return
        self.send(identifier + ":admit", "POST", API + f"/invocations/{identifier}/admission",
            {"disposition": "admitted", "source_digest": frozen["source_digest"], "runtime_operation_id": "reference/" + identifier}, frozen["etag"])
        operation["phase"] = "admitted"
        self.journal.save_operation(identifier, operation)
        effect = self.journal.effect_once(identifier, {"result": "synthetic reference operation completed"})
        text = frozen["normalized_input"].strip().lower()
        if frozen.get("run_id"):
            run_id = frozen["run_id"]
            self.send(identifier + ":followup", "POST", API + f"/runs/{run_id}/messages",
                {"body_text": "Reference follow-up accepted for this run only.", "client_message_id": stable_key(identifier + ":followup")})
        elif text.startswith(("task", "ask", "fail")):
            result = self.send(identifier + ":run", "POST", API + "/runs", {
                "room_id": frozen["room_id"], "external_run_id": "reference/" + identifier,
                "title": "Reference task", "state": "running", "owner_generation": 1, "source_revision": 1,
                "invocation_id": identifier, "context": frozen["context"]})
            run_id = result["resource"]["id"]
            operation["run_id"] = run_id
            self.journal.save_operation(identifier, operation)
            activity = {"operation_id": "reference-check", "kind": "analysis", "state": "completed", "summary": effect["result"],
                "evidence": [], "owner_generation": 1, "source_revision": 1}
            self.send(identifier + ":activity", "PUT", API + f"/runs/{run_id}/activities/reference-check", activity)
            if text.startswith("ask"):
                self.transition(identifier + ":wait", run_id, "waiting_for_human")
                action = {"run_id": run_id, "kind": "question", "operation": "reference.continue", "title": "Continue the reference task?",
                    "description": "Synthetic qualification only. No external infrastructure action will occur.", "arguments": {},
                    "input_schema": {"type": "object", "properties": {"choice": {"type": "string", "enum": ["continue", "stop"]}}, "required": ["choice"], "additionalProperties": False},
                    "subject_references": [], "reviewer_user_ids": [frozen["human_user_id"]],
                    "expires_at": (datetime.now(timezone.utc) + timedelta(minutes=10)).isoformat()}
                self.send(identifier + ":question", "POST", API + "/actions", action)
                operation["phase"] = "waiting"
                self.journal.save_operation(identifier, operation)
                return
            self.send(identifier + ":result", "POST", API + f"/runs/{run_id}/messages",
                {"body_text": effect["result"], "client_message_id": stable_key(identifier + ":result")})
            self.transition(identifier + ":finish", run_id, "failed" if text.startswith("fail") else "completed")
        else:
            self.send(identifier + ":reply", "POST", API + f"/rooms/{frozen['room_id']}/messages",
                {"body_text": "Reference worker is available. This is a synthetic status, not an infrastructure observation.",
                 "client_message_id": stable_key(identifier + ":reply")})
        operation["phase"] = "completed"
        self.journal.save_operation(identifier, operation)

    def transition(self, phase: str, run_id: str, state: str):
        existing = self.journal.replay_write(self.client, stable_key(self.identity + ":" + phase))
        if existing is not None:
            return existing
        run = self.client.request("GET", API + f"/runs/{run_id}")
        return self.send(phase, "PATCH", API + f"/runs/{run_id}",
            {"state": state, "owner_generation": run["owner_generation"], "source_revision": run["source_revision"] + 1}, run["etag"])

    def action(self, identifier: str):
        action = self.client.request("GET", API + f"/actions/{identifier}")
        if action["state"] != "resolved" or not action.get("decision_receipt_id") or not action.get("run_id"):
            return
        run_id = action["run_id"]
        row = self.journal.db.execute("SELECT id,payload FROM operations WHERE json_extract(payload,'$.run_id')=?", (run_id,)).fetchone()
        if not row:
            raise RecoveryRequired("Action targets a run absent from this runtime journal")
        decision = self.client.request("GET", API + f"/receipts/{action['decision_receipt_id']}")
        accepted = action["operation"] in {"reference.continue", "control.cancel"} and decision["result"] != "reject"
        stop = action["operation"] == "control.cancel" or not accepted
        if accepted and decision["evidence"]:
            context = self.client.request("POST", API + "/context/resolve", {"references": decision["evidence"], "include_current_request": False}, key=stable_key(identifier + ":context"))
            if any(item["availability"] != "available" for item in context["items"]):
                raise RecoveryRequired("Human response evidence changed")
            values = json.loads(context["items"][0]["body_text"])
            stop = values.get("choice") == "stop"
        receipt = {"subject": {"type": "action", "id": identifier}, "runtime_operation_id": "reference-action/" + identifier,
            "decision_receipt_id": decision["id"], "evidence": [], "kind": "admission", "source_revision": 1,
            "result": "accepted" if accepted else "rejected", "policy_reference": "reference-worker-v1:no-external-effects"}
        self.send(identifier + ":admission", "POST", API + "/receipts", receipt)
        if accepted:
            self.journal.effect_once("action/" + identifier, {"result": "stopped" if stop else "continued"})
            self.send(identifier + ":outcome", "POST", API + "/receipts", {**receipt, "kind": "outcome", "result": "succeeded", "source_revision": 2})
        self.transition(identifier + ":terminal", run_id, "cancelled" if stop else "completed")
        operation = json.loads(row["payload"])
        operation["phase"] = "completed"
        self.journal.save_operation(row["id"], operation)
