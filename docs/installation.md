# GamersTrackerForever 0.3.0-beta.3 — Classic Era / Forever beta installation

## Install

1. Close World of Warcraft.
2. Extract `GamersTrackerForever-0.3.0-beta.3.zip` into the desired client so
   it creates exactly one of these folders:
   - `C:\Program Files (x86)\World of Warcraft\_classic_era_\Interface\AddOns\GamersTrackerForever\`
   - `C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns\GamersTrackerForever\`
3. Start the client and enable **GamersTrackerForever** on the character-selection AddOns list. The package declares interfaces **11509** and **16001**.

## Use

- `/gtf` opens or toggles the tracker window (`/act` is a compatibility alias).
- `/gtf status` prints adapter, client/build/interface, current key, scan times, database counts, and diagnostics.
- `/gtf probe` prints a read-only compatibility report. It does not scan bank contents or enable an unsupported client.
- `/gtf minimap on|off|toggle` controls the optional minimap button (enabled by default); the same subcommands work through `/act`.
- The key binding is **Toggle GamersTrackerForever**.
- Use `/reload` after changing the addon files. The addon never forces a reload.
- The native window lists characters on the left. Select one to reveal its
  professions and ranks, expand a profession to browse captured recipes, then
  select a recipe to see material icons and quantities on the right. A separate
  panel below shows each tracked character's last-known bag/bank holdings.
  Use `Track up to` to choose 1–10 tracked characters (default 3); a full limit
  does not untrack anyone automatically.

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

Bag and bank item totals are kept for recipe material comparisons, not shown
as a raw inventory dump in the character overview. Snapshots remain local
SavedVariables; WoW addons cannot
make arbitrary HTTP requests or write arbitrary files. A future server needs an
explicit export after WoW flushes SavedVariables plus a companion desktop
uploader (or another approved bridge).

Material totals distinguish bags from bank, compatible transfer ecosystems from isolated characters, and fresh/stale/unknown snapshots. A missing or inaccessible location is not treated as zero, and special/tool/cooldown requirements are not claimed craftable.

## Validation status

- Local Classic Era installation metadata was inspected read-only. The installed client exposes interface **11509** in its Vanilla addon TOCs.
- All eight fixture harnesses and the SoD static regression check pass. Complete
  in-client validation still requires the checklist in
  `tests\classic-era-acceptance-checklist.md`.
- The Forever beta adapter is limited to character level, profession names and
  ranks, bag snapshots, native UI, and `/gtf probe`. Beta recipes, bank scans,
  and cross-character transfer calculations remain disabled. Test `/gtf probe`
  once with professions closed and again with a profession open; see
  `docs\forever-beta-probe.md` for the expected diagnostic lines.
