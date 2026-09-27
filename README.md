# GamersTrackerForever

GamersTrackerForever is an account-wide, last-known tracker for character
levels, professions, learned recipes, bags, banks where accessible, and
cross-character crafting materials on Classic Era and WoW Forever beta.

The interface uses only native Classic/Season of Discovery Blizzard Lua frames
and XML bindings; HTML, CSS, and JavaScript are not available to WoW addons.
The main window has a searchable Character > Profession > Category > Recipe
tree on the left and a larger detail pane on the right. Every character that
runs the addon is included automatically; there is no tracking cap or manual
Track/Untrack control. Class icons and conservative current-character
cannot-wear hints help identify recipes at a glance.

The addon is informational. It does not move items, automate protected actions,
or contact an external service. The beta probe on build `1.60.1.69913`
reported interface `16001`; the installed executable is now `1.60.1.70009`.
The beta adapter supports character levels, profession ranks, bag snapshots,
and learned-recipe/reagent capture while a profession window is open. Native
category names are retained when that client exposes them. Bank scanning and
cross-character transfer compatibility remain unsupported or unverified on
the tested beta build.

Snapshots are stored locally in the account-wide `GamersTrackerForeverDB`
SavedVariables table. WoW serializes it on `/reload`, logout, clean exit, or
disconnect. Addons cannot perform arbitrary HTTP requests; future server sync
would require an explicit export after SavedVariables flush and a companion
desktop uploader, or another approved bridge.

## Install

Copy the [`GamersTrackerForever`](GamersTrackerForever) directory to:

```text
World of Warcraft\_classic_era_\Interface\AddOns\GamersTrackerForever\
```

For the Forever beta, use
`World of Warcraft\_classic_beta_\Interface\AddOns\GamersTrackerForever\`.

Enable **GamersTrackerForever** on the character-selection AddOns screen, then use
`/gtf` (with `/act` retained as a compatibility alias). See [installation and usage](docs/installation.md) for details.

## Repository layout

- [`GamersTrackerForever/`](GamersTrackerForever) — addon source and fixture harnesses.
- [`docs/specification.md`](docs/specification.md) — current product and
  implementation specification.
- [`docs/feasibility-research.md`](docs/feasibility-research.md) — WoW API and
  persistence feasibility research.
- [`docs/installation.md`](docs/installation.md) — installation, usage, data
  limitations, and validation status.
- [`docs/forever-beta-compatibility.md`](docs/forever-beta-compatibility.md) —
  local beta-client findings and release gates.
- [`docs/forever-beta-probe.md`](docs/forever-beta-probe.md) — safe in-client
  probe procedure.

## Current validation status

The manifest targets Classic Era/SoD interface `11509` and Forever beta
interface `16001`. Eleven Lua fixture harnesses and the SoD XML regression
pass locally. Forever beta recipe and bag snapshots have survived `/reload`
in live testing; full bank/transfer acceptance is still pending.
