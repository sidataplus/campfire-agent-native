import json
from pathlib import Path
import tempfile
import unittest

from agent_campfire_client import Journal, RecoveryRequired, TransportError
from agent_campfire_client.worker import ReferenceWorker


class JournalTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.path = Path(self.temporary.name) / "state"
        self.journal = Journal(self.path)
        self.journal.bind("instance", "epoch")

    def tearDown(self):
        self.journal.close()
        self.temporary.cleanup()

    def test_ingestion_and_cursor_are_atomic(self):
        event = {"id": "one", "type": "message.created"}
        self.journal.ingest([event], "cursor-1")
        with self.assertRaises(RecoveryRequired):
            self.journal.ingest([{"id": "one", "type": "invocation.created"}], "cursor-2")
        self.assertEqual("cursor-1", self.journal.get("cursor"))
        self.assertEqual([event], self.journal.pending())

    def test_duplicate_events_are_not_new_work(self):
        event = {"id": "one", "type": "message.created"}
        self.journal.ingest([event, event], "cursor")
        self.journal.done("one")
        self.journal.ingest([event], "cursor")
        self.assertEqual([], self.journal.pending())

    def test_epoch_change_preserves_effect_journal(self):
        self.journal.effect_once("op", {"result": 1})
        with self.assertRaises(RecoveryRequired):
            self.journal.bind("instance", "new-epoch")
        self.assertEqual(1, self.journal.effect_count())
        self.assertEqual("epoch", self.journal.get("instance")["epoch"])

    def test_synthetic_effect_survives_restart(self):
        self.journal.effect_once("op", {"result": 1})
        self.journal.close()
        self.journal = Journal(self.path)
        self.assertEqual({"result": 1}, self.journal.effect_once("op", {"result": 2}))
        self.assertEqual(1, self.journal.effect_count())

    def test_only_one_worker_owns_state(self):
        with self.assertRaises(RuntimeError):
            Journal(self.path)

    def test_lost_write_acknowledgement_reuses_identical_request(self):
        class Server:
            def __init__(self):
                self.results = {}
                self.calls = 0
            def request(server, method, path, body, *, key, etag=None):
                server.calls += 1
                server.results.setdefault(key, {"resource": {"type": "message", "id": "1"}, "replayed": False})
                if server.calls == 1:
                    raise TransportError(True)
                return server.results[key]
        server = Server()
        key = "persistent-key-0001"
        with self.assertRaises(TransportError):
            self.journal.write(server, "POST", "/api/agent/v1/rooms/1/messages", {"body_text": "hello"}, key=key)
        self.journal.close()
        self.journal = Journal(self.path)
        result = self.journal.replay_write(server, key)
        self.assertEqual("1", result["resource"]["id"])
        self.assertEqual(1, len(server.results))
        with self.assertRaises(ValueError):
            self.journal.write(server, "POST", "/api/agent/v1/rooms/1/messages", {"body_text": "changed"}, key=key)

    def test_enrollment_key_is_unique_to_each_journal(self):
        class Server:
            def __init__(self): self.keys = []
            def doctor(server):
                return {"instance": {"instance_id": "instance", "stream_epoch": "epoch"}, "profile": {"id": "profile"}}
            def request(server, method, path, body, *, key, etag=None):
                server.keys.append(key)
                return {"id": "consumer-" + str(len(server.keys)), "cursor": "cursor"}

        server = Server()
        with tempfile.TemporaryDirectory() as directory:
            first_path = Path(directory) / "first"
            first = Journal(first_path)
            ReferenceWorker(server, first, "same-name")
            first_nonce = first.get("enrollment_nonce")
            first.close()

            second_path = Path(directory) / "second"
            second = Journal(second_path)
            ReferenceWorker(server, second, "same-name")
            second_nonce = second.get("enrollment_nonce")
            second.close()

        self.assertIsNotNone(first_nonce)
        self.assertNotEqual(first_nonce, second_nonce)
        self.assertNotEqual(server.keys[0], server.keys[1])

    def test_private_directory_required(self):
        public = Path(self.temporary.name) / "public"
        public.mkdir(mode=0o755)
        with self.assertRaises(ValueError):
            Journal(public)

    def test_symlink_database_rejected(self):
        other = Path(self.temporary.name) / "other"
        other.mkdir(mode=0o700)
        (other / "journal.sqlite3").symlink_to(self.path / "journal.sqlite3")
        with self.assertRaises(ValueError):
            Journal(other)
