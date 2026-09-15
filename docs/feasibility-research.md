# WoW character, profession, recipe, and materials tracker — feasibility research

Research date: 2026-09-15 (Europe/Warsaw)

## Executive conclusion

The proposed addon is feasible as a local, account-level tracker. It can snapshot the logged-in character's level, active and completed quests, professions and skill ranks, known recipes, and item counts. A selected recipe can then be compared against the last stored inventory of every explicitly tracked character.

There are four important boundaries:

1. A WoW addon cannot inspect an offline character. Every character must log in with the addon enabled, and some information must be exposed once per character before it can be cached.
2. The native persistence mechanism is a Lua `SavedVariables` table written by the WoW client. The addon sandbox cannot create arbitrary JSON files, open SQLite, or call Wowhead over HTTP. [`SavedVariables` files are plain Lua and can be account-wide or per-character](https://warcraft.wiki.gg/wiki/SavedVariables); the sandbox has no live website/file I/O path other than WoW-managed SavedVariables ([WoW UI FAQ](https://warcraft.wiki.gg/wiki/UI_FAQ/AddOns)).
3. Character bags are available while playing, but bank/reagent-bank contents must be refreshed while the corresponding bank is open. The UI emits [`BANKFRAME_OPENED`](https://warcraft.wiki.gg/wiki/BANKFRAME_OPENED); the mature BagSync addon likewise refuses its bank/reagent scans unless it is at the bank and retains the last snapshot afterward ([BagSync scanner](https://raw.githubusercontent.com/Xruptor/BagSync/master/wireframe/scanner.lua)).
4. Blizzard has not yet published World of Warcraft: Forever's addon API flavor, interface number, or `WOW_PROJECT_ID`. Forever must be treated as an unverified client until the beta opens on Thursday, September 17. Blizzard explicitly describes it as a separate permanent WoW experience, not a new Classic version ([announcement](https://news.blizzard.com/en-us/article/24302093/carve-a-new-path-with-world-of-warcraft-forever), [What's Next recap](https://worldofwarcraft.blizzard.com/en-us/news/24303862/world-of-warcraft-forever-whats-next-panel-recap)).

Recommendation: build the data model and UI as client-neutral modules, with a thin API adapter selected by runtime capability tests. Prototype against current Classic Era, then freeze the Forever adapter only after inspecting the beta client.

## Capability matrix

| Requested information | Classic feasibility | Conditions and limitations |
|---|---:|---|
| Character identity, level, class | Yes | For the logged-in character only. `UnitLevel("player")` and `UnitGUID("player")` are available in Classic Era and progression clients ([UnitLevel](https://warcraft.wiki.gg/wiki/API_UnitLevel), [UnitGUID](https://warcraft.wiki.gg/wiki/API%3AUnitGUID)). |
| Explicit list of tracked characters | Yes | Store `tracked = true/false` inside one account-wide SavedVariables table. An unvisited/offline character has no discoverable live state. |
| Active quests and objective progress | Yes | Enumerate the current quest log and store quest ID, title, level/status, and objectives. Classic exposes `GetNumQuestLogEntries`, `GetQuestLogTitle`, and `C_QuestLog.GetQuestObjectives` ([entry count](https://warcraft.wiki.gg/wiki/API_GetNumQuestLogEntries), [quest row](https://warcraft.wiki.gg/wiki/API_GetQuestLogTitle), [objectives](https://warcraft.wiki.gg/wiki/API_C_QuestLog.GetQuestObjectives)). |
| Completed quests | Yes | `GetQuestsCompleted()` returns a table keyed by completed quest IDs on Classic ([API](https://warcraft.wiki.gg/wiki/API_GetQuestsCompleted)). This is character history, with documented caveats for daily/invisible/alternate quests. |
| Automatic named questline/chain | Partial | Retail's `C_QuestLine` family is mainline-only ([API](https://warcraft.wiki.gg/wiki/API_C_QuestLine.GetQuestLineInfo)). Classic gives quest IDs and completion state, not a canonical chain label/order. A curated embedded quest-chain database is required for automatic grouping; otherwise let the user pin an active quest or enter a short manual goal. |
| Profession names and skill ranks | Yes | Newer Classic builds expose `GetProfessions`/`GetProfessionInfo`; older/variant clients can fall back to skill-line APIs. [`GetProfessionInfo`](https://warcraft.wiki.gg/wiki/API%3AGetProfessionInfo) returns current and maximum skill values. Capability-test rather than assuming a specific patch. |
| Known recipes | Yes, after exposure | Classic's legacy trade-skill API lists recipes for the currently loaded profession. The Blizzard Vanilla trade-skill UI uses `GetNumTradeSkills`, `GetTradeSkillInfo`, `GetTradeSkillLine`, and reagent calls ([mirrored client UI source](https://raw.githubusercontent.com/Gethe/wow-ui-source/classic_era/Interface/AddOns/Blizzard_TradeSkillUI/Vanilla/Blizzard_TradeSkillUI.lua)). In practice the player must open each profession once; events can then trigger a scan. |
| Recipe output and required materials | Yes, after exposure | Legacy Classic provides `GetTradeSkillItemLink`, `GetTradeSkillNumReagents`, `GetTradeSkillReagentInfo`, and `GetTradeSkillReagentItemLink` ([output link](https://warcraft.wiki.gg/wiki/API_GetTradeSkillItemLink), [reagent info](https://warcraft.wiki.gg/wiki/API_GetTradeSkillReagentInfo), [reagent item link](https://warcraft.wiki.gg/wiki/API_GetTradeSkillReagentItemLink)). Persist numeric item IDs and quantities, not localized names. |
| Bag inventory | Yes | Iterate bag IDs/slots with `C_Container.GetContainerNumSlots` and `C_Container.GetContainerItemInfo`; the generated Classic API source returns item ID and stack count ([Classic API source](https://raw.githubusercontent.com/Gethe/wow-ui-source/classic_era/Interface/AddOns/Blizzard_APIDocumentationGenerated/ContainerDocumentation.lua)). |
| Bank contents | Yes, last-seen snapshot | Refresh only at a bank and label with `lastBankScanAt`. Bag IDs differ across client flavors and some Classic enum aliases are historically wrong; use a tested adapter rather than hard-coded Retail values ([BagID notes](https://warcraft.wiki.gg/wiki/BagID), [BagSync compatibility code](https://raw.githubusercontent.com/Xruptor/BagSync/master/wireframe/scanner.lua)). |
| Reagent bank/bag | Client-dependent | Classic Era does not have Retail's historical reagent-bank feature; progression/Forever behavior must be detected. Store locations as capabilities, not required schema fields. |
| Cross-character material availability | Yes | Compare a recipe's persisted `{itemID, requiredCount}` list with each tracked character's last persisted per-location item totals. The result is necessarily only as fresh as each character/location snapshot. |
| Live Wowhead data from inside the addon | No | WoW addons cannot make web requests. Wowhead's published tooltips/XML mechanism is for websites and per-entity feeds ([Wowhead tooltips](https://www.wowhead.com/tooltips)), not an in-game Lua network API. |

## Client/API differences that affect the design

### Classic Era, TBC/Wrath/Cataclysm/Mists progression

Current clients share many namespaced container and quest APIs, but profession APIs are not the same as Retail. Classic/progression clients retain the legacy indexed trade-skill functions. `GetTradeSkillLine()` explicitly describes the profession currently visible in the trade-skill frame and otherwise returns an unknown/empty state ([API](https://warcraft.wiki.gg/wiki/API%3AGetTradeSkillLine)). Recipe indices also depend on the current expanded/collapsed list, so the scanner should expand categories, ignore headers, and persist stable IDs parsed from recipe/output/reagent links rather than persisting row indices.

The exact client matters. As of this research, the mirrored Blizzard UI source identifies current Classic Era as 1.15.9 and current Classic progression as Mists 5.5.4 ([Era version](https://raw.githubusercontent.com/Gethe/wow-ui-source/classic_era/version.txt), [progression version](https://raw.githubusercontent.com/Gethe/wow-ui-source/classic/version.txt)). `GetBuildInfo()` exposes build and TOC interface versions at runtime ([API](https://warcraft.wiki.gg/wiki/API%3AGetBuildInfo)).

### Retail

Retail has the richer `C_TradeSkillUI` API. `GetAllRecipeIDs()` returns all recipes for the currently selected profession but returns an empty table until the profession panel has been opened; `GetRecipeInfo()` includes a `learned` flag ([recipe list](https://warcraft.wiki.gg/wiki/API_C_TradeSkillUI.GetAllRecipeIDs), [recipe info](https://warcraft.wiki.gg/wiki/API_C_TradeSkillUI.GetRecipeInfo)). Retail also has `C_QuestLine` metadata that Classic lacks. This should be a separate adapter, not mixed into Classic code paths.

### World of Warcraft: Forever

Forever is now an official Blizzard product. Beta begins Thursday, September 17, 2026; launch is November 4 ([official announcement](https://news.blizzard.com/en-us/article/24302093/carve-a-new-path-with-world-of-warcraft-forever)). Blizzard says it is guided by Classic principles but is **not** a mode, season, or new version of Classic ([official recap](https://worldofwarcraft.blizzard.com/en-us/news/24303862/world-of-warcraft-forever-whats-next-panel-recap)).

This is especially important for this addon:

- Blizzard has announced more than 600 new profession recipes, including Blueprint recipes from dungeon bosses. A current WoW Classic recipe catalog will therefore be incomplete ([official Deep Dive](https://worldofwarcraft.blizzard.com/en-us/news/24303313)).
- Forever is realmless and uses two-part character names unique per region. Do not make `name-realm` the database primary key; store the runtime GUID as the technical identity and the complete display name/ruleset/region as attributes ([official Deep Dive](https://worldofwarcraft.blizzard.com/en-us/news/24303313)).
- No official statement currently identifies the underlying Lua API, TOC interface value, client build, or project constant. The official forum question asking whether the API is Retail- or Classic-based is unanswered ([forum thread](https://us.forums.blizzard.com/en/wow/t/wow-forever-addon-api-classic-retail-or-something-else/2348601)).

Forever compatibility is therefore provisional, not blocked. The architecture can be prepared now; the exact adapter and recipe database cannot be finalized until beta inspection.

## Persistence design

Use a single **account-wide** SavedVariables root, for example `CraftRosterDB`, declared with `## SavedVariables: CraftRosterDB`. Do not use `SavedVariablesPerCharacter` for the primary data: WoW loads only the currently logged-in character's per-character file, which defeats cross-character lookup. BagSync demonstrates the established account-wide pattern with one `BagSyncDB` SavedVariable while supporting Classic Era, TBC, Wrath, Cataclysm, Mists, and Retail from one addon ([BagSync TOC](https://raw.githubusercontent.com/Xruptor/BagSync/master/BagSync.toc)).

Recommended logical layout:

```lua
CraftRosterDB = {
  schemaVersion = 1,
  characters = {
    [characterKey] = {
      tracked = true,
      identity = {
        guid = "Player-...",
        displayName = "...",
        realm = "...",       -- nil/optional on Forever
        ruleset = "...",     -- optional; useful on Forever
        classID = 1,
      },
      client = {
        projectID = 2,
        version = "1.15.9",
        interface = 11509,
      },
      level = 42,
      updatedAt = 0,
      quests = {
        active = { [questID] = { title = "...", objectives = {} } },
        completed = { [questID] = true },
        pinnedQuestID = nil,
        manualGoal = nil,
        scannedAt = 0,
      },
      professions = {
        [professionKey] = {
          skillLineID = 164,
          name = "Blacksmithing", -- display only
          rank = 225,
          maxRank = 300,
          recipes = { [recipeKey] = true },
          scannedAt = 0,
        },
      },
      inventory = {
        bags = { [itemID] = count },
        bank = { [itemID] = count },
        reagentBank = { [itemID] = count },
        bagScannedAt = 0,
        bankScannedAt = 0,
      },
    },
  },
}
```

Keep the **static recipe catalog** out of SavedVariables and ship it as versioned Lua data files inside the addon. Store only learned-recipe sets and character snapshots in SavedVariables. This avoids duplicating recipe data per character and makes catalog updates deterministic.

JSON inside a SavedVariables string is technically possible but counterproductive: the client still writes a Lua assignment file, JSON parsing increases code/memory cost, and tables become less inspectable. SQLite is impossible without a separate desktop companion process. A companion could transform SavedVariables after `/reload` or logout, but it adds installation, synchronization, and policy/security surface without helping the first local-only release.

## Snapshot strategy and freshness

Prefer event-driven updates, with a ten-minute in-memory safety scan:

- At `PLAYER_LOGIN`/`PLAYER_ENTERING_WORLD`: initialize identity, level, client metadata, current quest state, and bags.
- At `PLAYER_LEVEL_UP`: use the event's new-level payload, because `UnitLevel("player")` can still be stale during that event ([UnitLevel note](https://warcraft.wiki.gg/wiki/API_UnitLevel)).
- At `QUEST_LOG_UPDATE`, `QUEST_ACCEPTED`, `QUEST_REMOVED`, and `QUEST_TURNED_IN`: debounce and rebuild active quests; refresh completion data after turn-in. The generated Classic quest API lists these events and objective/completion queries ([Classic quest API source](https://raw.githubusercontent.com/Gethe/wow-ui-source/classic_era/Interface/AddOns/Blizzard_APIDocumentationGenerated/QuestLogDocumentation.lua)).
- At `BAG_UPDATE_DELAYED`: rebuild or incrementally update item totals. The generated container API documents bag-update events ([Classic container API source](https://raw.githubusercontent.com/Gethe/wow-ui-source/classic_era/Interface/AddOns/Blizzard_APIDocumentationGenerated/ContainerDocumentation.lua)).
- At `BANKFRAME_OPENED`, bank slot changes, and bank close: refresh bank-capable locations while data is accessible.
- At `TRADE_SKILL_SHOW`/`TRADE_SKILL_UPDATE`: debounce and scan the currently opened profession. BagSync uses precisely separate Retail and Classic profession paths and these events ([event code](https://raw.githubusercontent.com/Xruptor/BagSync/master/wireframe/events.lua), [scanner code](https://raw.githubusercontent.com/Xruptor/BagSync/master/wireframe/scanner.lua)).
- Every ten minutes: refresh only always-available current-character state (identity, level, quests, bags). Do not overwrite a valid bank/profession cache with empty data merely because its UI is closed.
- At `PLAYER_LOGOUT`: perform a final cheap refresh of always-available state and timestamps. `PLAYER_LOGOUT` fires immediately before SavedVariables are written ([event](https://warcraft.wiki.gg/wiki/PLAYER_LOGOUT)).

Important: the ten-minute timer updates only the Lua table in memory. WoW writes the SavedVariables file on logout, disconnect, quit, or `/reload`; it is not an arbitrary periodic disk-write API ([SavedVariables lifecycle](https://warcraft.wiki.gg/wiki/Saving_variables_between_game_sessions)). A client crash can therefore lose changes since the last successful save/reload.

Every UI value derived from a snapshot should expose freshness. Suggested labels are `Updated 3m ago`, `Bank: last seen 2d ago`, and `Profession recipes: scan required`.

## Recipe identity and catalog strategy

For Classic, use these canonical identifiers in priority order:

1. recipe/enchant spell ID parsed from `GetTradeSkillRecipeLink()`;
2. output item ID from `GetTradeSkillItemLink()` for ordinary crafts;
3. an embedded-catalog key when a craft has no ordinary output item or legacy APIs do not expose a stable recipe spell ID.

Never persist the trade-skill row index; it changes with filters and collapsed headers. BagSync's current Classic scanner follows the same pattern: skip headers, prefer recipe/enchant links, then fall back to output item links ([source](https://raw.githubusercontent.com/Xruptor/BagSync/master/wireframe/scanner.lua)).

There are two distinct product requirements:

- **Known recipes only:** can be collected entirely from the in-game profession UI after each profession is opened. Reagents and output links can be snapshotted at the same time.
- **All available and missing recipes, including where to obtain them:** requires a complete shipped catalog. AllTheThings explicitly ships database modules to avoid relying on incomplete runtime API access ([project source](https://github.com/ATTWoWAddon/AllTheThings)).

Wowhead can inform the build-time catalog, but should not be treated as a live runtime dependency. Obtain permission/confirm data-use terms before distributing a bulk-derived database. Its documented XML interface is per item/entity and not evidence of a supported bulk export API ([Wowhead tooltips/XML documentation](https://www.wowhead.com/tooltips)). An alternative is a permissively licensed curated dataset or a project-owned extractor run against beta client data. Forever's 600+ additions require a Forever-specific dataset.

## Cross-character material calculation

When a recipe is selected:

1. Resolve its fixed reagent list to `{itemID, requiredCount}`.
2. For each tracked character, read the last snapshot and compute counts by location: bags, bank, and any client-supported reagent storage.
3. Display `owned / required` for every character and an account total.
4. Compute `craftableCount = min(floor(totalOwned[itemID] / requiredCount))` across required materials. Keep this informational; materials split across offline characters cannot be crafted until transferred.
5. Mark stale/never-scanned locations and do not silently present missing data as zero.

Classic recipes are mostly fixed-reagent crafts, so this is straightforward. If Forever introduces optional/substitutable reagents, qualities, account banks, or profession-specialization modifiers, the schema should allow a recipe requirement to be a group of alternatives rather than only a flat list.

## Beta validation gate for September 17

Before declaring Forever support, run a small probe addon and inspect the installed client:

1. Record `.build.info`, `GetBuildInfo()`, `WOW_PROJECT_ID`, all available `WOW_PROJECT_*` constants, and the accepted `.toc` interface number.
2. Inspect `Interface/AddOns/Blizzard_APIDocumentationGenerated` and the relevant Blizzard FrameXML modules if the beta distributes/exposes them.
3. Verify character identity: `UnitGUID("player")`, full two-part name APIs, ruleset/region data, and behavior after character recreation/transfer.
4. Verify quest enumeration, completed-quest access, objective progress, and whether Forever exposes any questline metadata.
5. Open every profession type, including Enchanting and a Blueprint/Camping recipe. Record events, list functions, stable recipe ID, output ID, reagent IDs/quantities, and behavior with collapsed filters.
6. Verify backpack, equipped bags, bank, any account-wide storage, and event timing. Never assume Classic Era bag numeric constants are correct for Forever.
7. Write a test SavedVariables table, `/reload`, log out/in, and confirm the account-wide character map is readable from a second character.
8. Compare a small sample of beta recipes against the planned static catalog. Block catalog release if the Classic data set is being reused unchanged.

Blizzard is also holding a developer Q&A on September 17; if the beta itself does not make the contract clear, the exact addon API flavor/TOC question is appropriate there ([official Q&A announcement](https://worldofwarcraft.blizzard.com/en-us/news/24303312)).

## Product risks and decisions for the later specification

- Decide whether “questline” means a manually pinned current objective or automatic chain inference. The latter is a separate content-database feature.
- Decide whether “available recipes” means learned recipes or the entire learnable catalog. The latter requires maintained data and source/licensing decisions.
- Define freshness semantics and whether stale bank values count toward totals by default.
- Scope v1 to one WoW account and one local installation. Multiple WoW accounts or computers require explicit sync/companion architecture.
- Treat localized names as display fields only; identity and joins should use numeric IDs/GUIDs.
- Keep the addon read-only/informational. Blizzard's published addon policy requires addons to be free, code-visible, non-advertising, and non-disruptive ([official policy](https://eu.forums.blizzard.com/en/wow/t/wow-user-interface-add-on-development-policy/1642)).

## Bottom line for planning

No additional Classic addon download is needed to establish feasibility: Blizzard's mirrored UI/API source plus BagSync and AllTheThings source already demonstrate the necessary patterns. The only essential future artifact is the Forever beta client itself. Once installed, its API and data should be inspected before the implementation specification names exact functions or promises complete recipe coverage.
