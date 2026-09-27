"""Safely export persisted WoW SavedVariables as per-character JSON snapshots.

This module never executes Lua and never modifies the game's SavedVariables.
It deliberately has no network or authentication configuration: those belong
to the future companion transport, after the server contract is agreed.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import tempfile
import time
from typing import Any
from urllib.parse import urlparse
from urllib.request import Request, urlopen


MAX_SOURCE_BYTES = 32 * 1024 * 1024
MAX_DEPTH = 80
MAX_FIELDS = 500_000
NUMBER = re.compile(r"-?(?:\d+\.\d*|\d*\.\d+|\d+)(?:[eE][+-]?\d+)?")
IDENTIFIER = re.compile(r"[A-Za-z_][A-Za-z_0-9]*")
ALLOWED_GLOBALS = {"GamersTrackerForeverDB", "AltCraftTrackerDB"}


class ExportError(ValueError):
    """A saved file or snapshot is unsafe, incomplete, or incompatible."""


class SavedVariablesParser:
    """Parse only the literal-table subset emitted by WoW, never arbitrary Lua."""

    def __init__(self, source: str):
        self.source = source
        self.position = 0
        self.fields = 0

    def _skip(self) -> None:
        while self.position < len(self.source):
            if self.source[self.position].isspace():
                self.position += 1
            elif self.source.startswith("--", self.position):
                end = self.source.find("\n", self.position)
                self.position = len(self.source) if end < 0 else end + 1
            else:
                return

    def _take(self, token: str) -> bool:
        self._skip()
        if self.source.startswith(token, self.position):
            self.position += len(token)
            return True
        return False

    def _expect(self, token: str) -> None:
        if not self._take(token):
            raise ExportError(f"expected {token!r} at offset {self.position}")

    def _identifier(self) -> str | None:
        self._skip()
        match = IDENTIFIER.match(self.source, self.position)
        if not match:
            return None
        self.position = match.end()
        return match.group()

    def _string(self) -> str:
        self._expect('"')
        result: list[str] = []
        while self.position < len(self.source):
            char = self.source[self.position]
            self.position += 1
            if char == '"':
                return "".join(result)
            if char == "\\":
                if self.position >= len(self.source):
                    break
                char = self.source[self.position]
                self.position += 1
                escapes = {"n": "\n", "r": "\r", "t": "\t", "\\": "\\", '"': '"', "'": "'"}
                if char in escapes:
                    result.append(escapes[char])
                elif char.isdigit():
                    digits = char
                    for _ in range(2):
                        if self.position < len(self.source) and self.source[self.position].isdigit():
                            digits += self.source[self.position]
                            self.position += 1
                    value = int(digits)
                    if value > 255:
                        raise ExportError("invalid Lua decimal escape")
                    result.append(chr(value))
                else:
                    raise ExportError(f"unsupported Lua string escape at offset {self.position}")
            else:
                if char in "\r\n":
                    raise ExportError("unescaped newline in Lua string")
                result.append(char)
            if len(result) > MAX_SOURCE_BYTES:
                raise ExportError("string is too large")
        raise ExportError("unterminated Lua string")

    def _value(self, depth: int = 0) -> Any:
        if depth > MAX_DEPTH:
            raise ExportError("SavedVariables nesting limit exceeded")
        self._skip()
        if self._take("{"):
            table: dict[Any, Any] = {}
            implicit_index = 1
            while True:
                self._skip()
                if self._take("}"):
                    return table
                if self._take("["):
                    key = self._value(depth + 1)
                    if type(key) not in (str, int, float) or isinstance(key, float) and not key.is_integer():
                        raise ExportError("unsupported Lua table key")
                    if isinstance(key, float):
                        key = int(key)
                    self._expect("]")
                    self._expect("=")
                    value = self._value(depth + 1)
                else:
                    start = self.position
                    word = self._identifier()
                    if word and self._take("="):
                        key = word
                        value = self._value(depth + 1)
                    else:
                        self.position = start
                        key = implicit_index
                        implicit_index += 1
                        value = self._value(depth + 1)
                self.fields += 1
                if self.fields > MAX_FIELDS:
                    raise ExportError("SavedVariables field limit exceeded")
                if key in table:
                    raise ExportError("duplicate Lua table key")
                table[key] = value
                self._skip()
                if self._take(",") or self._take(";"):
                    continue
                if not self.source.startswith("}", self.position):
                    raise ExportError(f"expected table separator at offset {self.position}")
        if self.source.startswith('"', self.position):
            return self._string()
        match = NUMBER.match(self.source, self.position)
        if match:
            self.position = match.end()
            literal = match.group()
            return float(literal) if any(c in literal for c in ".eE") else int(literal)
        word = self._identifier()
        if word == "true":
            return True
        if word == "false":
            return False
        if word == "nil":
            return None
        raise ExportError(f"unsupported Lua expression at offset {self.position}")

    def parse(self) -> dict[str, Any]:
        globals_found: dict[str, Any] = {}
        self._skip()
        while self.position < len(self.source):
            name = self._identifier()
            if name not in ALLOWED_GLOBALS or name in globals_found:
                raise ExportError(f"unexpected or duplicate SavedVariables global at offset {self.position}")
            self._expect("=")
            globals_found[name] = self._value()
            self._skip()
        if not isinstance(globals_found.get("GamersTrackerForeverDB"), dict):
            raise ExportError("GamersTrackerForeverDB is missing or not a table")
        return globals_found


def _table(value: Any, context: str) -> dict[Any, Any]:
    if not isinstance(value, dict):
        raise ExportError(f"{context} must be a table")
    return value


def _string(value: Any, context: str, *, optional: bool = False) -> str | None:
    if value is None and optional:
        return None
    if not isinstance(value, str) or len(value) > 4096:
        raise ExportError(f"{context} must be a string")
    return value


def _integer(value: Any, context: str, *, minimum: int = 0) -> int:
    if type(value) is not int or value < minimum:
        raise ExportError(f"{context} must be an integer >= {minimum}")
    return value


def _sequence(value: Any, context: str) -> list[Any]:
    table = _table(value, context)
    if set(table) != set(range(1, len(table) + 1)):
        raise ExportError(f"{context} must be a dense Lua sequence")
    return [table[index] for index in range(1, len(table) + 1)]


def _item_counts(value: Any, context: str) -> dict[str, int]:
    result: dict[str, int] = {}
    for item_id, count in _table(value, context).items():
        _integer(item_id, f"{context} item ID", minimum=1)
        _integer(count, f"{context} quantity")
        if count:
            result[str(item_id)] = count
    return dict(sorted(result.items(), key=lambda pair: int(pair[0])))


def _plain(value: Any, context: str, depth: int = 0) -> Any:
    if depth > 12:
        raise ExportError(f"{context} nesting limit exceeded")
    if value is None or type(value) in (bool, int, float, str):
        return value
    table = _table(value, context)
    if not table:
        return {}
    if all(type(key) is int for key in table) and set(table) == set(range(1, len(table) + 1)):
        return [_plain(table[index], context, depth + 1) for index in range(1, len(table) + 1)]
    if not all(type(key) in (str, int) for key in table):
        raise ExportError(f"{context} has an unsupported key")
    return {str(key): _plain(child, context, depth + 1) for key, child in table.items()}


def _recipe(value: Any, context: str) -> dict[str, Any]:
    source = _table(value, context)
    result = {
        "recipeID": _integer(source.get("recipeID"), context + ".recipeID", minimum=1),
        "professionID": _integer(source.get("professionID"), context + ".professionID"),
        "name": _string(source.get("name"), context + ".name"),
        "icon": source.get("icon", 0),
        "outputItemID": _integer(source.get("outputItemID", 0), context + ".outputItemID"),
        "outputMin": _integer(source.get("outputMin", 1), context + ".outputMin"),
        "outputMax": _integer(source.get("outputMax", 1), context + ".outputMax"),
        "categoryPath": [_string(name, context + ".categoryPath") for name in _sequence(source.get("categoryPath", {}), context + ".categoryPath")],
        "reagents": [],
    }
    if type(result["icon"]) not in (int, str):
        raise ExportError(context + ".icon has invalid type")
    for reagent in _sequence(source.get("reagents", {}), context + ".reagents"):
        row = _table(reagent, context + ".reagent")
        item_id = _integer(row.get("itemID"), context + ".reagent.itemID", minimum=1)
        quantity = _integer(row.get("quantity"), context + ".reagent.quantity", minimum=1)
        cleaned = {"itemID": item_id, "quantity": quantity, "kind": _string(row.get("kind", "item"), context + ".reagent.kind")}
        for field in ("name", "icon", "quality", "soulbound", "currency", "tool", "locationBound", "substitutable"):
            if field in row:
                cleaned[field] = _plain(row[field], context + ".reagent." + field)
        result["reagents"].append(cleaned)
    for field in ("categoryID", "categoryName", "specialRequirements", "unknownRequirements", "discoveredBuild"):
        if field in source:
            result[field] = _plain(source[field], context + "." + field)
    return result


def build_snapshots(root: dict[str, Any]) -> list[dict[str, Any]]:
    """Pure export seam: normalized per-character documents, no I/O or upload."""
    _integer(root.get("schemaVersion"), "schemaVersion", minimum=1)
    if root["schemaVersion"] != 1:
        raise ExportError("unsupported SavedVariables schema version")
    snapshots: list[dict[str, Any]] = []
    for product_key, raw_product in sorted(_table(root.get("products"), "products").items()):
        _string(product_key, "product key")
        product = _table(raw_product, "product")
        recipes = _table(product.get("recipes", {}), "product.recipes")
        for character_key, raw_character in sorted(_table(product.get("characters", {}), "product.characters").items()):
            _string(character_key, "character key")
            character = _table(raw_character, "character")
            identity = _table(character.get("identity"), "identity")
            guid = _string(identity.get("guid"), "identity.guid")
            if guid != character_key:
                raise ExportError("character GUID/key mismatch")
            client = _table(character.get("client", {}), "client")
            exported_professions: dict[str, Any] = {}
            for profession_key, raw_profession in sorted(_table(character.get("professions", {}), "professions").items()):
                _string(profession_key, "profession key")
                profession = _table(raw_profession, "profession")
                scanned_at = _integer(profession.get("recipesScannedAt", 0), "recipesScannedAt")
                learned = None
                definitions: dict[str, Any] = {}
                if scanned_at > 0:
                    learned_map = _table(profession.get("learnedRecipes"), "learnedRecipes")
                    learned = []
                    for recipe_key, is_known in sorted(learned_map.items()):
                        _string(recipe_key, "recipe key")
                        if is_known is not True:
                            raise ExportError("learnedRecipes contains a non-true entry")
                        if recipe_key not in recipes:
                            raise ExportError(f"missing definition for learned {recipe_key}")
                        learned.append(recipe_key)
                        definitions[recipe_key] = _recipe(recipes[recipe_key], "recipe " + recipe_key)
                exported_professions[profession_key] = {
                    "professionID": _integer(profession.get("professionID", 0), "professionID"),
                    "name": _string(profession.get("name", ""), "profession.name"),
                    "rank": _integer(profession.get("rank", 0), "profession.rank"),
                    "maxRank": _integer(profession.get("maxRank", 0), "profession.maxRank"),
                    "skillScannedAt": _integer(profession.get("skillScannedAt", 0), "skillScannedAt"),
                    "recipesScannedAt": scanned_at or None,
                    "scanState": _string(profession.get("scanState", "never"), "scanState"),
                    "learnedRecipes": learned,
                    "recipes": definitions,
                }
            inventory = _table(character.get("inventory", {}), "inventory")
            bags_at = _integer(inventory.get("bagsScannedAt", 0), "bagsScannedAt")
            bank_at = _integer(inventory.get("bankScannedAt", 0), "bankScannedAt")
            snapshots.append({
                "schemaVersion": 1,
                "product": product_key,
                "productDataVersion": _integer(product.get("dataVersion", 1), "productDataVersion", minimum=1),
                "characterKey": character_key,
                "character": {
                    "guid": guid,
                    "displayName": _string(identity.get("displayName", ""), "displayName"),
                    "realm": _string(identity.get("realm"), "realm", optional=True),
                    "region": _string(identity.get("region"), "region", optional=True),
                    "ruleset": _string(identity.get("ruleset"), "ruleset", optional=True),
                    "faction": _string(identity.get("faction", ""), "faction"),
                    "classID": _integer(identity.get("classID", 0), "classID"),
                    "level": _integer(character.get("level", 0), "level"),
                    "lastSeenAt": _integer(character.get("lastSeenAt", 0), "lastSeenAt"),
                },
                "client": {
                    "productID": _integer(client.get("productID", 0), "client.productID"),
                    "version": _string(client.get("version", ""), "client.version"),
                    "build": _string(client.get("build", ""), "client.build"),
                    "interface": _integer(client.get("interface", 0), "client.interface"),
                },
                "professions": exported_professions,
                "inventory": {
                    "bags": _item_counts(inventory.get("bags", {}), "bags") if bags_at else None,
                    "bagsScannedAt": bags_at or None,
                    "bank": _item_counts(inventory.get("bank", {}), "bank") if bank_at else None,
                    "bankScannedAt": bank_at or None,
                },
            })
    return snapshots


def read_saved_variables(path: Path) -> dict[str, Any]:
    before = path.stat()
    if before.st_size > MAX_SOURCE_BYTES:
        raise ExportError("SavedVariables file is too large")
    source = path.read_bytes()
    after = path.stat()
    if (before.st_size, before.st_mtime_ns) != (after.st_size, after.st_mtime_ns):
        raise ExportError("SavedVariables changed during read; retry after WoW finishes saving")
    if len(source) > MAX_SOURCE_BYTES:
        raise ExportError("SavedVariables file is too large")
    try:
        parsed = SavedVariablesParser(source.decode("utf-8-sig")).parse()
    except UnicodeDecodeError as exc:
        raise ExportError("SavedVariables is not valid UTF-8") from exc
    return parsed["GamersTrackerForeverDB"]


def export_once(source: Path, output_dir: Path) -> tuple[list[dict[str, Any]], int]:
    snapshots = build_snapshots(read_saved_variables(source))
    output_dir.mkdir(parents=True, exist_ok=True)
    changed = 0
    for snapshot in snapshots:
        digest = hashlib.sha256((snapshot["product"] + "\0" + snapshot["characterKey"]).encode()).hexdigest()[:24]
        target = output_dir / f"character-{digest}.json"
        content = (json.dumps(snapshot, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False) + "\n").encode("utf-8")
        if target.exists() and target.read_bytes() == content:
            continue
        temp_name = None
        try:
            with tempfile.NamedTemporaryFile(dir=output_dir, prefix=".sync-", suffix=".tmp", delete=False) as temp:
                temp_name = temp.name
                temp.write(content)
                temp.flush()
                os.fsync(temp.fileno())
            os.replace(temp_name, target)
            changed += 1
        finally:
            if temp_name and os.path.exists(temp_name):
                os.unlink(temp_name)
    return snapshots, changed


def upload_snapshots(snapshots: list[dict[str, Any]], server_url: str, token: str) -> int:
    """Idempotent whole-document uploads; the server decides its revision."""
    parsed = urlparse(server_url)
    if parsed.scheme not in ("http", "https") or not parsed.hostname or parsed.username or parsed.password:
        raise ExportError("invalid server URL")
    if parsed.scheme == "http" and parsed.hostname not in ("127.0.0.1", "localhost", "::1"):
        raise ExportError("unencrypted HTTP is allowed only for localhost")
    endpoint = server_url.rstrip("/") + "/v1/snapshots"
    for snapshot in snapshots:
        body = json.dumps(snapshot, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False).encode("utf-8")
        request = Request(endpoint, body, method="PUT", headers={
            "Authorization": "Bearer " + token,
            "Content-Type": "application/json; charset=utf-8",
        })
        with urlopen(request, timeout=10) as response:
            if response.status != 200:
                raise ExportError(f"server rejected snapshot with HTTP {response.status}")
    return len(snapshots)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--saved-variables", type=Path, required=True, help="exact GamersTrackerForever.lua file")
    parser.add_argument("--output-dir", type=Path, required=True, help="directory for per-character JSON")
    parser.add_argument("--watch-seconds", type=int, help="poll interval; 300 seconds is the suggested starting point")
    parser.add_argument("--server-url", help="optional server base URL; HTTP is allowed only on localhost")
    parser.add_argument("--token-file", type=Path, help="local bearer token file; required with --server-url")
    args = parser.parse_args()
    if args.watch_seconds is not None and args.watch_seconds < 5:
        parser.error("--watch-seconds must be at least 5")
    if bool(args.server_url) != bool(args.token_file):
        parser.error("--server-url and --token-file must be provided together")
    try:
        while True:
            snapshots, changed = export_once(args.saved_variables, args.output_dir)
            uploaded = 0
            if args.server_url:
                token = args.token_file.read_text(encoding="utf-8").strip()
                if not token:
                    raise ExportError("token file is empty")
                uploaded = upload_snapshots(snapshots, args.server_url, token)
            print(f"characters={len(snapshots)} changed={changed} checked_on_server={uploaded}", flush=True)
            if args.watch_seconds is None:
                return 0
            time.sleep(args.watch_seconds)
    except (ExportError, OSError) as exc:
        parser.exit(1, f"sync export: {exc}\n")
    except KeyboardInterrupt:
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
