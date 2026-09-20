# World of Warcraft Forever beta compatibility report

Date: 2026-09-20  
Scope: read-only inspection of the installed client at `C:\Program Files (x86)\World of Warcraft\_classic_beta_` and the addon source under `GamersTrackerForever\GamersTrackerForever`.

## Executive result

The installed client is a real `wow_classic_beta` build, not the Classic Era build that the addon currently declares. The client reports version `1.60.1.69913` / build `69913`, branch `1.60.1`, while the addon TOC declares interface `11509` and product `Classic Era`. This is an **unreleased/test-only integration** until the addon has a beta-specific product/interface policy and has been loaded in this client.

The current client cannot explain the bag symptom or validate the new UI: `Interface\AddOns` is empty, the beta SavedVariables contain no addon database, and the client error report says `Addons.HasAny.Loaded: No` and `LuaErrors: 0`. The observed beta crashes are graphics/client assertions, not addon Lua failures.

The source already contains the requested native WoW split UI: a character list and tracking-limit dropdown on the left, and a larger detail/recipe pane on the right. It does not use HTML. Whether those native templates and APIs are present with the beta build remains a runtime gate.

## Primary client evidence

| Fact | Evidence | Interpretation |
|---|---|---|
| Client flavor | `C:\Program Files (x86)\World of Warcraft\_classic_beta_\.flavor.info:1-2` contains `Product Flavor!STRING:0` and `wow_classic_beta`. | Product identity is explicitly beta. |
| Installed build manifest | `C:\Program Files (x86)\World of Warcraft\.build.info:1-3` has a `wow_classic_beta` row with version `1.60.1.69913`; the same file has a separate `wow_classic_era` row at `1.15.9.69722`. | Beta and Era are distinct products/build lines in the installed client. |
| Executable metadata | `C:\Program Files (x86)\World of Warcraft\_classic_beta_\WowB.exe` reports FileVersion/ProductVersion `1.60.1.69913`, ProductName `World of Warcraft`, CompanyName `Blizzard Entertainment`. | The executable agrees with the manifest. |
| Runtime build | `...\_classic_beta_\Logs\gx.log:1-4` reports `World of Warcraft Beta x86_64 1.60.1.69913`; `Sound.log:1-3` reports WoW `1.60.1 (69913)`. | Runtime is the beta x64 client. |
| Realm build | `...\Logs\Aurora.log:30` records realm `Classic Beta PvP 2` with version `1.60.1.69800`; the latest error report records `<Realm.Version> 1.60.1.69800` at `...\Errors\2026-09-19_21.33.28_Error_40624.txt:107-110`. | Realm/client patch numbers can differ by build; use the client `GetBuildInfo()` result for addon diagnostics and retain realm version separately. |
| No addon runtime | `...\Errors\2026-09-19_21.33.28_Error_40624.txt:94-101` says `Addons.Current (null)`, `Addons.HasAny.Loading No`, `Addons.HasAny.Loaded No`, `LuaErrors 0`; `...\Interface\AddOns` has zero entries. | No conclusion about addon API behavior can be drawn from this session. |
| Existing crash class | `...\Errors\2026-09-19_21.33.28_Error_40624.txt:9-13,60-73` reports an engine `IndirectTextureArray.cpp` assertion, build 69913, beta config; `...\Logs\gx.log:38-52` reports GPU hung/device lost and recovery. | Current client crashes are unrelated to addon Lua. Keep them separate from addon release gating. |

## Addon-to-client compatibility comparison

### Product and interface identity — high risk / not release-ready

The TOC declares `## Interface: 11509` and `## X-Product: Classic Era` at `GamersTrackerForever\GamersTrackerForever.toc:1-8`. The beta client is `1.60.1.69913` and `wow_classic_beta` as shown above. The local evidence does not expose the beta's numeric TOC interface value, so it is not safe to invent one; the loader must be queried at runtime or the beta's own AddOn list must be observed.

`ApiCompat.lua` now uses a fail-closed allowlist: only the verified `1.15.x` client family may select the Classic adapter. A missing project marker is no longer enough, and a beta that reuses project ID `2` but reports `1.60.x` is routed to an explicit `unsupported:2` partition. Unsupported products use a read-only adapter and do not construct Classic scanners. Product detection still captures `version`, `build`, `interface`, `WOW_PROJECT_ID`, and a beta/era marker through the separate probe; no beta support is claimed.

Recommended detection record:

```text
productKey = explicit project/product marker when available
version, build, date, interface = GetBuildInfo()
wowProjectID = WOW_PROJECT_ID
ruleset = explicit product key, never inferred only from missing project ID
```

For this installed client, an allowlist should at minimum distinguish `wow_classic_beta` / `1.60.1.*` from `wow_classic_era` / `1.15.9.*`. Do not make the beta claim production-compatible merely because both branches are called Classic.

### Character identity and context — likely compatible, runtime required

The adapter uses `UnitFullName`/`UnitName`, `GetRealmName`, `UnitClass`, `UnitFactionGroup`, `UnitGUID`, and `UnitLevel` (`ApiCompat.lua:54-90,115-128`). These are basic character-context APIs, but the beta must be exercised to verify return shapes and realm/faction values. The source stores the client build/interface alongside each character (`Repository.lua:137-160`), which is useful for diagnosing mixed Era/beta records.

### Bags and bank — code has both API branches, runtime required

The inventory adapter supports either `C_Container.GetContainerNumSlots/GetContainerItemInfo` or legacy global `GetContainerNumSlots/GetContainerItemInfo` (`ApiCompatInventory.lua:90-140`). It derives bag IDs from `NUM_BAG_SLOTS` and bank IDs from `NUM_BANKBAGSLOTS` (`:35-64`) and deliberately refuses to infer bank accessibility from a stale cache (`:70-87`).

The scanner commits only a complete, readable bag result (`InventoryScanner.lua:117-149,159-185`) and commits bank data only while bank access is true (`:188-230`). It listens for `BAG_UPDATE_DELAYED`, `BAG_UPDATE`, `BANKFRAME_OPENED`, `PLAYERBANKSLOTS_CHANGED`, and `BANKFRAME_CLOSED` (`:273-289`; event list `Constants.lua:30-45`). This is a reasonable compatibility shape, but the beta test must verify:

1. Which container branch exists (`C_Container` versus legacy globals).
2. `GetContainerItemInfo` return shape and whether `itemID`, `stackCount`, and `hyperlink` are populated immediately.
3. Whether `BAG_UPDATE_DELAYED` fires after login and ordinary bag changes.
4. Whether bank container `-1` and bank bag IDs are readable before `BANKFRAME_CLOSED`.

### Professions and recipes — high risk / runtime required

Profession enumeration prefers `GetProfessions` + `GetProfessionInfo` and falls back to old skill-line APIs (`ApiCompatProfessions.lua:124-216`). Recipe scanning relies on the legacy trade-skill family: `GetTradeSkillLine`, `GetNumTradeSkills`, `GetTradeSkillInfo`, recipe/item links, and reagent APIs (`:221-357`). The client directory has `WTF\Account\...\SavedVariables\Blizzard_Professions.lua`, but that is Blizzard state, not proof that these globals exist or retain the Classic return signatures. The beta must be tested in an actual profession window; if the beta exposes only a newer `C_TradeSkillUI` surface, add a beta adapter before release.

### Events and UI templates — likely compatible, runtime required

The dispatcher creates a native `Frame`, registers the addon's event list, and installs an `OnEvent` script (`EventDispatcher.lua:35-55`). The UI uses native `CreateFrame`, `BackdropTemplate` with a fallback, `UIPanelButtonTemplate`, `InputBoxTemplate`, `UIPanelScrollFrameTemplate`, and `UIDropDownMenuTemplate` (`UI.lua:74-96,121-180`). There is no HTML widget or browser/HTML markup in the addon source; `rg` finds no HTML/browser usage under the addon directory. The beta client does contain a `UTILS\BlizzardBrowser.exe`, but no local evidence shows that WoW addon Lua can embed it. Treat “HTML UI inside the addon” as unsupported/unverified; use native frames for the in-game panel.

The requested split is already represented in source: `UI.lua:160-176` creates `leftPane` (210 px), `rightPane`, scrollable character content, and larger detail/recipe content. The left side labels the control `Track up to` and uses `UIDropDownMenuTemplate` at `:162-178`; rows show each character and tracked/available state at `:273-283`. This needs beta runtime visual verification, not a new HTML layer.

## Where bag data is saved

The TOC declares account-level SavedVariables `GamersTrackerForeverDB AltCraftTrackerDB` (`GamersTrackerForever.toc:1-8`). On initialization, `Bootstrap.lua:108-116` passes `GamersTrackerForeverDB` into the repository. The repository recovers/migrates `AltCraftTrackerDB` if needed and then assigns the active table back to `GamersTrackerForeverDB` (`Repository.lua:558-616`). Bag and bank snapshots are stored under each character's `inventory.bags`, `inventory.bank`, and corresponding timestamps (`Repository.lua:899-930`); defaults are defined at `:128-134`.

Therefore the expected on-disk location, after a successful logout/reload, is the beta client's account/realm/character SavedVariables path under `...\_classic_beta_\WTF\Account\<account>\<realm>\SavedVariables\GamersTrackerForever.lua` (exact realm/account path depends on the logged-in account). No such file exists in the inspected beta profile because the addon is not installed/loaded. A future server can consume exported/serialized snapshots, but the current in-game SavedVariables table is the only persistence path; there is no network upload code in the inspected addon source.

## Explicit release-gate checklist

- [ ] Install the addon into the beta client's `Interface\AddOns` in a test copy and confirm it appears in the AddOns list. Do not infer this from the current no-addon error reports.
- [ ] Confirm the beta TOC interface value at runtime; update packaging/TOC policy so `1.60.1.*` is not silently treated as `1.15.9.*`.
- [ ] Log `GetBuildInfo()` and project/product markers at `ADDON_LOADED`/`PLAYER_LOGIN`; fail closed on unknown product/build.
- [ ] Confirm `CreateFrame`, `BackdropTemplate`, `UIPanelScrollFrameTemplate`, and `UIDropDownMenuTemplate` instantiate without errors.
- [ ] Confirm the two-pane UI is visible, resizable, scrollable, and the tracking-limit dropdown persists a value of 1–3 (or the chosen maximum).
- [ ] Confirm `C_Container` versus legacy bag APIs and validate bag totals against the live bags.
- [ ] Confirm `BAG_UPDATE_DELAYED`/`BAG_UPDATE` and login retry behavior; verify a successful `bagsScannedAt` is written.
- [ ] Open and close a bank, verify `BANKFRAME_OPENED` and `BANKFRAME_CLOSED`, and ensure the bank snapshot is not overwritten with an empty inaccessible cache.
- [ ] Open each supported profession, verify enumeration and recipe/reagent links, and capture any Lua error/API return-shape mismatch.
- [ ] Logout normally, inspect the generated `GamersTrackerForever.lua`, reload, and verify the same bag/character data is restored.
- [ ] Repeat with an Era client/profile to ensure product keys keep beta and Era records separate.
- [ ] Re-test with the beta GPU crash conditions isolated; do not classify engine/GPU assertions as addon failures unless the addon is loaded and appears in the error report.

## Recommended next implementation decision

Keep the native two-pane UI and SavedVariables architecture. The fail-closed detector is now in place; the remaining beta gate is a beta-specific adapter plus the in-client API/UI test. Do not add HTML as a dependency for this panel. A server can be added later as an explicit export/sync layer over normalized `GamersTrackerForeverDB`, not as a replacement for the local SavedVariables write path.
