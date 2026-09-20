# Task 1 harness

`runtime_harness.lua` supplies the small subset of Classic API globals needed to load the scaffold, dispatch its lifecycle hooks, resolve a character key and transfer ecosystem, and exercise `/gtf status` plus the `/act` compatibility alias.

Run it with a Lua 5.1-compatible interpreter from the addon directory:

```text
lua tests/runtime_harness.lua
```

The harness intentionally does not test repository, scanner, catalog, craftability, or UI behavior; those belong to later work packages.

## Task 7 integration harness

`integration_harness.lua` exercises the complete Classic dependency graph,
login/entering-world scan de-duplication, bank preservation through close and
logout, slash/minimap settings, geometry normalization, and future-schema
read-only behavior. Run it with the same Lua 5.1-compatible interpreter when
one is available:

```text
lua tests/integration_harness.lua
```

For in-client verification, follow
`classic-era-acceptance-checklist.md` after installing the addon in Classic
Era.

The SoD-specific static check (`sod_static_regression.ps1`) verifies that the
special `Bindings.xml` is not listed in the TOC and uses `category` metadata.
The character/inventory harness also verifies that zero readable login slots
preserve the previous bag snapshot and that a bounded delayed retry commits a
later Hearthstone fixture. All harnesses are compatible with Lua 5.1 and the
supplied Fengari CLI.

The Forever beta probe harness (`beta_probe_harness.lua`) verifies inert load,
read-only C_Container aggregate probing, bank access detection without a bank
scan, product-partition inspection, and output redaction of item names.
It also verifies that a `1.60.x` beta build reusing project ID `2` is routed
to `unsupported:2`, selects no Classic scanner, and leaves the repository
read-only.

## Task 2 repository harness

`repository_harness.lua` exercises version-1 defaults, context-keyed product and character records, complete atomic snapshot commits, bank preservation when inaccessible, migrations, and valid/missing/corrupt fixture recovery.

Run it from the addon directory with:

```text
lua tests/repository_harness.lua
```
