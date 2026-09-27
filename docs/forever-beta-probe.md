# Forever beta compatibility probe

`BetaProbe.lua` is a read-only diagnostic component. It is loaded with the
addon but does nothing on Classic Era or Forever until `/gtf probe` is run.
The command reports the observed build/interface, scalar `WOW_PROJECT_*`
constants, product flavor hint, current character identity, profession and
trade-skill API results, aggregate bag slot/item counts, bank API availability,
and the account-wide SavedVariables product partitions. It intentionally does
not print item names or links, read bank contents, open protected frames, or
write/erase data. The report is evidence for compatibility work, not a support
claim based on the version number.

## Beta procedure

1. Copy the addon into the beta client's `Interface/AddOns` directory. Do not
   change the Classic Era installation while testing.
2. Log into a representative Forever character and run `/gtf probe`, then
   `/gtf status`. Save the chat output without adding account paths or item
   names to an issue report.
3. Run `/gtf probe` once while every profession window is closed. This records
   `C_TradeSkillUI` and related namespace/function availability, but does not
   call recipe-list methods. The report should say `window closed` (or
   `unknown` if this client exposes no detectable frame).
4. Open one profession normally, wait for its list to finish loading, and run
   `/gtf probe` again. The probe only observes the already-open UI; it does not
   open or close frames. When the frame is detectable as open it performs
   bounded aggregate checks of the current line and recipe-ID list shapes and
   counts, then samples no more than three numeric IDs for available recipe
   info/schematic calls. It reports aggregate call/error/table counts, learned
   true/false counts, numeric output/quantity-range availability, and reagent
   slot quantity/exact-item/ambiguous counts (at most 100 slots per sample).
   It discards recipe IDs, names, links, and raw reagent values and never
   writes data.
5. Repeat the open-window run for each profession type available to the
   character. Save the complete chat output for adapter work, including the
   `functions x/y`, `window`, line/list summaries, and modern recipe detail
   sample counts. These summaries are not enough to enable persistence: also
   establish that the learned flag distinguishes known and unknown recipes,
   the list covers all learned recipes rather than the active filter, and the
   detail fields provide complete output and reagent data.
   Then run `/gtf recipecheck` in that same open window. This separate,
   read-only diagnostic inspects at most 200 IDs from `GetAllRecipeIDs`,
   classifies only records whose returned recipe ID matches and whose
   `learned` field is a boolean, and prints at most two learned and two
   unlearned ID/name examples. If available, it also prints their profession
   IDs. Unlike the aggregate `/gtf probe`, these public recipe names and IDs
   are shown so they can be compared with the visible profession and
   Wowhead Forever `/spell=ID` pages. It does not save a recipe set.
6. Run the command once with the bank closed. If bank access is reported as
   unknown, open the bank normally and run it again. Bank slot contents are
   deliberately never read by the probe.
7. Use `/reload`, then a second character on the same account, and confirm the
   report shows the same account-wide SavedVariables root with separate product
   partitions. This validates persistence behavior; WoW still owns the actual
   SavedVariables file write at logout/reload.
8. Compare the beta report with the Classic Era report. A different interface,
   project ID, API shape, or partition result requires a dedicated adapter
   change and tests before claiming Forever support.

## What to send for a recipe adapter

Send the `/gtf probe` output from the closed-window run and from each open
profession run, plus `/gtf recipecheck` with the profession window open. The useful evidence is the client/build/interface line, the
`modern trade C_TradeSkillUI` availability line, the detected window state,
line/list counts, and detail sample aggregates. Do not send screenshots or logs
containing account paths, item names, or recipe links. These probe results
describe shapes only and do not authorize enabling recipe persistence.

The local beta install is identified by `.flavor.info` as
`wow_classic_beta`; that file does not prove the in-game API contract. The
runtime probe and an in-client run are required.

## Harness

From `GamersTrackerForever/`, run `tests/beta_probe_harness.lua` with the
supplied Fengari CLI. The fixture asserts that loading is inert, C_Container
bag aggregation is bounded, bank data is not scanned, and formatted output
contains no item names.
