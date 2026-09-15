# GamersTrackerForever — Classic Era in-client acceptance checklist

Use on a disposable/test account in the Classic Era client. Do not run this checklist on a Forever beta client; Task 8 remains beta-gated.

## Load and persistence

- [ ] Install the folder at `World of Warcraft\_classic_era_\Interface\AddOns\GamersTrackerForever\`.
- [ ] Log in with character A and confirm `/gtf` opens the window; `/gtf` again toggles it closed. Confirm `/act` remains a working alias.
- [ ] Confirm `/gtf status` reports Classic adapter, interface/build, current key, and scan timestamps.
- [ ] Track A, `/reload`, and confirm tracking and window geometry survive.
- [ ] Log in with character B on the same realm; confirm A and B remain separate records.
- [ ] Log in with a same-named character on another realm; confirm no collision.

## Professions and recipes

- [ ] Confirm profession names/ranks appear after login; unopened professions show `never`/`recipe scan required`.
- [ ] Open each profession window and wait for the trade-skill update; confirm learned recipes and reagent quantities appear.
- [ ] Reopen/update after learning a recipe; confirm it is added without losing earlier recipes.
- [ ] Trigger an incomplete/closed trade-skill scan (close during update); confirm the previous valid learned set remains.

## Inventory and bank safety

- [ ] Add/remove/split/combine a bag stack and wait for `BAG_UPDATE_DELAYED`; confirm bag totals and timestamp update once.
- [ ] Open the bank and wait for bank contents to settle; confirm bank totals/timestamp update.
- [ ] Close the bank, then refresh the recipe panel; confirm last-known bank values remain and show their age.
- [ ] Log out away from the bank; confirm logout does not replace bank data with zero.

## Craftability and freshness

- [ ] Select a recipe whose materials are on the current character; `Available now` counts bags only (never bank).
- [ ] Put materials on a second compatible tracked character; `Available after transfer` includes bags + last-known bank.
- [ ] Verify every tracked character, including zero/missing scans, appears in the material matrix.
- [ ] Verify incompatible transfer groups remain visible but are excluded from pooled totals.
- [ ] Age a snapshot past the configured threshold; confirm `stale`/`very stale` is visible and never presented as silently current.
- [ ] Verify missing/inaccessible storage and special/tool/cooldown requirements show `unknown` or `special requirement`, never false `ready`.

## Controls and diagnostics

- [ ] Drag/resize the window, `/reload`, and confirm geometry is retained and clamped to safe minimums.
- [ ] Use `/gtf minimap off`, `/gtf minimap on`, and `/gtf minimap toggle`; confirm the setting and button visibility change. Repeat one command through `/act`.
- [ ] Use the key binding `Toggle GamersTrackerForever` and confirm it opens/toggles the same window.
- [ ] Confirm no protected action, item movement, external request, quest tracking, or forced reload occurs.
