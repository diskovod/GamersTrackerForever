# GamersTrackerForever

GamersTrackerForever is a Classic Era MVP: an account-wide, last-known tracker
for character levels, professions,
learned recipes, bags, banks, and cross-character crafting materials.

The interface uses only native Classic/Season of Discovery Blizzard Lua frames
and XML bindings; HTML, CSS, and JavaScript are not available to WoW addons.
The main window has a persistent character selector on the left and a larger
overview/recipes pane on the right. Its `Track up to` control supports 1–10
characters (default 3) and never silently untracks existing characters.

The addon is informational. It does not move items, automate protected actions,
or contact an external service. The installed Forever beta has been identified
as `wow_classic_beta` build `1.60.1.69913`; it remains diagnostic-only until
`/gtf probe` supplies the runtime interface and API evidence required by the
compatibility gate.

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

Enable **GamersTrackerForever** on the character-selection AddOns screen, then use
`/gtf` (with `/act` retained as a compatibility alias). See [installation and usage](docs/installation.md) for details.

## Repository layout

- [`GamersTrackerForever/`](GamersTrackerForever) — addon source and fixture harnesses.
- [`docs/specification.md`](docs/specification.md) — finalized product and
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

The supported manifest targets Classic Era/SoD interface `11509`, confirmed
from the locally installed client metadata. All eight Lua fixture harnesses,
the SoD XML regression, and diff validation pass locally. In-client acceptance
still requires launching the relevant game client; the Forever beta is not yet
declared compatible.
