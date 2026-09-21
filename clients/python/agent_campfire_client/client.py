from __future__ import annotations

import hashlib
import http.client
import json
import os
from pathlib import Path
import re
import ssl
import stat
import time
import urllib.error
import urllib.parse
import urllib.request
from typing import Any


class ApiError(RuntimeError):
    def __init__(self, status: int, code: str):
        self.status, self.code = status, code
        super().__init__(f"HTTP {status}: {code}")


class TransportError(RuntimeError):
    def __init__(self, uncertain: bool):
        self.uncertain = uncertain
        super().__init__("Transport failed; retain the original idempotency key and inspect the journal")


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def read_token(path: str | Path) -> str:
    fd = os.open(path, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0))
    with os.fdopen(fd, "r", encoding="utf-8") as source:
        info = os.fstat(source.fileno())
        if not stat.S_ISREG(info.st_mode) or info.st_mode & 0o077:
            raise ValueError("Token file must be a private regular file (mode 0600 or 0400)")
        token = source.read(256).strip()
    if not re.fullmatch(r"acn_[A-Za-z0-9_-]{43}", token):
        raise ValueError("Invalid native token format")
    return token


class Client:
    """HTTP/JSON only. It never submits human approvals or executes agent work."""
    MAX_JSON_RESPONSE_BYTES = 4_194_304
    MAX_UPLOAD_BYTES = 26_214_400
    MAX_UPLOAD_RESPONSE_BYTES = 65_536

    def __init__(self, origin: str, token: str, *, timeout: float = 15, retries: int = 2,
                 allow_loopback_http: bool = False, opener=None, sleep=time.sleep):
        url = urllib.parse.urlsplit(origin)
        test_origin = allow_loopback_http and url.scheme == "http" and url.hostname in {"127.0.0.1", "::1", "localhost"}
        if (url.scheme != "https" and not test_origin) or not url.hostname or url.username or url.password or url.query or url.fragment or url.path not in {"", "/"}:
            raise ValueError("Base URL must be an HTTPS origin; plain HTTP is loopback-test-only")
        if not re.fullmatch(r"acn_[A-Za-z0-9_-]{43}", token):
            raise ValueError("Invalid token format")
        if not 0 < timeout <= 120 or not 0 <= retries <= 5:
            raise ValueError("Invalid timeout/retry budget")
        self.origin, self._token = origin.rstrip("/"), token
        self.timeout, self.retries, self.sleep = timeout, retries, sleep
        self.opener = opener or urllib.request.build_opener(
            urllib.request.ProxyHandler({}), NoRedirect(), urllib.request.HTTPSHandler(context=ssl.create_default_context()))

    def request(self, method: str, path: str, body: dict[str, Any] | None = None,
                *, key: str | None = None, etag: str | None = None) -> dict[str, Any]:
        method = method.upper()
        decoded = urllib.parse.unquote(path.split("?", 1)[0])
        if not decoded.startswith("/api/agent/v1/") or any(p in {".", ".."} for p in decoded.split("/")) or "\\" in decoded or "#" in path:
            raise ValueError("Only native API paths are accepted")
        if method not in {"GET", "POST", "PUT", "PATCH", "DELETE"}:
            raise ValueError("Unsupported HTTP method")
        if method != "GET" and (not key or not 16 <= len(key) <= 128):
            raise ValueError("Mutations require a caller-persisted idempotency key")
        data = None if body is None else json.dumps(body, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()
        if data is not None and len(data) > 262144:
            raise ValueError("JSON request exceeds the native limit")
        headers = {"Authorization": f"Bearer {self._token}", "Accept": "application/json", "User-Agent": "agent-campfire-client/0.1"}
        if data is not None:
            headers["Content-Type"] = "application/json"
        if key:
            headers["Idempotency-Key"] = key
        if etag:
            headers["If-Match"] = etag
        for attempt in range(self.retries + 1):
            request = urllib.request.Request(self.origin + path, data=data, headers=headers, method=method)
            try:
                with self.opener.open(request, timeout=self.timeout) as response:
                    raw = self._read_response(response, self.MAX_JSON_RESPONSE_BYTES)
                    if not raw:
                        return {}
                    value = json.loads(raw)
                    if not isinstance(value, dict):
                        raise ApiError(getattr(response, "status", 502), "invalid_response")
                    return value
            except urllib.error.HTTPError as error:
                code = "http_error"
                try:
                    problem = json.loads(error.read(65536))
                    if isinstance(problem, dict) and re.fullmatch(r"[A-Z_]{1,80}", str(problem.get("code", ""))):
                        code = problem["code"]
                except (ValueError, OSError):
                    pass
                if error.code not in {429, 500, 502, 503, 504} or attempt == self.retries:
                    raise ApiError(error.code, code) from None
            except (http.client.IncompleteRead, OSError, urllib.error.URLError):
                if attempt == self.retries:
                    raise TransportError(method != "GET") from None
            except (ValueError, UnicodeError):
                raise ApiError(502, "invalid_response") from None
            self.sleep(min(2 ** attempt, 8))
        raise AssertionError("unreachable")

    def doctor(self) -> dict[str, Any]:
        instance = self.request("GET", "/api/agent/v1/instance")
        profile = self.request("GET", "/api/agent/v1/self")
        return {"instance": instance, "profile": profile, "read_only": True}

    def upload(self, room_id: str, path: Path, *, key: str) -> dict[str, Any]:
        if not 16 <= len(key) <= 128 or not re.fullmatch(r"[0-9]{1,24}", room_id):
            raise ValueError("Invalid upload target or key")
        filename = path.name
        if any(c in filename for c in '\r\n"'):
            raise ValueError("Upload must be a bounded regular file with a safe filename")
        fd = os.open(path, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0))
        try:
            info = os.fstat(fd)
            if not stat.S_ISREG(info.st_mode) or not 0 < info.st_size <= self.MAX_UPLOAD_BYTES:
                raise ValueError("Upload must be a bounded regular file with a safe filename")
            with os.fdopen(fd, "rb") as source:
                fd = None
                data = source.read(self.MAX_UPLOAD_BYTES + 1)
        finally:
            if fd is not None:
                os.close(fd)
        if len(data) != info.st_size or len(data) > self.MAX_UPLOAD_BYTES:
            raise ValueError("Upload changed while it was being read")
        boundary = "campfire-" + hashlib.sha256(key.encode()).hexdigest()
        parts = []
        for name, value in {"room_id": room_id, "filename": filename, "content_type": "application/octet-stream"}.items():
            parts.append(f'--{boundary}\r\nContent-Disposition: form-data; name="{name}"\r\n\r\n{value}\r\n'.encode())
        parts += [f'--{boundary}\r\nContent-Disposition: form-data; name="file"; filename="{filename}"\r\nContent-Type: application/octet-stream\r\n\r\n'.encode(), data, f'\r\n--{boundary}--\r\n'.encode()]
        body = b"".join(parts)
        headers = {"Authorization": f"Bearer {self._token}", "Idempotency-Key": key,
            "Content-Type": f"multipart/form-data; boundary={boundary}", "Accept": "application/json"}
        for attempt in range(self.retries + 1):
            request = urllib.request.Request(self.origin + "/api/agent/v1/uploads", data=body, method="POST", headers=headers)
            try:
                with self.opener.open(request, timeout=self.timeout) as response:
                    raw = self._read_response(response, self.MAX_UPLOAD_RESPONSE_BYTES)
                    if not raw:
                        return {}
                    value = json.loads(raw)
                    if not isinstance(value, dict):
                        raise ApiError(getattr(response, "status", 502), "invalid_response")
                    return value
            except urllib.error.HTTPError as error:
                raise ApiError(error.code, "upload_failed") from None
            except (http.client.IncompleteRead, OSError, urllib.error.URLError):
                if attempt == self.retries:
                    raise TransportError(True) from None
            except (ValueError, UnicodeError):
                raise ApiError(502, "invalid_response") from None
            self.sleep(min(2 ** attempt, 8))
        raise AssertionError("unreachable")

    @staticmethod
    def _read_response(response, limit: int) -> bytes:
        headers = getattr(response, "headers", None)
        expected = headers.get("Content-Length") if headers is not None else None
        if expected is not None:
            try:
                expected = int(expected)
            except (TypeError, ValueError):
                raise ValueError("Invalid response length") from None
            if expected < 0:
                raise ValueError("Invalid response length")
            if expected > limit:
                raise ApiError(getattr(response, "status", 502), "response_too_large")
        raw = response.read(limit + 1)
        if expected is not None and len(raw) != expected:
            raise http.client.IncompleteRead(raw, expected)
        if len(raw) > limit:
            raise ApiError(getattr(response, "status", 502), "response_too_large")
        return raw
