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
   open or close frames. When the frame is detectable as open it performs only
   bounded aggregate checks of the current line and recipe-ID list return
   shapes/counts. It never calls recipe-detail, item-link, or reagent methods,
   and it never prints recipe/item names or IDs.
5. Repeat the open-window run for each profession type available to the
   character. Save the complete chat output for adapter work, including the
   `functions x/y`, `window`, `line`, and `recipe lists ok/count` lines.
   Those fields tell us which adapter calls are safe and whether a dedicated
   recipe adapter needs a line ID argument, a list-return API, or another
   client-specific surface.
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
profession run. The useful evidence is the client/build/interface line, the
`modern trade C_TradeSkillUI` availability line, the detected window state,
the line return-shape booleans, and the aggregate recipe-list counts. Do not
send screenshots or logs containing account paths, item names, or recipe
links. A dedicated adapter can be designed once we have the list return shape
and the exact availability of detail/link methods; the probe intentionally does
not invoke those methods because their returns can contain names and materials.

The local beta install is identified by `.flavor.info` as
`wow_classic_beta`; that file does not prove the in-game API contract. The
runtime probe and an in-client run are required.

## Harness

From `GamersTrackerForever/`, run `tests/beta_probe_harness.lua` with the
supplied Fengari CLI. The fixture asserts that loading is inert, C_Container
bag aggregation is bounded, bank data is not scanned, and formatted output
contains no item names.
