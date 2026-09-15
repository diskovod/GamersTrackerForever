# AltCraft Tracker 0.1.0 — Classic Era installation

## Install

1. Close World of Warcraft.
2. Extract `AltCraftTracker-0.1.0-classic.zip` so it creates exactly:
   `C:\Program Files (x86)\World of Warcraft\_classic_era_\Interface\AddOns\AltCraftTracker\`
3. Start the Classic Era client and enable **AltCraft Tracker** on the character-selection AddOns list. The package targets interface **11509**.

## Use

- `/act` opens or toggles the tracker window.
- `/act status` prints adapter, client/build/interface, current key, scan times, database counts, and diagnostics.
- `/act minimap on|off|toggle` controls the optional minimap button (enabled by default).
- The key binding is **Toggle AltCraft Tracker**.
- Use `/reload` after changing the addon files. The addon never forces a reload.

## Data and freshness

Saved data is account-wide in `AltCraftTrackerDB`. Other characters are last-known snapshots; the addon cannot inspect an offline character. Bags scan at login, after debounced bag events, every ten minutes, and during logout. Bank data scans only while the bank is accessible and remains last-known after closing the bank. Learned recipes are captured when a profession window is open and has settled.

Material totals distinguish bags from bank, compatible transfer ecosystems from isolated characters, and fresh/stale/unknown snapshots. A missing or inaccessible location is not treated as zero, and special/tool/cooldown requirements are not claimed craftable.

## Validation status

- Local Classic Era installation metadata was inspected read-only. The installed client exposes interface **11509** in its Vanilla addon TOCs.
- No `lua`, `luajit`, or `luac` executable was available locally, so the fixture harnesses could not be runtime-executed. Static review covered all Lua files, TOC/XML load order, API guards, future-schema read-only handling, and ZIP contents. Complete in-client validation requires the checklist in `tests\classic-era-acceptance-checklist.md`.
- The release is Classic Era only. **Task 8 remains beta-client-gated**; no Forever support is claimed.
