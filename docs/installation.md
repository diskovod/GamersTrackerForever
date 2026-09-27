# GamersTrackerForever 0.3.0-beta.14 — Classic Era / Forever beta installation

## Install

1. Close World of Warcraft.
2. Extract `GamersTrackerForever-0.3.0-beta.14.zip` into the desired client so
   it creates exactly one of these folders:
   - `C:\Program Files (x86)\World of Warcraft\_classic_era_\Interface\AddOns\GamersTrackerForever\`
   - `C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns\GamersTrackerForever\`
3. Start the client and enable **GamersTrackerForever** on the character-selection AddOns list. The package declares interfaces **11509** and **16001**.

## Use

- `/gtf` opens or toggles the tracker window (`/act` is a compatibility alias).
- `/gtf status` prints adapter, client/build/interface, current key, scan times, database counts, and diagnostics.
- `/gtf probe` prints a read-only compatibility report. It does not scan bank contents or enable an unsupported client.
- `/gtf recipecheck` inspects up to 200 IDs from `GetAllRecipeIDs` while a profession is open and prints at most two learned and two unlearned examples. When the list is larger, its learned count is only a partial sample, not the open profession's total. It is read-only and does not save recipes.
- `/gtf recipecount` is an opt-in, read-only diagnostic that inspects up to 10,000 recipe IDs and reports learned counts by profession ID, duplicate/invalid entries, and schematic material shapes. It labels a capped or incomplete scan as partial; it still does not save recipes. On the tested beta build, the returned list changes with the open profession.
- `/gtf scan` manually captures the currently open profession's learned recipes on the supported Forever beta client. Opening or updating a profession also starts an automatic capture after the window settles. A failed or incomplete scan preserves the prior snapshot.
- `/gtf minimap on|off|toggle` controls the optional minimap button (enabled by default); the same subcommands work through `/act`.
- The key binding is **Toggle GamersTrackerForever**.
- Use `/reload` after changing the addon files. The addon never forces a reload.
- Every character that logs in with the addon is included automatically; there
  is no tracking limit or separate Characters tab. The left pane has a search
  field and a Character → Profession → Category → Recipe tree styled like the
  native profession list, with framed category bars and white recipe names.
  Expand a character and profession to browse captured recipes, then select a recipe to
  see material icons and quantities on the right. Categories appear when the
  client exposes them; otherwise recipes are grouped as Uncategorized. The
  All Recipes button opens the cross-character recipe view. A separate panel
  below shows each character's last-known bag/bank holdings.
  Hover a recipe row, crafted item icon, or material card for the native item
  tooltip. An equipped-item comparison appears when the client provides it.
  A small class icon identifies each character. A red X marks equipment the
  currently logged-in character cannot wear when the item type is known;
  unknown or uncached items are not marked. Forget is available on a selected
  character, but logging that character in again will add it back.

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
- The SoD static regression check passes. Complete
  in-client validation still requires the checklist in
  `tests\classic-era-acceptance-checklist.md`.
- On Forever beta build 70009, live Blacksmithing, Cooking, and First Aid scans
  saved 22, 4, and 3 learned recipes respectively. The saved per-character
  learned sets survived `/reload`, and recipe search and material details worked
  in the native UI. An empty transient `GetProfessions()` response no longer
  erases saved profession data. Mining's recipe list currently reports mixed
  profession ownership, so the scanner preserves existing data instead of
  claiming a complete scan. Bank scanning and transfer-group calculations
  remain unavailable on this beta client. Classic Era still needs in-client
  recipe regression testing.
- Beta.13 loaded after `/reload` without a visible Lua error. The two-pane
  window, class icon, expandable profession tree, saved recipes, material
  detail, and nearby native tooltip were observed in the running client.
  Existing recipes appeared under Uncategorized because their saved snapshots
  predate category capture; category assignment after a fresh profession scan,
  left-search behavior, and the red-X hint still need live acceptance checks.
- Beta.14 changes the left-pane presentation only. Its automated UI and SoD
  checks pass; the updated styling still needs a visual check after `/reload`.
