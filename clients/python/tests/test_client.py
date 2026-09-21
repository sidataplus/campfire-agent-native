import io
import http.client
import json
from pathlib import Path
import tempfile
import unittest
import urllib.error

from agent_campfire_client import ApiError, Client, TransportError, read_token
from agent_campfire_client.bridges import conversation_binding

TOKEN = "acn_" + "a" * 43


class Reply(io.BytesIO):
    status = 200
    headers = {}


class IncompleteReply:
    status = 200
    headers = {"Content-Length": "10"}

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False

    def read(self, _limit):
        raise http.client.IncompleteRead(b'{"ok"', 10)


class ClientTests(unittest.TestCase):
    def test_https_and_origin_are_required(self):
        for origin in ["http://example.test", "https://user:secret@example.test", "https://example.test/path", "https://example.test?key=1"]:
            with self.assertRaises(ValueError):
                Client(origin, TOKEN)
        Client("http://127.0.0.1:8888", TOKEN, allow_loopback_http=True)

    def test_human_routes_and_relative_traversal_rejected(self):
        client = Client("https://example.test", TOKEN)
        for path in ["/agent/actions/id/decisions", "https://evil.test/", "/api/agent/v1/../../agent"]:
            with self.assertRaises(ValueError):
                client.request("GET", path)

    def test_mutations_require_persisted_key(self):
        with self.assertRaises(ValueError):
            Client("https://example.test", TOKEN).request("POST", "/api/agent/v1/rooms/1/messages", {})

    def test_retries_retain_body_and_key(self):
        class Opener:
            def __init__(self): self.requests = []
            def open(self, request, timeout):
                self.requests.append(request)
                if len(self.requests) == 1: raise urllib.error.URLError("synthetic lost connection")
                return Reply(b'{"ok":true}')
        opener = Opener()
        client = Client("https://example.test", TOKEN, opener=opener, sleep=lambda _: None)
        client.request("POST", "/api/agent/v1/presence", {"state": "busy"}, key="stable-write-key-123")
        self.assertEqual(opener.requests[0].data, opener.requests[1].data)
        self.assertEqual(opener.requests[0].get_header("Idempotency-key"), opener.requests[1].get_header("Idempotency-key"))

    def test_incomplete_response_retries_before_success(self):
        class Opener:
            def __init__(self): self.calls = 0
            def open(self, request, timeout):
                self.calls += 1
                return IncompleteReply() if self.calls == 1 else Reply(b'{"ok":true}')
        opener = Opener()
        result = Client("https://example.test", TOKEN, opener=opener, sleep=lambda _: None).request("GET", "/api/agent/v1/self")
        self.assertEqual({"ok": True}, result)
        self.assertEqual(2, opener.calls)

    def test_repeated_incomplete_response_becomes_transport_error(self):
        class Opener:
            def __init__(self): self.calls = 0
            def open(self, request, timeout):
                self.calls += 1
                return IncompleteReply()
        opener = Opener()
        with self.assertRaisesRegex(TransportError, "Transport failed") as caught:
            Client("https://example.test", TOKEN, opener=opener, retries=1, sleep=lambda _: None).request("POST", "/api/agent/v1/presence", {}, key="stable-write-key-123")
        self.assertTrue(caught.exception.uncertain)
        self.assertEqual(2, opener.calls)

    def test_errors_do_not_echo_server_content_or_credentials(self):
        class Opener:
            def open(self, request, timeout):
                raise urllib.error.HTTPError(request.full_url, 403, "Forbidden", {}, Reply(json.dumps({"code": "FORBIDDEN", "detail": TOKEN}).encode()))
        with self.assertRaises(ApiError) as caught:
            Client("https://example.test", TOKEN, opener=Opener()).request("GET", "/api/agent/v1/self")
        self.assertEqual("FORBIDDEN", caught.exception.code)
        self.assertNotIn(TOKEN, str(caught.exception))

    def test_doctor_is_read_only(self):
        class Opener:
            def __init__(self): self.methods = []
            def open(self, request, timeout):
                self.methods.append(request.get_method())
                return Reply(b'{}')
        opener = Opener()
        self.assertTrue(Client("https://example.test", TOKEN, opener=opener).doctor()["read_only"])
        self.assertEqual(["GET", "GET"], opener.methods)

    def test_token_permissions_and_symlinks(self):
        with tempfile.TemporaryDirectory() as directory:
            token = Path(directory) / "token"
            token.write_text(TOKEN)
            token.chmod(0o600)
            self.assertEqual(TOKEN, read_token(token))
            token.chmod(0o644)
            with self.assertRaises(ValueError): read_token(token)
            alias = Path(directory) / "alias"
            alias.symlink_to(token)
            with self.assertRaises(OSError): read_token(alias)

    def test_upload_uses_one_private_fd_and_bounded_response(self):
        class Opener:
            def __init__(self): self.request = None
            def open(self, request, timeout):
                self.request = request
                return Reply(b'{"id":"upload"}')
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "result.bin"
            path.write_bytes(b"bytes")
            opener = Opener()
            result = Client("https://example.test", TOKEN, opener=opener).upload("12", path, key="upload-key-123456")
            self.assertEqual("upload", result["id"])
            self.assertIn(b"bytes", opener.request.data)
            alias = Path(directory) / "alias.bin"
            alias.symlink_to(path)
            with self.assertRaises(OSError):
                Client("https://example.test", TOKEN, opener=opener).upload("12", alias, key="upload-key-654321")

    def test_session_bindings_separate_conversations_and_runs(self):
        values = [conversation_binding("instance", "room", "agent", run) for run in (None, "run-1", "run-2")]
        self.assertEqual(3, len(set(values)))
        self.assertEqual(values[0], conversation_binding("instance", "room", "agent"))
