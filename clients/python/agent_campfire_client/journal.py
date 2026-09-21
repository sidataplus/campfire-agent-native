from __future__ import annotations

from contextlib import contextmanager
import fcntl
import hashlib
import json
import os
from pathlib import Path
import sqlite3
import stat
from typing import Any


class RecoveryRequired(RuntimeError):
    pass


def canonical(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), allow_nan=False)


class Journal:
    """Single-owner local journal. Effect deduplication is synthetic, not a distributed claim."""
    def __init__(self, directory: str | Path):
        root = Path(directory)
        root.mkdir(mode=0o700, parents=True, exist_ok=True)
        if root.is_symlink() or root.stat().st_mode & 0o077:
            raise ValueError("Journal directory must be private (0700) and not a symlink")
        self._lock = os.open(root / "owner.lock", os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
        try:
            fcntl.flock(self._lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            os.close(self._lock)
            raise RuntimeError("Another adapter owns this journal") from None
        path = root / "journal.sqlite3"
        if path.exists() and (path.is_symlink() or not stat.S_ISREG(path.lstat().st_mode)):
            self.close()
            raise ValueError("Journal database must be a regular file")
        fd = os.open(path, os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
        os.close(fd)
        self.db = sqlite3.connect(path, isolation_level=None, timeout=10)
        self.db.row_factory = sqlite3.Row
        self.db.execute("PRAGMA journal_mode=WAL")
        self.db.execute("PRAGMA synchronous=FULL")
        self.db.executescript('''
          CREATE TABLE IF NOT EXISTS metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL);
          CREATE TABLE IF NOT EXISTS inbox (id TEXT PRIMARY KEY, epoch TEXT NOT NULL, payload TEXT NOT NULL, processed INTEGER NOT NULL DEFAULT 0);
          CREATE TABLE IF NOT EXISTS outbox (key TEXT PRIMARY KEY, fingerprint TEXT NOT NULL, method TEXT NOT NULL, path TEXT NOT NULL, body TEXT NOT NULL, etag TEXT, response TEXT);
          CREATE TABLE IF NOT EXISTS operations (id TEXT PRIMARY KEY, payload TEXT NOT NULL);
          CREATE TABLE IF NOT EXISTS effects (operation_id TEXT PRIMARY KEY, result TEXT NOT NULL);
        ''')

    def close(self):
        if hasattr(self, "db"):
            self.db.close()
        if hasattr(self, "_lock"):
            os.close(self._lock)
            del self._lock

    @contextmanager
    def transaction(self):
        self.db.execute("BEGIN IMMEDIATE")
        try:
            yield
            self.db.execute("COMMIT")
        except BaseException:
            self.db.execute("ROLLBACK")
            raise

    def get(self, key: str, default=None):
        row = self.db.execute("SELECT value FROM metadata WHERE key=?", (key,)).fetchone()
        return json.loads(row[0]) if row else default

    def set(self, key: str, value: Any):
        self.db.execute("INSERT INTO metadata VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value", (key, canonical(value)))

    def bind(self, instance_id: str, epoch: str):
        with self.transaction():
            previous = self.get("instance")
            if previous and previous != {"id": instance_id, "epoch": epoch}:
                raise RecoveryRequired("Instance or stream epoch changed; retain the journal and reconcile externally")
            self.set("instance", {"id": instance_id, "epoch": epoch})

    def ingest(self, events: list[dict], next_cursor: str):
        epoch = self.get("instance")["epoch"]
        with self.transaction():
            for event in events:
                encoded = canonical(event)
                previous = self.db.execute("SELECT payload FROM inbox WHERE id=?", (event["id"],)).fetchone()
                if previous and previous[0] != encoded:
                    raise RecoveryRequired("Event identity changed contents")
                self.db.execute("INSERT OR IGNORE INTO inbox(id,epoch,payload) VALUES(?,?,?)", (event["id"], epoch, encoded))
            self.set("cursor", next_cursor)

    def pending(self):
        return [json.loads(row[0]) for row in self.db.execute("SELECT payload FROM inbox WHERE processed=0 ORDER BY rowid LIMIT 100")]

    def done(self, event_id: str):
        self.db.execute("UPDATE inbox SET processed=1 WHERE id=?", (event_id,))

    def operation(self, operation_id: str):
        row = self.db.execute("SELECT payload FROM operations WHERE id=?", (operation_id,)).fetchone()
        return json.loads(row[0]) if row else None

    def save_operation(self, operation_id: str, value: dict):
        self.db.execute("INSERT INTO operations VALUES(?,?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload", (operation_id, canonical(value)))

    def write(self, client, method: str, path: str, body: dict, *, key: str, etag: str | None = None):
        signature = hashlib.sha256(canonical([method, path, body, etag]).encode()).hexdigest()
        with self.transaction():
            row = self.db.execute("SELECT * FROM outbox WHERE key=?", (key,)).fetchone()
            if row and row["fingerprint"] != signature:
                raise ValueError("An outbox key cannot be reused for a different request")
            if row and row["response"] is not None:
                return json.loads(row["response"])
            self.db.execute("INSERT OR IGNORE INTO outbox(key,fingerprint,method,path,body,etag) VALUES(?,?,?,?,?,?)",
                            (key, signature, method, path, canonical(body), etag))
        result = client.request(method, path, body, key=key, etag=etag)
        with self.transaction():
            self.db.execute("UPDATE outbox SET response=? WHERE key=?", (canonical(result), key))
        return result

    def replay_write(self, client, key: str):
        row = self.db.execute("SELECT * FROM outbox WHERE key=?", (key,)).fetchone()
        if not row:
            return None
        return self.write(client, row["method"], row["path"], json.loads(row["body"]), key=key, etag=row["etag"])

    def effect_once(self, operation_id: str, value: dict):
        with self.transaction():
            row = self.db.execute("SELECT result FROM effects WHERE operation_id=?", (operation_id,)).fetchone()
            if row:
                return json.loads(row[0])
            self.db.execute("INSERT INTO effects VALUES(?,?)", (operation_id, canonical(value)))
            return value

    def effect_count(self) -> int:
        return self.db.execute("SELECT COUNT(*) FROM effects").fetchone()[0]
