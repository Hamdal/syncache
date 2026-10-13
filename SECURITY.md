# Security Policy

## Supported versions

Only the latest published minor release line of each package receives
security fixes. Pre-1.0 releases (`0.x`) may receive fixes in new minor
versions rather than patches, following the release strategy in
`docs/milestones/README.md`.

| Package | Version |
|---------|---------|
| syncache | 0.5.x |
| syncache_flutter | 0.5.x |
| syncache_hive | 0.5.x |
| syncache_drift | 0.5.x |

## Reporting a vulnerability

**Do not open a public GitHub issue for security vulnerabilities.**

Report privately by opening a [security advisory](
https://github.com/Hamdal/syncache/security/advisories/new) on this
repository (recommended — it keeps the report private and lets us coordinate
a fix and credit), or contact the maintainers directly through the contact
information on the [repository](https://github.com/Hamdal/syncache).

Please include:

- the affected package(s) and version(s),
- a description of the issue and its impact,
- steps or a minimal reproduction,
- any suggested mitigation.

We aim to acknowledge reports within 7 days and will keep you informed
through assessment, fix, and release.

## Scope notes

Syncache is a client-side cache and sync engine. Points that would concern
us include, but are not limited to:

- **Data-at-rest handling** — cache entries and the mutation outbox are
  written to disk unencrypted by design (Hive box / SQLite database).
  Secrets placed in the cache are readable by anyone with device access;
  do not cache credentials or tokens unless your storage backend is
  encrypted.
- **Deserialization** — store values are decoded with caller-supplied
  `fromJson` codecs. A tampered database file can feed arbitrary JSON into
  those codecs; treat on-disk cache integrity as out of scope unless you
  provide it (e.g. SQLCipher or encrypted boxes).
- **Outbox replay** — recovery replays queued mutations after process
  death. Replay is not idempotent by default; the documented mitigation
  (client-generated operation ids, server-side deduplication) matters for
  correctness and abuse-resistance alike.

## Known non-features

- Syncache performs no server-side authorization and ships no network
  transport of its own — it calls the fetch/mutation closures you provide.
- No telemetry or analytics are collected by the packages.
