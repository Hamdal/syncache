# Contributing to Syncache

Thanks for your interest in contributing! This document covers the monorepo
layout, the development workflow, and the project's conventions.

## Repository layout

| Path | Purpose |
|------|---------|
| `packages/syncache` | Core cache/sync engine (pure Dart) |
| `packages/syncache_flutter` | Flutter integration (widgets, lifecycle, connectivity) |
| `packages/syncache_hive` | Hive (`hive_ce`) storage backend |
| `packages/syncache_drift` | SQLite (Drift) storage backend |
| `docs/milestones/` | The implementation roadmap; each milestone is a self-contained brief |
| `tool/` | Repo-level developer tooling |

## Setup

The repo is managed with [melos](https://pub.dev/packages/melos):

```bash
dart pub global activate melos
melos bootstrap
```

## Common commands

```bash
melos run format        # dart format everything
melos run format:check  # CI-style format check
melos run analyze       # dart analyze / flutter analyze per package
melos run test          # tests for all pure-Dart packages
melos run test:all      # tests for every package (incl. Flutter)
```

Running a single package's tests:

```bash
cd packages/syncache && dart test
cd packages/syncache_flutter && flutter test
```

## Milestone workflow

Feature work is organized in `docs/milestones/`. Pick a milestone brief,
work through its task list, and tick the checkboxes in the brief plus the
status table in `docs/milestones/README.md` as work completes so the next
session can resume cleanly. Milestones map to releases (one release per
milestone) — see the release strategy section in
[docs/milestones/README.md](docs/milestones/README.md).

## Pull requests

1. Create a feature branch.
2. Make your change with tests. Bug fixes need a regression test; new APIs
   need coverage for the documented behavior (including edge cases).
3. Run the full local gate:

   ```bash
   melos run format:check
   melos run analyze
   melos run test:all
   dart run tool/validate_readme_samples.dart
   ```

4. Update the affected packages' `CHANGELOG.md` (Keep-a-Changelog format;
   explicit **BREAKING** section when applicable) and bump versions in
   lockstep across packages that share interfaces.
5. Update READMEs/doc comments — see the code-sample convention below.
6. Keep commit messages and PR titles/bodies about the change itself and
   its public versioning. Internal planning notes (the local `docs/` tree,
   milestones, workstream labels) never appear in git history or PR text —
   they are deliberately untracked.

## Code-sample convention (READMEs and doc comments)

Every ` ```dart ` block in any README is **mechanically validated** by
`tool/validate_readme_samples.dart` (also run in CI). Two block shapes are
valid:

- **Complete sample** — the block starts with `import`. It is analyzed
  verbatim and must define everything it uses (including stub types like
  `User`/`api` where needed for brevity).
- **Fragment** — any other block. It must be pure statements (no top-level
  declarations) and may rely on the small stub set the validator injects for
  that package's README (e.g. `User`, `api`, `fetchUser`, `cache`). If you
  need a new stub, add it to the package's preamble in the validator script
  rather than working around it.

Blocks that are signature sketches or pseudo-code should use a ` ```text `
fence instead so they are not analyzed as Dart.

## Backend package rules

Storage backend packages (`syncache_hive`, `syncache_drift`) must:

- depend on `syncache` only (never on each other, never on `hive`/`hive_ce`
  from the drift side or `drift` from the Hive side),
- pass the shared `TaggableStore` conformance suite
  (`packages/syncache/test/taggable_store_conformance.dart`, imported via
  relative path, canonical copy lives in the core package),
- preserve the documented tag lifecycle contract: plain `write` preserves
  tags, `writeWithTags` replaces them, `delete`/`clear` remove them.

## Release checklist

Per-package releases follow the checklist in
`docs/milestones/README.md` (changelog, lockstep versions, format/analyze
green, tests green, `dart pub publish --dry-run` clean).

## License

By contributing, you agree that your contributions will be licensed under
the MIT License found in [LICENSE](LICENSE).
