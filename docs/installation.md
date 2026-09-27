# GamersTrackerForever 0.3.0 — Classic Era / SoD / WoW Forever installation

## Install

1. Close World of Warcraft.
2. Copy the `GamersTrackerForever` folder so it creates exactly one of:
   - Classic Era: `C:\Program Files (x86)\World of Warcraft\_classic_era_\Interface\AddOns\GamersTrackerForever\`
   - WoW Forever beta: `C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns\GamersTrackerForever\`
3. Start the client and enable **GamersTrackerForever** on the character-selection AddOns list. The TOC lists interfaces **11509** (Classic Era) and **16001** (Forever, inferred from `1.60.1`). If Forever lists the addon as out of date, tick **Load out of date AddOns** and report the interface shown by `/gtf status`.

## Use

- `/gtf` opens or toggles the tracker window (`/act` is a compatibility alias).
- `/gtf status` prints adapter, client/build/interface, current key, scan times, database counts, and diagnostics.
- `/gtf probe` prints a read-only compatibility report. It does not scan bank contents or enable an unsupported client.
- `/gtf minimap on|off|toggle` controls the optional minimap button (enabled by default); the same subcommands work through `/act`.
- The key binding is **Toggle GamersTrackerForever**.
- Use `/reload` after changing the addon files. The addon never forces a reload.
- The native window keeps all discovered characters in a left selector and the
  selected character overview/recipes in a larger right pane. Use `Track up to`
  to choose 1–10 tracked characters (default 3); a full limit reports a status
  message and does not untrack anyone automatically.

## Data and freshness

Saved data is account-wide in `GamersTrackerForeverDB`, written by WoW to
`WTF\Account\<account>\SavedVariables\GamersTrackerForever.lua` on `/reload`,
logout, or a clean exit. If an existing installation has data in the legacy
`AltCraftTrackerDB`, the first load copies it into `GamersTrackerForeverDB`
without changing the schema. Other characters are last-known snapshots; the
addon cannot inspect an offline character. Bags scan at login, after debounced
bag events, every ten minutes, and during logout. Bank data scans only while
the bank is accessible and remains last-known after closing the bank. Learned
recipes are captured when a profession window is open and has settled.

Bag and bank item totals are shown in the selected-character overview as item
names/IDs and counts. Snapshots remain local SavedVariables; WoW addons cannot
make arbitrary HTTP requests or write arbitrary files. A future server needs an
explicit export after WoW flushes SavedVariables plus a companion desktop
uploader (or another approved bridge).

Material totals distinguish bags from bank, compatible transfer ecosystems from isolated characters, and fresh/stale/unknown snapshots. A missing or inaccessible location is not treated as zero, and special/tool/cooldown requirements are not claimed craftable.

## Validation status

- Local Classic Era installation metadata was inspected read-only. The installed client exposes interface **11509** in its Vanilla addon TOCs.
- All eight fixture harnesses and the SoD static regression check pass. Complete
  in-client validation still requires the checklist in
  `tests\classic-era-acceptance-checklist.md`.
- WoW Forever (`1.60.x` builds, e.g. beta `1.60.1.69913`) selects the Forever
  adapter: it reuses the Classic profession/container APIs, stores data in a
  separate `forever` product partition, drops realm from identity, and pools
  materials only within the same region, ruleset (normal vs Hardcore), and
  faction. It still needs the in-client release gate in
  `docs/forever-beta-compatibility.md`; run `/gtf probe` if a profession or
  bag scan reports unsupported. Any other unknown client family fails closed.
- Enchanting (Classic `Craft` window) is scanned alongside trade skills.
