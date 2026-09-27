# World of Warcraft Forever beta compatibility report

Updated: 2026-09-27
Scope: installed beta client, user-supplied `/gtf status` and `/gtf probe` output, and addon source.

## Executive result

The installed client is `wow_classic_beta`; its executable is now build `1.60.1.70009`. In-game probes reported interface `16001` and project `1` on this build. A separate `forever_beta` adapter saves character level, profession ranks, and bag snapshots when that interface/project shape is present. The addon declares interfaces `11509, 16001`. The native UI was seen in game; layout and interaction changes still need visual retesting.

The user's in-game probe found `C_Container` with 44/44 readable bag slots and 129 items, plus four readable profession entries. It found no legacy trade-skill line/count APIs and no accessible bank. The previous no-addon crash report predates this runtime probe; its graphics assertion is not evidence of an addon Lua failure.

The addon uses native WoW frames, not HTML. The beta screenshot showed the split window and `Track up to` selector. The new tree puts professions and captured recipes under the selected character; selecting a recipe opens material cards and a separate per-character holdings panel on the right. Beta recipe rows remain unavailable until recipe scanning passes the compatibility gate.

## Primary client evidence

| Fact | Evidence | Interpretation |
|---|---|---|
| Client flavor | `C:\Program Files (x86)\World of Warcraft\_classic_beta_\.flavor.info:1-2` contains `Product Flavor!STRING:0` and `wow_classic_beta`. | Product identity is explicitly beta. |
| Installed build manifest | `C:\Program Files (x86)\World of Warcraft\.build.info` has a `wow_classic_beta` row with version `1.60.1.70009`; the separate `wow_classic_era` row remains `1.15.9.69722`. | Beta and Era are distinct products/build lines in the installed client. |
| Executable metadata | `C:\Program Files (x86)\World of Warcraft\_classic_beta_\WowB.exe` reports FileVersion/ProductVersion `1.60.1.70009`. | The executable agrees with the current manifest. |
| Runtime build | `...\_classic_beta_\Logs\gx.log:1-4` reports `World of Warcraft Beta x86_64 1.60.1.69913`; `Sound.log:1-3` reports WoW `1.60.1 (69913)`. | Runtime is the beta x64 client. |
| Realm build | `...\Logs\Aurora.log:30` records realm `Classic Beta PvP 2` with version `1.60.1.69800`; the latest error report records `<Realm.Version> 1.60.1.69800` at `...\Errors\2026-09-19_21.33.28_Error_40624.txt:107-110`. | Realm/client patch numbers can differ by build; use the client `GetBuildInfo()` result for addon diagnostics and retain realm version separately. |
| In-game probe | User screenshots from September 20 show version `1.60.1`, build `69913`, interface `16001`, project `1`; `GetProfessions` returned four readable entries; `C_Container` returned 44/44 readable bag slots and 129 items; legacy trade-skill line/count APIs were absent. | These are the proven beta capabilities used by the partial adapter. |
| Existing crash class | `...\Errors\2026-09-19_21.33.28_Error_40624.txt:9-13,60-73` reports an engine `IndirectTextureArray.cpp` assertion, build 69913, beta config; `...\Logs\gx.log:38-52` reports GPU hung/device lost and recovery. | Current client crashes are unrelated to addon Lua. Keep them separate from addon release gating. |

## Addon-to-client compatibility comparison

### Product and interface identity — high risk / not release-ready

The TOC now declares `## Interface: 11509, 16001`, matching the proven Era and Forever interface values. Local TOC examples (Questie/Plater) confirm comma-separated interface values are accepted. The addon still gates runtime selection by `GetBuildInfo()` and project evidence; a matching TOC value alone never selects an adapter.

`ApiCompat.lua` now uses a fail-closed allowlist: verified `1.15.x` selects `classic_era`, while the proven Forever shape (`WOW_PROJECT_ID == 1`, version `1.60.x`, interface `16001`) selects the dedicated writable `forever_beta` adapter. Unknown builds remain read-only and never construct Classic scanners. Product detection still captures `version`, `build`, `interface`, `WOW_PROJECT_ID`, and a beta/era marker through the separate probe.

Recommended detection record:

```text
productKey = explicit project/product marker when available
version, build, date, interface = GetBuildInfo()
wowProjectID = WOW_PROJECT_ID
ruleset = explicit product key, never inferred only from missing project ID
```

The adapter allowlist distinguishes the `1.60.x` beta shape from `1.15.x` Classic Era; it requires beta project `1` and interface `16001`. Forever data is persisted under `products.forever_beta`, never `products.classic_era`. The current `70009` build will remain read-only if its in-game interface differs.

### Character identity and context — two-part name confirmed

The user confirmed the Forever beta character's full name is `Disko Lebowski`; the persisted record had split it into `displayName="Disko"` and `realm="Lebowski"`. The Forever-only adapter now treats the first two `UnitFullName` values as first/last name parts and reads realm from `GetRealmName`. The probe uses the same normalization. Classic Era keeps its existing name/realm interpretation. Character keys continue to use the GUID when present, so this display correction does not change the record key.

### Bags and bank — bag persistence confirmed; bank unavailable

The Forever adapter enables the proven `C_Container.GetContainerNumSlots/GetContainerItemInfo` bag branch and refuses bank scanning because the beta probe found bank access unavailable. A before/after `/gtf status` around `/reload` showed bag scan timestamps advancing; the beta SavedVariables file then contained the `forever_beta` character record and `inventory.bagsScannedAt`. This confirms bag persistence.

### Profession ranks enabled; recipes disabled

The probe found `GetProfessions`/`GetProfessionInfo` readable, while legacy skill-line and trade-skill recipe APIs are absent. The Forever adapter saves profession names and current/max ranks from those readable enumeration calls under `products.forever_beta`. On build 70009, the open-window probe found filtered and all-recipe ID lists, but `GetTradeSkillLineInfo` and `GetRecipesForSkillLine` failed. List presence does not establish that a list is the learned-recipe set.

The read-only compatibility probe now samples at most three numeric recipe IDs from those lists and calls available `GetRecipeInfo` and `GetRecipeSchematic(recipeID, false)` functions. It retains only aggregate calls/errors/table counts, learned-known/true/false counts, numeric output/quantity-range availability, and reagent-slot quantity/exact-item/ambiguous counts (up to 100 slots per sample). It discards IDs, names, links, and raw reagent values. This is diagnostic evidence only. Recipe scanning remains disabled, the Recipes tab stays hidden, and the beta scanner remains rank-only. Enabling persistence requires evidence that the learned boolean is available and correctly distinguishes known from unknown recipes, recipe/output identity can be read safely, reagent slots are complete, and the list used for reconciliation covers all learned recipes rather than only the current filter. Capture results for multiple professions and known learned/unlearned examples before making that decision.

### Events and UI templates — likely compatible, runtime required

The dispatcher creates a native `Frame`, registers the addon's event list, and installs an `OnEvent` script (`EventDispatcher.lua:35-55`). The UI uses native `CreateFrame`, `BackdropTemplate` with a fallback, `UIPanelButtonTemplate`, `InputBoxTemplate`, `UIPanelScrollFrameTemplate`, and `UIDropDownMenuTemplate` (`UI.lua:74-96,121-180`). There is no HTML widget or browser/HTML markup in the addon source; `rg` finds no HTML/browser usage under the addon directory. The beta client does contain a `UTILS\BlizzardBrowser.exe`, but no local evidence shows that WoW addon Lua can embed it. Treat “HTML UI inside the addon” as unsupported/unverified; use native frames for the in-game panel.

The UI creates a 250 px left pane with the `Track up to` selector, scrollable characters, expandable professions, and nested recipe choices. The larger right pane shows an overview until a recipe is selected, then material icons/counts above a distinct holdings panel. Saved bag items are no longer rendered as a raw item-ID list. Beta runtime visual verification is still needed for the changed layout.

## Where bag data is saved

The TOC declares account-level SavedVariables `GamersTrackerForeverDB AltCraftTrackerDB` (`GamersTrackerForever.toc:1-8`). On initialization, `Bootstrap.lua:108-116` passes `GamersTrackerForeverDB` into the repository. The repository recovers/migrates `AltCraftTrackerDB` if needed and then assigns the active table back to `GamersTrackerForeverDB` (`Repository.lua:558-616`). Bag and bank snapshots are stored under each character's `inventory.bags`, `inventory.bank`, and corresponding timestamps (`Repository.lua:899-930`); defaults are defined at `:128-134`.

Therefore the expected on-disk location, after a successful logout/reload, is the beta client's account-wide path `...\_classic_beta_\WTF\Account\<account>\SavedVariables\GamersTrackerForever.lua`. It does not use realm/character subdirectories because the TOC declares `SavedVariables`, not `SavedVariablesPerCharacter`. No such file existed in the inspected beta profile because the addon had not yet been installed/loaded. A future server can consume exported/serialized snapshots, but the current in-game SavedVariables table is the only persistence path; there is no network upload code in the inspected addon source.

## Explicit release-gate checklist

- [x] Install the addon into the beta client's `Interface\AddOns`; the user ran `/gtf status` and `/gtf probe` on build `69913`.
- [x] Confirm interface `16001` in-game on build `69913` and declare both TOC interfaces. Recheck the current `70009` build.
- [x] Capture `GetBuildInfo()` and project markers through `/gtf probe`; fail closed on unknown product/build shape.
- [x] Confirm the native two-pane window and `Track up to` dropdown instantiate in the beta client.
- [ ] Retest the expanded profession tree, resizing, scrolling, and tracking-limit persistence after the UI change.
- [x] Confirm `C_Container` on build `69913` with 44/44 readable slots and 129 counted items; compare those totals against live bags after deploying this build.
- [x] Confirm `/reload` bag persistence: the bag timestamp advanced and the Forever partition was written.
- [ ] Open and close a bank, verify `BANKFRAME_OPENED` and `BANKFRAME_CLOSED`, and ensure the bank snapshot is not overwritten with an empty inaccessible cache.
- [ ] After installing the bounded detail probe, open each profession and capture aggregate detail results; confirm learned true/false on known examples and reagent/output completeness before considering persistence.
- [ ] Logout normally, inspect the generated `GamersTrackerForever.lua`, reload, and verify the same bag/character data is restored.
- [ ] Repeat with an Era client/profile to ensure product keys keep beta and Era records separate.
- [ ] Re-test with the beta GPU crash conditions isolated; do not classify engine/GPU assertions as addon failures unless the addon is loaded and appears in the error report.

## Recommended next implementation decision

Keep the native two-pane UI and SavedVariables architecture. The partial beta adapter and product partition are in place; the remaining gates are in-client UI/persistence checks and a verified recipe/bank API path. A server can later consume an explicit export of `GamersTrackerForeverDB` through a companion uploader.
