"""Run with: python -m unittest tools/test_sync.py"""

from __future__ import annotations

import copy
import json
from pathlib import Path
import tempfile
import threading
import unittest
from urllib.error import HTTPError
from urllib.request import Request, urlopen

from tools.sync_export import ExportError, SavedVariablesParser, build_snapshots, export_once, upload_snapshots
from tools.sync_server import create_server, list_snapshots, save_snapshot, validate_document


TOKEN = "test-token-" + "x" * 48


def fixture() -> dict:
    return {
        "schemaVersion": 1,
        "settings": {"selectedCharacterKey": "private-preference"},
        "products": {"forever_beta": {
            "dataVersion": 1,
            "recipes": {"recipe:3320": {
                "recipeID": 3320, "professionID": 2938, "name": "Rough Grinding Stone",
                "icon": 123, "outputItemID": 2840, "outputMin": 1, "outputMax": 1,
                "categoryPath": {1: "Weapon Stones"},
                "reagents": {1: {"itemID": 2770, "quantity": 2, "kind": "item", "link": "do-not-upload"}},
                "specialRequirements": {},
            }},
            "characters": {"Player-0-TEST": {
                "identity": {"guid": "Player-0-TEST", "displayName": "Example Character", "realm": "Beta",
                             "faction": "Horde", "classID": 2},
                "client": {"productID": 1, "version": "1.60.1", "build": "70009", "interface": 16001},
                "level": 20, "lastSeenAt": 1234,
                "professions": {"profession:blacksmithing": {
                    "professionID": 2938, "name": "Blacksmithing", "rank": 53, "maxRank": 75,
                    "skillScannedAt": 1234, "recipesScannedAt": 1233,
                    "scanState": "current", "learnedRecipes": {"recipe:3320": True},
                }},
                "inventory": {"bags": {2770: 7}, "bagsScannedAt": 1234,
                              "bank": {}, "bankScannedAt": 0},
            }},
        }},
    }


class ParserTests(unittest.TestCase):
    def test_literal_saved_variables_only(self) -> None:
        source = '''GamersTrackerForeverDB = {
          ["schemaVersion"] = 1,
          ["products"] = { ["forever_beta"] = { ["reagents"] = {
            { ["itemID"] = 2770, ["name"] = "Rough \\"Stone\\"" },
          } } },
        }
        AltCraftTrackerDB = nil'''
        parsed = SavedVariablesParser(source).parse()
        self.assertEqual(parsed["GamersTrackerForeverDB"]["products"]["forever_beta"]["reagents"][1]["itemID"], 2770)

    def test_rejects_code_and_duplicate_keys(self) -> None:
        for source in (
            'GamersTrackerForeverDB = os.execute("bad")',
            'GamersTrackerForeverDB = { ["a"] = 1, ["a"] = 2 }',
            'OtherGlobal = {}',
        ):
            with self.subTest(source=source), self.assertRaises(ExportError):
                SavedVariablesParser(source).parse()


class SnapshotTests(unittest.TestCase):
    def test_complete_and_private_data_minimized(self) -> None:
        snapshot = build_snapshots(fixture())[0]
        self.assertEqual(snapshot["character"]["displayName"], "Example Character")
        self.assertEqual(snapshot["professions"]["profession:blacksmithing"]["learnedRecipes"], ["recipe:3320"])
        self.assertEqual(snapshot["inventory"]["bags"], {"2770": 7})
        self.assertIsNone(snapshot["inventory"]["bank"])
        encoded = json.dumps(snapshot)
        self.assertNotIn("do-not-upload", encoded)
        self.assertNotIn("private-preference", encoded)

    def test_verified_empty_differs_from_unavailable(self) -> None:
        root = fixture()
        character = root["products"]["forever_beta"]["characters"]["Player-0-TEST"]
        profession = character["professions"]["profession:blacksmithing"]
        profession["recipesScannedAt"] = 0
        character["inventory"]["bagsScannedAt"] = 0
        unknown = build_snapshots(root)[0]
        self.assertIsNone(unknown["professions"]["profession:blacksmithing"]["learnedRecipes"])
        self.assertIsNone(unknown["inventory"]["bags"])
        profession["recipesScannedAt"] = 1234
        profession["learnedRecipes"] = {}
        character["inventory"]["bagsScannedAt"] = 1234
        character["inventory"]["bags"] = {}
        empty = build_snapshots(root)[0]
        self.assertEqual(empty["professions"]["profession:blacksmithing"]["learnedRecipes"], [])
        self.assertEqual(empty["inventory"]["bags"], {})

    def test_missing_definition_fails_without_partial_export(self) -> None:
        root = fixture()
        root["products"]["forever_beta"]["recipes"] = {}
        with self.assertRaisesRegex(ExportError, "missing definition"):
            build_snapshots(root)

    def test_unchanged_disk_snapshot_is_not_rewritten(self) -> None:
        source_text = '''GamersTrackerForeverDB = { ["schemaVersion"] = 1,
          ["products"] = { ["forever_beta"] = { ["dataVersion"] = 1,
          ["characters"] = { ["Player-0-TEST"] = {
            ["identity"] = { ["guid"] = "Player-0-TEST" },
          } } } } }
        AltCraftTrackerDB = nil'''
        with tempfile.TemporaryDirectory() as temp:
            source = Path(temp) / "GamersTrackerForever.lua"
            output = Path(temp) / "out"
            source.write_text(source_text, encoding="utf-8")
            first, first_changes = export_once(source, output)
            second, second_changes = export_once(source, output)
            self.assertEqual((len(first), first_changes), (1, 1))
            self.assertEqual((len(second), second_changes), (1, 0))


class ServerTests(unittest.TestCase):
    def test_revision_is_idempotent_and_isolated_by_character(self) -> None:
        first = build_snapshots(fixture())[0]
        with tempfile.TemporaryDirectory() as temp:
            db = Path(temp) / "sync.sqlite3"
            server = create_server(db, TOKEN, 0)
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            try:
                endpoint = f"http://127.0.0.1:{server.server_port}"
                self.assertEqual(upload_snapshots([first], endpoint, TOKEN), 1)
                self.assertEqual(upload_snapshots([first], endpoint, TOKEN), 1)
                rows = list_snapshots(db, "local")
                self.assertEqual(rows[0]["revision"], 1)
                self.assertEqual(rows[0]["snapshot"]["characterKey"], "Player-0-TEST")
                changed = copy.deepcopy(first)
                changed["character"]["level"] = 21
                upload_snapshots([changed], endpoint, TOKEN)
                self.assertEqual(list_snapshots(db, "local")[0]["revision"], 2)
                with self.assertRaises(HTTPError) as unauthorized:
                    urlopen(Request(endpoint + "/v1/snapshots"), timeout=2)
                self.assertEqual(unauthorized.exception.code, 401)
            finally:
                server.shutdown()
                server.server_close()
                thread.join(timeout=2)

    def test_rejects_invalid_document(self) -> None:
        snapshot = build_snapshots(fixture())[0]
        snapshot["character"]["guid"] = "different"
        with self.assertRaises(ValueError):
            validate_document(json.dumps(snapshot).encode())
        with self.assertRaises(ValueError):
            validate_document(b'{"a":1,"a":2}')


if __name__ == "__main__":
    unittest.main()
