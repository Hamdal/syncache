# Changelog

## 0.6.0

### Changed

- `syncache` dependency constraint bumped to `^0.6.0` — released in
  lockstep with the core package (shared `TaggableStore` /
  `MutationOutbox` interfaces). No API changes in this package.

## 0.5.0

- Initial release: Drift (SQLite) storage backend for Syncache.
- `DriftStore<T>`: `TaggableStore` + `IterableStore` over a `cache` table
  with a relational `cache_tags` index (full tag lifecycle contract:
  plain write preserves tags, `writeWithTags` replaces them, delete/clear
  remove mappings) and glob (`*`/`?`) pattern operations.
- `DriftMutationOutbox`: `MutationOutbox` over a `mutation_outbox` table
  (INSERT OR REPLACE / DELETE BY id / DELETE FROM / SELECT ORDER BY seq),
  with `optimisticSnapshot` persistence and corrupted-row tolerance.
- Store and outbox share **one** database connection: `clear` never touches
  outbox records, and cache + outbox writes can run in one SQL transaction.
