# Local sync prototype

Status: implemented and tested locally, **not** yet an in-game remote import or an internet-facing deployment.

The addon still writes its account-wide SavedVariables normally. A separate Python companion reads only the configured `GamersTrackerForever.lua` file after WoW has persisted it, converts it to one JSON document per character, and uploads complete documents to a server. The server runs on `127.0.0.1:8765` and stores documents in one SQLite table keyed by owner/product/character. SQLite is embedded in Python; no separate database service or NoSQL product is required. Each changed document receives a monotonically increasing revision; repeated identical uploads keep the same revision. SQLite stores JSON as text and supports JSON functions if later needed; its WAL mode allows concurrent readers and a single writer on one host ([SQLite JSON documentation](https://www.sqlite.org/json1.html), [SQLite WAL documentation](https://www.sqlite.org/wal.html)).

The seam is `build_snapshots(root)` in [`tools/sync_export.py`](../tools/sync_export.py): it returns validated, minimal per-character documents without any file or network side effects. The companion transport and the SQLite server are separate implementations around that seam. Future HTTPS transport can reuse the documents without changing the addon scanners.

## Running locally

Use Python 3.11+ and run these from the repository root. Replace the SavedVariables path with the exact file for the WoW account you want to sync. Keep the token and database in a private local directory, outside the addon installation and outside Git.

```powershell
$syncState = Join-Path $env:LOCALAPPDATA 'GamersTrackerForever\sync-local'
$savedFile = 'C:\Program Files (x86)\World of Warcraft\_classic_beta_\WTF\Account\YOUR_ACCOUNT\SavedVariables\GamersTrackerForever.lua'
python tools/sync_server.py --database (Join-Path $syncState 'snapshots.sqlite3') --token-file (Join-Path $syncState 'token')
```

The server command creates a random secret token on first run and remains in the foreground. In another terminal:

```powershell
python tools/sync_export.py --saved-variables $savedFile --output-dir (Join-Path $syncState 'exported') --server-url http://127.0.0.1:8765 --token-file (Join-Path $syncState 'token') --watch-seconds 300
```

Without `--watch-seconds`, the companion runs once. Without `--server-url` and `--token-file`, it only writes JSON files. It never edits the game's SavedVariables. It polls at five-minute intervals, but unchanged disk data yields the same server revision. WoW normally flushes new addon data to the file on logout or `/reload`; the companion **does not** trigger a reload. If the game is running, in-memory changes may not be on the server yet.

To inspect stored documents from a local terminal, send `GET /v1/snapshots` with `Authorization: Bearer <token>`. Do not publish the token or the JSON response. A server response contains `revision`, `contentHash`, `receivedAt`, and `snapshot` for each character.

## Snapshot and storage contract

- `schemaVersion: 1`, `product`, `characterKey` (GUID), `character`, `client`, `professions`, and `inventory` are required.
- Each profession carries rank, scan state/timestamps, learned recipe keys, and the definitions needed to render those recipes, including category path, output and reagent IDs/counts. Unknown/not-scanned recipe sets use JSON `null`; a complete verified-empty set uses `[]`.
- Bags and bank use ID-to-quantity JSON objects. Unknown/not-scanned locations use `null`; a verified-empty location uses `{}`. The beta's unsupported bank therefore remains unknown, not zero.
- The server stores the full document as JSON text plus indexed owner/product/character keys, content hash, revision, and receipt time. No recipe/category relational tables are necessary for v1.
- One designated writer per character is assumed. Missing characters in an upload are not deletions. Conflict resolution, explicit deletion, per-user accounts, internet TLS, and in-game remote import are future work.
- Only configured addon SavedVariables are parsed, and the parser rejects executable Lua. Export omits UI settings and full item-link strings. The server requires a bearer token and binds to loopback only; it is intentionally **not** suitable for direct public exposure.

For internet access later, place an authenticated HTTPS endpoint in front of the server, introduce real account ownership, backups, rate and size limits, and a conflict policy before allowing multiple writers. SQLite is appropriate for this small single-host workload; if many concurrent writers or multiple server hosts become necessary, migrate the same JSON documents to PostgreSQL `jsonb`. See the [architecture research](sync-architecture-research.md).

## Verification

Run `python -m unittest tools.test_sync -v`. The tests cover restricted Lua parsing, executable-input rejection, complete versus unavailable snapshots, private-field exclusion, no rewrite for unchanged saves, token enforcement, idempotent upload, and revision increment. A real beta SavedVariables export has been checked against the current client shape. No server or companion is installed into the WoW addon directory.
