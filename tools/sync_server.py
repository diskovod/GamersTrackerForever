"""Loopback-only prototype sync server with one JSON document per character.

Run explicitly; it does not install a Windows service or expose a public port.
Python's sqlite3 is embedded, so no database server installation is needed.
"""

from __future__ import annotations

import argparse
from contextlib import closing
import hashlib
import hmac
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import secrets
import sqlite3
import time
from urllib.parse import parse_qs, urlparse


MAX_DOCUMENT_BYTES = 2 * 1024 * 1024
SUPPORTED_PRODUCTS = {"classic_era", "forever_beta"}


def init_database(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with closing(sqlite3.connect(path)) as db, db:
        db.execute("PRAGMA journal_mode=WAL")
        db.execute("""CREATE TABLE IF NOT EXISTS character_snapshots (
            owner_id TEXT NOT NULL,
            product TEXT NOT NULL,
            character_key TEXT NOT NULL,
            revision INTEGER NOT NULL,
            content_hash TEXT NOT NULL,
            document TEXT NOT NULL,
            received_at INTEGER NOT NULL,
            PRIMARY KEY (owner_id, product, character_key)
        )""")


def read_or_create_token(path: Path) -> str:
    path.parent.mkdir(parents=True, exist_ok=True)
    if not path.exists():
        try:
            descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        except FileExistsError:
            pass
        else:
            with os.fdopen(descriptor, "w", encoding="utf-8") as token_file:
                token_file.write(secrets.token_urlsafe(48) + "\n")
    token = path.read_text(encoding="utf-8").strip()
    if len(token) < 32:
        raise ValueError("token file must contain at least 32 characters")
    return token


def _reject_duplicate_keys(pairs: list[tuple[str, object]]) -> dict[str, object]:
    result: dict[str, object] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate JSON key")
        result[key] = value
    return result


def _reject_constant(value: str) -> None:
    raise ValueError("non-finite JSON number: " + value)


def validate_document(body: bytes) -> tuple[str, str, str, str]:
    if not body or len(body) > MAX_DOCUMENT_BYTES:
        raise ValueError("snapshot size out of range")
    data = json.loads(body.decode("utf-8"), object_pairs_hook=_reject_duplicate_keys, parse_constant=_reject_constant)
    if not isinstance(data, dict) or type(data.get("schemaVersion")) is not int or data["schemaVersion"] != 1:
        raise ValueError("unsupported snapshot schema")
    product = data.get("product")
    character_key = data.get("characterKey")
    if not isinstance(product, str) or product not in SUPPORTED_PRODUCTS \
        or not isinstance(character_key, str) or not (1 <= len(character_key) <= 128):
        raise ValueError("invalid product or character key")
    if not isinstance(data.get("character"), dict) or data["character"].get("guid") != character_key:
        raise ValueError("character GUID/key mismatch")
    if not isinstance(data.get("professions"), dict) or not isinstance(data.get("inventory"), dict):
        raise ValueError("missing profession or inventory snapshot")
    canonical = json.dumps(data, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False)
    digest = hashlib.sha256(canonical.encode("utf-8")).hexdigest()
    return product, character_key, canonical, digest


def save_snapshot(db_path: Path, owner_id: str, body: bytes) -> tuple[int, str, bool]:
    product, character_key, document, digest = validate_document(body)
    with closing(sqlite3.connect(db_path, timeout=10)) as db, db:
        db.execute("BEGIN IMMEDIATE")
        previous = db.execute(
            "SELECT revision, content_hash FROM character_snapshots WHERE owner_id=? AND product=? AND character_key=?",
            (owner_id, product, character_key),
        ).fetchone()
        if previous and previous[1] == digest:
            return previous[0], digest, False
        revision = previous[0] + 1 if previous else 1
        db.execute("""INSERT INTO character_snapshots
            (owner_id, product, character_key, revision, content_hash, document, received_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(owner_id, product, character_key) DO UPDATE SET
              revision=excluded.revision, content_hash=excluded.content_hash,
              document=excluded.document, received_at=excluded.received_at""",
            (owner_id, product, character_key, revision, digest, document, int(time.time())),
        )
    return revision, digest, True


def list_snapshots(db_path: Path, owner_id: str, product: str | None = None) -> list[dict[str, object]]:
    with closing(sqlite3.connect(db_path, timeout=10)) as db:
        if product:
            rows = db.execute("""SELECT revision, content_hash, document, received_at
                FROM character_snapshots WHERE owner_id=? AND product=? ORDER BY character_key""", (owner_id, product))
        else:
            rows = db.execute("""SELECT revision, content_hash, document, received_at
                FROM character_snapshots WHERE owner_id=? ORDER BY product, character_key""", (owner_id,))
        return [{"revision": row[0], "contentHash": row[1], "snapshot": json.loads(row[2]), "receivedAt": row[3]}
                for row in rows]


def create_server(db_path: Path, token: str, port: int = 8765) -> ThreadingHTTPServer:
    if len(token) < 32:
        raise ValueError("token is too short")
    init_database(db_path)

    class Handler(BaseHTTPRequestHandler):
        def _json(self, status: int, payload: object) -> None:
            content = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(content)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(content)

        def _authorized(self) -> bool:
            actual = self.headers.get("Authorization", "")
            if hmac.compare_digest(actual, "Bearer " + token):
                return True
            self._json(401, {"error": "unauthorized"})
            return False

        def do_PUT(self) -> None:
            if urlparse(self.path).path != "/v1/snapshots":
                self._json(404, {"error": "not found"})
                return
            if not self._authorized():
                return
            length_text = self.headers.get("Content-Length", "")
            if not length_text.isdigit() or not (1 <= int(length_text) <= MAX_DOCUMENT_BYTES):
                self._json(413, {"error": "snapshot size out of range"})
                return
            try:
                revision, digest, changed = save_snapshot(db_path, "local", self.rfile.read(int(length_text)))
            except (ValueError, UnicodeDecodeError) as exc:
                self._json(400, {"error": str(exc)})
                return
            self._json(200, {"revision": revision, "contentHash": digest, "changed": changed})

        def do_GET(self) -> None:
            parsed = urlparse(self.path)
            if parsed.path != "/v1/snapshots":
                self._json(404, {"error": "not found"})
                return
            if not self._authorized():
                return
            product = parse_qs(parsed.query).get("product", [None])[0]
            if product is not None and product not in SUPPORTED_PRODUCTS:
                self._json(400, {"error": "invalid product"})
                return
            self._json(200, {"snapshots": list_snapshots(db_path, "local", product)})

        def log_message(self, format_string: str, *args: object) -> None:
            # Avoid echoing private character data or authorization headers.
            pass

    return ThreadingHTTPServer(("127.0.0.1", port), Handler)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--database", type=Path, required=True, help="local SQLite database file")
    parser.add_argument("--token-file", type=Path, required=True, help="local secret shared with the companion")
    parser.add_argument("--port", type=int, default=8765)
    args = parser.parse_args()
    if not (1 <= args.port <= 65535):
        parser.error("invalid port")
    token = read_or_create_token(args.token_file)
    server = create_server(args.database, token, args.port)
    print(f"GamersTrackerForever sync listening on 127.0.0.1:{args.port}", flush=True)
    try:
        server.serve_forever(poll_interval=0.25)
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
