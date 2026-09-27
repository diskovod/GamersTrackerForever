# Sync architecture research (2026-09-27)

## Recommendation

Use **one complete, versioned snapshot per character**, transported by an optional **local desktop companion**. The companion can poll for changed SavedVariables and exchange HTTPS snapshots with the server every five minutes. The addon should **not** reload the UI on a timer. A five-minute poll is a transport interval, **not** a promise that in-game data or other characters' data is five minutes fresh.

This is a design recommendation, not an implemented feature. The Forever beta has not been shown to expose an addon HTTP or arbitrary-file API. Standard WoW addon messaging is documented as sending payloads to *other game clients*, not to an arbitrary web server, so the companion is the conservative path unless Forever explicitly adds a supported bridge. This network conclusion is an inference from the [Blizzard-generated chat API documentation](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/ChatInfoDocumentation.lua) and should be re-probed on Forever before implementation. Blizzard's [addon development policy](https://eu.forums.blizzard.com/en/wow/t/wow-user-interface-add-on-development-policy/1642) also makes client and realm performance a consideration; avoid bulk addon-message transport as an unproven shortcut.

## What a five-minute schedule can and cannot do

| Operation | Feasible? | Meaning |
| --- | --- | --- |
| Re-scan current character's bags/level in addon memory | Yes, event-driven is better than blind polling | The existing scanner updates an in-memory account-wide repository when the client exposes complete data. [InventoryScanner.lua](../GamersTrackerForever/InventoryScanner.lua), [Repository.lua](../GamersTrackerForever/Repository.lua) |
| Upload local SavedVariables to server every five minutes | Only with a desktop companion, and only after a disk write | The addon declares account-wide SavedVariables in its [.toc](../GamersTrackerForever/GamersTrackerForever.toc); WoW writes that file at reload/logout/exit rather than for each Lua table mutation. See [SavedVariables discussion on Blizzard's forum](https://us.forums.blizzard.com/en/wow/t/saving-local-variables-between-sessions/380081). The companion may check every five minutes and upload only a newer *persisted* revision. |
| Fetch server changes every five minutes | Yes, in the companion | The companion can cache a validated response locally; an already-running addon cannot be assumed to read an arbitrary external file mid-session. |
| “Background reload” every five minutes | No, not in the requested sense | `ReloadUI()` is a full UI reload, not a hidden data refresh. Blizzard's own [slash command](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_ChatFrameBase/Shared/SlashCommands.lua) and [performance dialog](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_AddOnPerformance/AddOnPerformance.lua) invoke it explicitly. Timer-driven use would interrupt play and repeatedly reinitialize every addon. Offer a user-initiated “Refresh synced data” action/reload only if in-game viewing of remote updates is needed. |
| Fresh recipes/bank for every character every five minutes | No | An offline character cannot be rescanned. The present recipe scanner requires a complete readable profession view before replacing its learned set; the bank scanner preserves the last good bank snapshot if access is unavailable. [ForeverRecipeScanner.lua](../GamersTrackerForever/ForeverRecipeScanner.lua), [InventoryScanner.lua](../GamersTrackerForever/InventoryScanner.lua) |

Two useful product modes follow from this: **(A) local addon only**, with cross-character snapshots on the same WoW account, already present; **(B) optional server sync**, with companion upload after logout/reload and optional user-initiated import/reload for new remote data. A separate browser/web dashboard could show server-fresh data without any in-game reload.

## Transport boundary

1. Addon collects data using events and updates `GamersTrackerForeverDB` in memory. Its [.toc](../GamersTrackerForever/GamersTrackerForever.toc) already declares this account-wide SavedVariable.
2. On normal game logout/exit or an explicit `/reload`, WoW persists that table. The companion detects a stable, changed file, parses **data only** (never evaluates arbitrary Lua), validates it, and creates per-character JSON snapshots. Do not edit the live SavedVariables file while WoW runs; the client can overwrite those edits at its next save. [Blizzard forum SavedVariables lifecycle](https://us.forums.blizzard.com/en/wow/t/saving-local-variables-between-sessions/380081).
3. Companion uploads changed snapshots over authenticated HTTPS, with an idempotency key/content hash. The server atomically replaces each character document and gives it a server revision. Its GET endpoint returns the latest permitted documents.
4. For in-game remote viewing, the companion writes a **separate, generated inbox data file** and the user explicitly reloads the UI to load it; the addon validates and merges the inbox into a read-only remote cache. Never write executable server-supplied Lua or overwrite the game's SavedVariables. A generated Lua data file still has code-execution risk, so a strict serializer, size limits, atomic file replacement, and an import parser/validator are design gates. If those gates are not acceptable, keep remote viewing in the companion/web dashboard instead.

This is a proposal, not a claim that the Forever beta has been tested for inbox reloading. Prototype that path and verify it with a real beta client before committing to in-game server viewing.

## Minimal snapshot contract

The repository already separates product-wide recipe definitions from per-character learned sets, professions and inventories: see [Repository.lua](../GamersTrackerForever/Repository.lua). The profession and Forever recipe scanners require **complete** scans before replacing learned recipes; failed scans preserve previous data: [ProfessionScanner.lua](../GamersTrackerForever/ProfessionScanner.lua), [ForeverRecipeScanner.lua](../GamersTrackerForever/ForeverRecipeScanner.lua). The server need not normalize these into many relational tables. It can store one validated JSON document per character (a filesystem object or one JSON/blob column with indexed owner/product/character keys).

Suggested v1 envelope (illustrative; field names not yet a committed wire protocol):

```json
{
  "schemaVersion": 1,
  "product": "forever_beta",
  "clientBuild": "70009",
  "characterKey": "Player-0000-00000000",
  "character": {
    "guid": "Player-0000-00000000",
    "displayName": "Example Character",
    "realm": "Classic Beta PvP 2",
    "classID": 0,
    "faction": "Horde",
    "level": 20,
    "lastSeenAt": 0
  },
  "professions": {
    "profession:blacksmithing": {
      "name": "Blacksmithing",
      "rank": 53,
      "maxRank": 75,
      "skillScannedAt": 0,
      "recipesScannedAt": 0,
      "scanState": "current",
      "learnedRecipes": ["recipe:3320"],
      "recipes": {
        "recipe:3320": {
          "name": "Rough Grinding Stone",
          "categoryPath": ["Weapon Stones"],
          "outputItemID": 0,
          "reagents": [{"itemID": 0, "quantity": 1}]
        }
      }
    }
  },
  "inventory": {
    "bags": {"2840": 7},
    "bagsScannedAt": 0,
    "bank": {},
    "bankScannedAt": null,
    "bankStatus": "unsupported"
  }
}
```

The example IDs, timestamps and counts are **illustrative placeholders**, not measured values. Reuse the repository's actual normalized recipe fields (output quantity/range, icons, reagent IDs and quantities, category path, special requirements) when defining the real schema. A *character snapshot* should contain the recipe definitions needed to render that character's learned recipes, even if that duplicates definitions across characters. This buys simple atomic replacement; deduplication can come later. Category hierarchy can be derived from each recipe's `categoryPath`; a separate category database is unnecessary. The current [recipe normalization](../GamersTrackerForever/Repository.lua) already preserves that path.

Important semantics:

- Include source/product and schema version so Forever, Era and SoD IDs never collide.
- Use character GUID/key as identity, not display name: Forever permits two-part names. Bind that key to an authenticated sync account; do not trust a claimed name/GUID alone.
- Treat **verified empty** (`{}` after a complete scan), **unknown/not scanned** (`null` or explicit status), and **unsupported** as different states. An incomplete recipe/bank scan must preserve the previous valid section, not erase it. Include per-section `scannedAt`/status so last-known data is visibly stale.
- Server replacement is **per character**, never “all account characters” from one login. A missing character in an upload is not a deletion. Explicit tombstones would be required later if deletion is desired.
- Maintain server-assigned revision/ETag and idempotent uploads. For the first version, one designated writer per character is simplest; if two installations can update the same character, define conflict resolution before enabling both. Client wall-clock timestamps alone are not a safe ordering key.
- Do not transmit chat, player contacts, unrelated account data or full item-link strings by default. Minimize to IDs/counts/labels needed for this UI; obtain opt-in, allow disconnect/delete/export, protect tokens outside the SavedVariables, use TLS and limit request sizes. A local companion should read only the configured addon SavedVariables path, not scan the whole WoW folder.

## Suggested first implementation slice

Build a **one-way export** first: validated per-character snapshot builder + fixture tests for complete, empty, stale and unsupported scans; then a companion that parses a saved file and uploads a blob to a test server. Check that `/reload` persists a new bag snapshot, and that a five-minute companion poll does *not* claim new data when the SavedVariables file is unchanged. Only after that, prototype authenticated download/in-game import behind an explicit refresh action. This separates transport risk from the live addon scanner/UI work.
