# Local sync prototype

Status: implemented and tested locally, **not** yet an in-game remote import or an internet-facing deployment.

The addon still writes its account-wide SavedVariables normally. A separate Python companion reads only the configured `GamersTrackerForever.lua` file after WoW has persisted it, converts it to one JSON document per character, and uploads complete documents to a server. The server runs on `127.0.0.1:8765` and stores documents in one SQLite table keyed by owner/product/character. SQLite is embedded in Python; no separate database service or NoSQL product is required. Each changed document receives a monotonically increasing revision; repeated identical uploads keep the same revision. SQLite stores JSON as text and supports JSON functions if later needed; its WAL mode allows concurrent readers and a single writer on one host ([SQLite JSON documentation](https://www.sqlite.org/json1.html), [SQLite WAL documentation](https://www.sqlite.org/wal.html)).

The seam is `build_snapshots(root)` in [`tools/sync_export.py`](../tools/sync_export.py): it returns validated, minimal per-character documents without any file or network side effects. The companion transport and the SQLite server are separate implementations around that seam. Future HTTPS transport can reuse the documents without changing the addon scanners.

## Running locally

Use Python 3.11+ with its standard-library `sqlite3` module; no separate SQLite
server or database package is needed. Run the commands from the repository
root. Replace the SavedVariables path with the exact file for the WoW account
and client you want to sync. Keep the token, database, and exported JSON in a
private local directory, outside the addon installation and outside Git.

First, log out of WoW or use `/reload` so the client writes the latest addon
state to `GamersTrackerForever.lua`. The companion only reads the persisted
file; it cannot see unsaved in-memory changes or trigger a reload.

Open a PowerShell terminal for the server and run:

```powershell
$syncState = Join-Path $env:LOCALAPPDATA 'GamersTrackerForever\sync-local'
$savedFile = 'C:\Program Files (x86)\World of Warcraft\_classic_beta_\WTF\Account\YOUR_ACCOUNT\SavedVariables\GamersTrackerForever.lua'
python tools/sync_server.py --database (Join-Path $syncState 'snapshots.sqlite3') --token-file (Join-Path $syncState 'token')
```

The first run creates the state directory, SQLite database, and a random bearer
token file. Keep this terminal open; the server runs in the foreground and
listens only on `127.0.0.1:8765` by default. In a **second PowerShell
terminal**, from the repository root, define the same state and SavedVariables
paths (terminal variables are not shared), then start the companion. Adjust the
account and client folder as needed:

```powershell
$syncState = Join-Path $env:LOCALAPPDATA 'GamersTrackerForever\sync-local'
$savedFile = 'C:\Program Files (x86)\World of Warcraft\_classic_beta_\WTF\Account\YOUR_ACCOUNT\SavedVariables\GamersTrackerForever.lua'
python tools/sync_export.py --saved-variables $savedFile --output-dir (Join-Path $syncState 'exported') --server-url http://127.0.0.1:8765 --token-file (Join-Path $syncState 'token') --watch-seconds 300
```

Without `--watch-seconds`, the companion runs once. Without `--server-url` and
`--token-file`, it only writes JSON files. It never edits the game's SavedVariables.
With `--watch-seconds 300`, it polls every five minutes, but unchanged disk data
does not create a new server revision. If WoW is running, unsaved in-memory
changes may not be included yet. Stop either foreground process with Ctrl+C.

SQLite data lives in `snapshots.sqlite3` under the state directory; WAL mode may
also create `snapshots.sqlite3-wal` and `snapshots.sqlite3-shm` while the server
is running. The server creates a `character_snapshots` table with one current
document per owner, product, and character. To verify service-side data, use
`GET /v1/snapshots` with `Authorization: Bearer <token>` as described below;
the response includes the stored JSON document. Do not publish the token or
response.

The `GET /v1/snapshots` response contains `revision`, `contentHash`,
`receivedAt`, and `snapshot` for each character.

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
