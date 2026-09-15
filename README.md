# GamersTrackerForever

GamersTrackerForever is a Classic Era MVP: an account-wide, last-known tracker
for character levels, professions,
learned recipes, bags, banks, and cross-character crafting materials.

The addon is informational. It does not move items, automate protected actions,
or contact an external service. Forever support is not claimed until its beta
client can be inspected and the compatibility gate in the specification passes.

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

## Current validation status

The manifest targets Classic Era interface `11509`, confirmed from the locally
installed client metadata. Static integration and package checks were completed.
The Lua fixture harnesses and in-client checklist are included, but neither was
executed in this environment because no standalone Lua runtime was available and
the game client was not launched.
