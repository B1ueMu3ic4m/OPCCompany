<!-- Translated from HISTORY_ARCHIVE_RFC.md; the Chinese original remains authoritative for internal history. -->

# History Index & Archive RFC

Last updated: 2026-05-07

Current status: The SQLite history index and history archive migration are wired in as a local sidecar capability in the maintenance area. The main snapshot remains the authoritative state; the history database is a rebuildable index/archive that needs no Docker or external database, and is not a blocker for current single-user local formal use.

## Decision

OPC does not migrate the main state wholesale into a database at this point. The main snapshot remains the authoritative state; the local database serves only as a rebuildable sidecar history index and an archive table for old history.

Reasons:

- The main snapshot is convenient for local backups, safety checkpoints, and manual troubleshooting.
- The existing product-state structure is still evolving quickly; migrating main storage directly would amplify schema risk.
- The current pain point is retrieval and indexing, not transactional writes.
- If the local history index is corrupted, it can be rebuilt from the main snapshot without affecting main state.

## Current implementation

Maintenance audits or the explicit rebuild entry generate:

```text
~/Library/Application Support/OPCCompany/company-history.sqlite3
```

The index tables cover:

- Chat messages.
- Company events.
- Tasks.
- Employee work items.
- Approvals.
- Artifacts.
- Acceptance.
- Product memory.
- Communication logs.
- Acceptance gates.
- Employee collaboration messages.

Normal main-state saves do not trigger a synchronous full rebuild, so high-frequency state saves are not slowed down by the history index. The Terminal Hall maintenance area provides a "History Index Audit" for rebuilding the index, writing acceptance records, and reporting to the CTO.

## Current archive migration

The maintenance area provides a "History Archive Migration" entry. The current migration only copies old records past their retention period into local archive tables:

- Chat messages.
- Company events.
- Communication logs.
- Employee collaboration messages.

The current migration does not prune the main snapshot, delete local files, or start model tasks. If an archive table is corrupted it can still be rebuilt from the main snapshot; archive failure must not affect main-state saves.

## Future pruning triggers

Pruning archived old history from the main snapshot is only considered when any of the following holds:

- `company-state.json` exceeds 50 MB.
- App startup loads the snapshot in more than 1 second.
- The user needs cross-month/cross-product full-text search that the current index queries cannot satisfy.
- Safety checkpoints grow so large that they hurt rollback or backup experience.

## Archive principles

- The main snapshot keeps the most recent active state and recent records.
- Local archive tables hold old messages, old events, old communication logs, and old collaboration messages.
- Archives must be exportable, rebuildable, and deletable per product.
- Archive failure must not affect main-state saves.
