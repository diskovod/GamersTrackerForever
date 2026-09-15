# Task 1 harness

`runtime_harness.lua` supplies the small subset of Classic API globals needed to load the scaffold, dispatch its lifecycle hooks, resolve a character key and transfer ecosystem, and exercise `/act status`.

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

## Task 2 repository harness

`repository_harness.lua` exercises version-1 defaults, context-keyed product and character records, complete atomic snapshot commits, bank preservation when inaccessible, migrations, and valid/missing/corrupt fixture recovery.

Run it from the addon directory with:

```text
lua tests/repository_harness.lua
```
