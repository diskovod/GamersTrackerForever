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
3. Repeat after opening each profession UI. The probe only observes the
   resulting trade-skill API state; it does not open the UI for you.
4. Run the command once with the bank closed. If bank access is reported as
   unknown, open the bank normally and run it again. Bank slot contents are
   deliberately never read by the probe.
5. Use `/reload`, then a second character on the same account, and confirm the
   report shows the same account-wide SavedVariables root with separate product
   partitions. This validates persistence behavior; WoW still owns the actual
   SavedVariables file write at logout/reload.
6. Compare the beta report with the Classic Era report. A different interface,
   project ID, API shape, or partition result requires a dedicated adapter
   change and tests before claiming Forever support.

The local beta install is identified by `.flavor.info` as
`wow_classic_beta`; that file does not prove the in-game API contract. The
runtime probe and an in-client run are required.

## Harness

From `GamersTrackerForever/`, run `tests/beta_probe_harness.lua` with the
supplied Fengari CLI. The fixture asserts that loading is inert, C_Container
bag aggregation is bounded, bank data is not scanned, and formatted output
contains no item names.
