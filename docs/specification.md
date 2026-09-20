# GamersTrackerForever — Final Addon Specification

**Version:** 1.0

**Status:** Final for implementation

**Prepared:** 2026-09-15

**Initial platform:** WoW Classic Era

**Second platform:** World of Warcraft: Forever, after beta API validation

## 1. Product definition

GamersTrackerForever is a compact World of Warcraft addon that records the last-known state of selected characters and answers two questions:

1. Which professions and recipes does each tracked character have?
2. For a selected recipe, which tracked characters hold the required materials, and is the pooled amount sufficient?

The addon tracks:

- character identity and level;
- professions and profession skill levels;
- learned recipes and their material requirements;
- bag inventory;
- last-known bank inventory;
- timestamps and data freshness.

Quest and questline tracking is explicitly excluded from this version.

## 2. Feasibility decision

The addon is feasible on WoW Classic Era.

- The logged-in character's identity, level, skills, professions, recipes, bags, and accessible bank contents can be read through addon APIs.
- Other characters cannot be queried while offline. Their information is a last-known snapshot collected when each character was played.
- Bag data can be refreshed while playing. Bank data can only be refreshed while the bank is accessible.
- Recipe details are most reliably collected while the relevant profession window is open.
- Addons cannot make HTTP requests to Wowhead or write arbitrary JSON, SQLite, or NoSQL files.
- Native persistence must use an account-wide Lua `SavedVariables` table written by the WoW client during logout, clean exit, disconnect, or `/reload`.
- A ten-minute timer can reconcile the in-memory snapshot but cannot force a background disk write.

The local Classic Era installation and installed BagBrother/Bagnon source demonstrate the required cross-character inventory and SavedVariables pattern. No additional reference addon needs to be downloaded.

## 3. WoW: Forever compatibility position

World of Warcraft: Forever beta begins September 17, 2026. Blizzard has not yet published its addon interface number, API flavor, project constant, or compatibility guarantees.

The product announcements do establish several requirements:

- Forever is a separate permanent WoW experience.
- It is realmless and uses region-unique two-part character names.
- Characters are separated by ruleset and faction ecosystems.
- Forever contains more than 600 new profession recipes, including Blueprint recipes.

Sources: Blizzard's [Forever announcement](https://news.blizzard.com/en-us/article/24302093/carve-a-new-path-with-world-of-warcraft-forever), [What's Next recap](https://worldofwarcraft.blizzard.com/en-us/news/24303862/world-of-warcraft-forever-whats-next-panel-recap), and [Deep Dive recap](https://worldofwarcraft.blizzard.com/en-us/news/24303313).

The core must therefore be client-neutral. All version-sensitive calls belong behind an API adapter, and Classic and Forever data must occupy separate product namespaces. Forever support is accepted only after the beta validation suite passes.

## 4. Product scope

### 4.1 MVP features

- Discover the current character on login.
- Allow the user to track or untrack discovered characters.
- Display each tracked character's name, level, class, faction, product, transfer ecosystem, and last-seen time.
- Record primary and secondary professions with current and maximum skill values.
- Scan learned recipes and reagent requirements when a profession is opened.
- Record bag contents from bag events.
- Record bank contents while the bank is open and preserve the last-known snapshot afterward.
- List recipes known by one or more tracked characters.
- Display which characters know a selected recipe.
- Display required materials with bag, bank, per-character, pooled, and shortage totals.
- Indicate stale, missing, and never-scanned data.
- Store everything locally in account-wide SavedVariables.
- Provide a compact, expandable Blizzard-style UI.
- Use a persistent two-pane native UI: a left character selector and a larger
  right detail/recipes pane. The selector exposes a `Track up to` limit from 1
  through 10 (default 3), persists the selected character, and never silently
  untracks existing characters when a limit is reached.

### 4.2 Out of scope

- Quest or questline progress.
- Automatic crafting, buying, selling, mailing, trading, or item movement.
- Cloud or server synchronization.
- Synchronization across computers or separate WoW account folders.
- Live Wowhead or other website requests.
- A complete catalog of recipes no tracked character knows.
- Recipe source/drop/vendor guidance.
- Auction house, mailbox, guild bank, and equipped-item counts.
- Price calculations.
- Profession optimization, crafting queues, or shopping lists.
- Manual JSON or SQLite storage inside the WoW addon.

## 5. Terminology

- **Discovered character:** a character that has loaded the addon at least once.
- **Tracked character:** a discovered character included in the addon UI and material calculations.
- **Current character:** the character presently logged in.
- **Snapshot:** last data collected for one character and one data source.
- **Fresh data:** data collected within its configured freshness threshold.
- **Transfer ecosystem:** characters between which the addon may reasonably assume items can be moved.
- **Known recipe:** a recipe captured from a tracked character's profession UI.
- **Pooled materials:** the sum of eligible last-known item counts across compatible tracked characters.
- **Craftable now:** the current character has the materials available to the game immediately.
- **Craftable after transfer:** compatible tracked characters collectively have enough last-known materials.

## 6. Functional requirements

### FR-1: Character discovery and tracking

On login, the addon shall create or update the current character record.

The record shall contain:

- stable character GUID when available;
- full display name;
- realm for Classic clients;
- region/ruleset/two-part name fields for Forever when exposed;
- class and faction;
- current level;
- game product and client build;
- last-seen timestamp;
- tracked/untracked state.

The UI shall let the user:

- track or untrack the current/discovered character;
- hide an untracked character;
- permanently forget a character and its snapshots through an explicit confirmation.

The addon shall not claim to enumerate characters that have never loaded it. Manual empty placeholders are not part of MVP.

### FR-2: Level tracking

The addon shall capture level:

- during login initialization;
- on the level-up event using the event's new-level value;
- during the ten-minute reconciliation pass;
- during the final logout snapshot.

The character list shall show the last-known level and last-seen time.

### FR-3: Profession tracking

The addon shall capture all profession/skill lines identified as professions by the current client adapter.

For every profession, store:

- stable skill-line or profession ID when exposed;
- localized display name;
- current skill value;
- maximum skill value;
- specialization when reliably detectable;
- last skill scan time;
- last recipe scan time;
- recipe scan state: `never`, `current`, `stale`, or `unsupported`.

Profession ranks shall update on login, skill-line changes, the reconciliation timer, and logout.

### FR-4: Learned recipe scanning

When a profession window is opened or updated, the addon shall scan all visible/loaded learned recipes after the API data has settled.

For each recipe, capture when exposed:

- recipe or spell ID;
- localized name and icon;
- profession ID;
- output item ID/link;
- minimum and maximum output quantity;
- reagent item IDs and required quantities;
- tool, location, cooldown, or other special requirement flags;
- client build and scan timestamp.

Rules:

- Never use a trade-skill row index as persistent identity.
- Expand or traverse profession categories as required by the client adapter.
- Skip headers and non-recipe rows.
- Prefer recipe/spell ID; use output item ID only as a defined fallback.
- Replace the learned set for the scanned profession atomically after a successful complete scan.
- Preserve the previous valid snapshot if a scan fails or the profession data source is incomplete.
- Mark a profession `stale` after a client/addon data-version change until it is opened again.

### FR-5: Inventory scanning

The addon shall maintain item totals by numeric item ID.

Bag inventory:

- scan at login;
- rescan on the debounced bag-update event;
- reconcile every ten minutes;
- perform a lightweight final scan at logout.

Bank inventory:

- scan only while bank containers are accessible;
- refresh on bank open, relevant bank changes, and bank close;
- retain the last successful snapshot after leaving the bank;
- never replace valid bank data with an empty result caused by an inaccessible bank;
- show the bank snapshot timestamp in every result that uses it.

Store totals separately for bags and bank. Container/slot detail is not required after aggregation unless needed for diagnostics.

A zero total of readable container slots during early login/world entry is an
incomplete scan, not an empty inventory. Preserve the previous valid bags and
retry after approximately one and three seconds, with a bounded retry count.
An actually empty inventory is valid when the client reports one or more
readable slots.

### FR-6: Recipe catalog

The MVP catalog shall contain recipes learned by at least one tracked character and captured from the game client.

Recipe definitions shall be deduplicated at product level. Characters shall store only the set of recipe IDs they know.

The recipe browser shall support:

- text search by recipe/output name;
- profession filter;
- known-by-character filter;
- craftable/shortage filter;
- transfer-ecosystem filter;
- sorting by name, profession, or craftability.

Wowhead is not an MVP dependency. A future separately approved build-time catalog may add unlearned recipes and recipe sources after licensing and Forever data availability are resolved.

### FR-7: Material availability

Clicking a recipe shall open a material panel.

For every reagent, show:

- item icon and localized name;
- quantity required per craft;
- current-character bag quantity;
- each tracked character's bag quantity;
- each tracked character's last-known bank quantity;
- pooled compatible total;
- shortage;
- snapshot age;
- status: `ready`, `short`, `stale`, `unknown`, or `special requirement`.

Every tracked character shall be represented, including zero values and characters with missing scans.

The panel shall distinguish:

1. **Available now:** materials immediately usable by the current character.
2. **Available after transfer:** pooled materials belonging to compatible tracked characters.
3. **Incompatible/isolated:** materials on characters outside the selected transfer ecosystem.

### FR-8: Craftability calculation

For fixed ordinary reagents:

```text
availableNowOwned(item) = currentCharacterBagCount(item)
characterTransferableOwned(item) = bagCount(item) + lastKnownBankCount(item)
pooledAfterTransferOwned(item) = sum(characterTransferableOwned(item)) for compatible tracked characters
shortage(item) = max(required(item) - selectedViewOwned(item), 0)
craftableCount = min(floor(selectedViewOwned(item) / required(item))) across reagents
```

The `Available now` view shall never count bank inventory, including the current
character's bank. A missing current-character bag snapshot makes that view
`unknown`; a missing bank snapshot does not. The `Available after transfer` view
may use last-known bank inventory. If its known total is insufficient and a
compatible contributing location has never been scanned, the result is
`unknown` rather than a confirmed shortage.

The result is informational. It shall not imply that materials have been transferred.

Items or requirements that are soulbound, currencies, tools, cooldowns, location-bound, quality-based, or substitutable shall not be treated as normal pooled reagents unless the client adapter provides enough data for a correct rule. Unknown cases shall display `unknown`.

### FR-9: Freshness

Every character, profession, bag, and bank snapshot shall have an independent timestamp.

Default presentation:

- normal: scanned less than 24 hours ago;
- amber: scanned 24 hours to 7 days ago;
- gray: older than 7 days, never scanned, or unavailable;
- red: confirmed material shortage.

The thresholds shall be configurable. Stale values may contribute to a pooled total, but the UI must visibly label the result `based on stale data`.

### FR-10: Diagnostics

`/gtf status` shall display (and `/act status` shall remain an alias):

- addon version and database schema version;
- product, client version, build, and interface number;
- detected API adapter;
- current character key and transfer ecosystem;
- last character, profession, bag, and bank scans;
- total tracked characters and cached recipes;
- unsupported capabilities or last scanner error.

Diagnostics must not expose private account paths or unrelated SavedVariables.

## 7. Persistence specification

The WoW client owns SavedVariables serialization. Addon code only updates the
in-memory `GamersTrackerForeverDB` table; it cannot write arbitrary files or
make arbitrary HTTP requests. Future server synchronization must use an
explicit export after SavedVariables flush and a companion desktop uploader,
or another approved bridge.

### 7.1 Storage mechanism

The `.toc` file shall declare:

```text
## SavedVariables: GamersTrackerForeverDB AltCraftTrackerDB
```

`GamersTrackerForeverDB` is the only active database. `AltCraftTrackerDB` is
listed solely so WoW can load an older installation for the one-time migration
into the new global; addon code does not modify it after migration.

The addon shall modify a Lua table in memory. WoW owns disk serialization.

The ten-minute reconciliation timer is not a disk-save guarantee. The addon shall not force `/reload` during gameplay.

### 7.2 Database shape

```lua
GamersTrackerForeverDB = {
  schemaVersion = 1,
  settings = {
    staleAfterSeconds = 86400,
    veryStaleAfterSeconds = 604800,
    maxTrackedCharacters = 3,
    selectedCharacterKey = nil,
  },
  products = {
    [productKey] = {
      dataVersion = 1,
      recipes = {
        [recipeKey] = {
          recipeID = 0,
          professionID = 0,
          name = "",
          icon = 0,
          outputItemID = 0,
          outputMin = 1,
          outputMax = 1,
          reagents = {
            { itemID = 0, quantity = 0, kind = "item" },
          },
          discoveredBuild = "",
        },
      },
      characters = {
        [characterKey] = {
          tracked = true,
          identity = {
            guid = "",
            displayName = "",
            realm = nil,
            region = nil,
            ruleset = nil,
            faction = "",
            classID = 0,
            transferGroup = "",
          },
          client = {
            productID = 0,
            version = "",
            build = "",
            interface = 0,
          },
          level = 0,
          lastSeenAt = 0,
          professions = {
            [professionKey] = {
              professionID = 0,
              name = "",
              rank = 0,
              maxRank = 0,
              specializationID = nil,
              learnedRecipes = { [recipeKey] = true },
              skillScannedAt = 0,
              recipesScannedAt = 0,
              scanState = "never",
            },
          },
          inventory = {
            bags = { [itemID] = 0 },
            bank = { [itemID] = 0 },
            bagsScannedAt = 0,
            bankScannedAt = 0,
          },
        },
      },
    },
  },
}
```

### 7.3 Identity rules

- Use the character GUID as the primary technical key when available.
- Classic fallback: normalized realm + character name + faction.
- Forever fallback: region + ruleset + normalized two-part name + faction, subject to beta validation.
- Display names are not database joins.
- Transfer compatibility shall be represented by `transferGroup`, calculated by the active client adapter.
- Classic and Forever data shall never share the same product namespace.

### 7.4 Database integrity

- Validate every loaded root and record type.
- Apply versioned forward migrations.
- Never silently reset the entire database because one character record is invalid.
- Quarantine or ignore invalid subrecords and report them through diagnostics.
- Commit scanner results atomically only after a successful scan.
- Deduplicate product recipe definitions.
- Prune orphaned recipe definitions only through an explicit maintenance action or safe migration.

## 8. Runtime events

| Event family | Required action |
|---|---|
| Addon loaded / player entering world | Initialize and migrate DB; capture client, identity, level, professions, and bags |
| Player level up | Store the event's new level |
| Skill-line changed | Refresh profession ranks and mark recipes stale when appropriate |
| Trade-skill show/update/close | Debounce and scan the loaded profession and learned recipes |
| Bag update delayed | Debounced bag rescan |
| Bank opened/slot changed/closed | Rescan accessible bank locations and timestamp success |
| Ten-minute timer | Reconcile level, profession ranks, and bags; never erase inaccessible data |
| Player logout | Perform a cheap final accessible-state snapshot before SavedVariables serialization |

All noisy events shall be debounced. Expensive scans shall be split across frames if profiling shows visible frame stalls.

## 9. UI specification

Use only native Blizzard Lua frames, XML bindings, item buttons, icons,
tooltips, scroll containers, and expand/collapse controls. HTML/CSS/JavaScript
are not available to WoW addons.

### 9.1 Opening the addon

- Slash command: `/gtf`; `/act` remains a compatibility alias.
- Optional minimap button, enabled by default.
- Optional key binding.
- Window is movable, resizable, clamped to screen, and remembers its geometry.

### 9.2 Characters tab

The tab is a persistent two-pane layout. The left pane always lists every
discovered character, marks the selected row, and shows tracked/available
status. It includes the native `Track up to` dropdown. The right pane shows the
selected character overview (or a helpful no-selection message), profession
rows, scan freshness, and sorted saved bag/bank item rows with item IDs and
counts. Selecting a row updates `settings.selectedCharacterKey`.

Collapsed row:

```text
[Class] Ana Forever   L42   Alchemy 225 | Herbalism 210   seen 12m ago   [>]
```

Expanded content:

- identity/product/transfer ecosystem;
- level and last seen;
- profession rows with rank and recipe scan status;
- bag and bank scan freshness;
- track/untrack and forget controls.

### 9.3 Recipes tab

Recipe row:

```text
[Icon] Heavy Copper Maul   Blacksmithing   Known: Brinna   Transfer-ready: 1
```

Controls:

- search field;
- profession filter;
- character filter;
- craftable/shortage filter;
- transfer ecosystem filter;
- expandable recipe details.

### 9.4 Material panel

```text
Heavy Copper Maul — known by Brinna

Material       Need   Total   Brinna             Corvin           Status
Copper Bar       20      24   4 bags             20 bank (2h)     Ready
Weak Flux         2       —   Vendor/special      —                Buy 2
```

Hovering a quantity shall show its character, location, exact scan time, and whether it is included in the pooled total.

## 10. Architecture

```text
Bootstrap
  -> ApiCompat
  -> Repository / Migrations
  -> CharacterService
       -> ProfessionScanner
       -> InventoryScanner
  -> RecipeCatalog
  -> CraftabilityService
  -> ViewModels
  -> UI
```

Responsibilities:

- **Bootstrap:** addon lifecycle, event registration, commands, and dependency wiring.
- **ApiCompat:** all client/version-sensitive WoW API access and transfer-group rules.
- **Repository:** SavedVariables validation, schema, migrations, reads, and atomic writes.
- **CharacterService:** coordinates identity, level, profession, and inventory snapshots.
- **ProfessionScanner:** converts loaded trade-skill data into stable profession/recipe records.
- **InventoryScanner:** converts accessible containers into item totals by location.
- **RecipeCatalog:** deduplicated recipes discovered from clients.
- **CraftabilityService:** pure calculations with no WoW API calls.
- **ViewModels:** transforms data and freshness into UI-ready rows.
- **UI:** rendering and user interaction only.

## 11. Non-functional requirements

- The addon is informational and read-only.
- No protected-action automation.
- No perceptible frame stalls during normal bag or skill changes.
- Numeric IDs drive joins; localized names are display-only.
- Unsupported APIs disable only the affected feature.
- Scanner failures preserve the last valid snapshot.
- Every cached value shown to the user exposes freshness.
- Core calculations are testable outside WoW with Lua fixtures.
- API adapters are selected through product/capability detection, not folder-name assumptions.
- Source files remain readable and modular; no generated external catalog is required for MVP.

## 12. Acceptance test suite

### Character and persistence

- Login discovers character A and saves its level.
- Tracking state survives `/reload` and logout.
- Login as character B preserves and displays character A.
- Same-named Classic characters on different realms do not collide.
- Classic and Forever records do not mix.
- Forgetting a character removes only the selected character's snapshots.

### Professions and recipes

- Profession names and ranks are visible after login.
- An unopened profession displays `recipe scan required`.
- Opening a profession captures every learned recipe exposed by the client.
- Reagents and quantities are stored by item ID.
- Learning a recipe and reopening/updating the profession adds it.
- Abandoning a profession updates the profession state without corrupting the catalog.
- A failed/incomplete scan does not erase the previous learned set.

### Inventory

- Adding, removing, splitting, and combining bag stacks produces correct totals.
- Opening the bank records its contents and timestamp.
- Closing the bank does not erase its contents.
- Login away from a bank retains last-known bank data and marks its age.
- Unknown and inaccessible storage is not interpreted as zero.

### Material calculations

- Recipe materials located on one character produce correct totals.
- Materials distributed across two compatible characters produce the correct pooled result.
- Incompatible characters are displayed but excluded from the transferable total.
- A shortage is calculated per reagent.
- Maximum craftable count is the minimum supported across ordinary reagents.
- Stale bank data visibly marks the result as stale.
- Special and unknown requirements do not produce a false `ready` result.

### Persistence lifecycle

- State survives `/reload`.
- State survives clean logout and client restart.
- A ten-minute reconciliation updates the in-memory timestamps without forcing a reload.
- Corrupt fixture records are isolated without destroying healthy records.
- Schema migration preserves tracked characters, recipes, and inventory.

## 13. Forever beta release gate

Before claiming Forever support:

1. Record install flavor, client build, interface number, project constants, and accepted `.toc` metadata.
2. Confirm that third-party addons load.
3. Verify GUID and complete two-part character-name APIs.
4. Identify region, ruleset, faction, and Hardcore transfer boundaries.
5. Verify profession enumeration before opening the profession UI.
6. Open professions and identify exact learned-recipe, output, reagent, Blueprint, tool, and special-requirement APIs.
7. Verify bag and bank container IDs/events.
8. Check for account-wide storage or new reagent locations.
9. Verify account-wide SavedVariables from two beta characters.
10. Scan representative new Forever recipes and compare recipe/item ID behavior with Classic.
11. Run the full acceptance suite using the Forever adapter.

If the beta client is installed locally, inspect it directly and use a minimal purpose-built probe addon. No third-party addon download is required for this gate.

## 14. Development work packages

Each work package is owned by exactly one development agent. Agents may not edit the same module concurrently. Integration begins only after a package meets its handoff tests.

### Task 1 — Addon scaffold and API capability probe

Owner: one Luna/high agent.

Deliverables:

- addon folder and `.toc` files;
- Bootstrap and event dispatcher;
- slash commands;
- product/build detection;
- initial Classic `ApiCompat` interface;
- `/gtf status` capability output (with `/act status` compatibility coverage);
- minimal mock/runtime test harness.

Depends on: none.

### Task 2 — Repository, schema, and migrations

Owner: one Luna/high agent.

Deliverables:

- SavedVariables repository;
- schema validation and version 1 migration;
- product/character keys;
- atomic snapshot commits;
- fixture tests for valid, missing, and corrupt records.

Depends on: Task 1 interfaces.

### Task 3 — Character and inventory scanners

Owner: one Luna/high agent.

Deliverables:

- character discovery and level updates;
- transfer-group record supplied through `ApiCompat`;
- bag scanner and debounced events;
- bank scanner and freshness timestamps;
- scanner unit fixtures and in-client checklist.

Depends on: Tasks 1 and 2.

### Task 4 — Profession and learned-recipe scanner

Owner: one Luna/high agent.

Deliverables:

- profession/rank discovery;
- profession scan states;
- Classic learned-recipe traversal;
- recipe/output/reagent normalization;
- atomic learned-set updates;
- failure preservation and fixture tests.

Depends on: Tasks 1 and 2.

### Task 5 — Recipe catalog and craftability service

Owner: one Luna/high agent.

Deliverables:

- deduplicated product recipe catalog;
- per-character known-recipe queries;
- transfer-compatible aggregation;
- shortage and craftable-count calculations;
- stale/unknown/special requirement outcomes;
- pure Lua unit tests.

Depends on: Task 2 contracts; consumes Task 3 and 4 records.

### Task 6 — Compact character and recipe UI

Owner: one Luna/high agent.

Deliverables:

- main window and saved geometry;
- Characters tab;
- Recipes tab and filters;
- material matrix;
- freshness states and tooltips;
- track/untrack/forget flows;
- minimap button and key binding.

Depends on: Tasks 2 and 5 public interfaces.

### Task 7 — Integration, Classic validation, and packaging

Owner: one Luna/high agent.

Deliverables:

- integrated addon build;
- complete Classic acceptance pass;
- performance/error review;
- SavedVariables migration/recovery test;
- release notes and install instructions;
- packaged ZIP artifact.

Depends on: Tasks 1–6.

### Task 8 — Forever beta adapter

Owner: one Luna/high agent after the beta client is available.

Deliverables:

- beta capability report;
- Forever `.toc` and `ApiCompat` implementation;
- two-part-name/realmless transfer identity;
- Forever profession, Blueprint, recipe, and inventory normalization;
- Forever acceptance pass and compatibility notes.

Depends on: Task 1 contracts, Tasks 3–5 scanner models, and an installed beta client.

### Execution order

```text
Task 1
  -> Task 2
      -> Tasks 3 and 4 in parallel
          -> Task 5
              -> Task 6
                  -> Task 7

Task 8 starts when the beta client exists and the relevant core interfaces are stable.
```

## 15. Definition of done

Version 1 is complete when:

- two Classic characters retain independent level, profession, recipe, bag, and bank snapshots;
- the recipe browser shows recipes known by either character;
- selecting a recipe displays correct per-character and pooled material quantities;
- incompatible and stale snapshots cannot silently produce a misleading result;
- data survives `/reload`, logout, and client restart;
- unsupported functionality fails locally and visibly;
- the full Classic acceptance suite passes;
- the addon is packaged with install instructions;
- no quest functionality, external service, or live Wowhead dependency is present.

Forever is supported only when Task 8 and the Forever release gate both pass.
