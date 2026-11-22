# Pending match-photo queue migration

S4 moves pending match photos from per-account JSON archives to GRDB. This applies to the configured repository. Demo photos stay in memory.

## Files and ownership

The existing directory is `Application Support/MatchMomentUploads.v1/`. Legacy active files are named `<owner UUID>.json`. The new database lives in `GRDB.v1/match-moment-pending.v1.sqlite` beneath that directory. `DatabaseMigrator` creates the schema. Each photo is keyed by owner and photo ID. The stored metadata and the raw image bytes stay together in the same row.

The database uses complete file protection. The database file and its enclosing directory are excluded from backups. The protected directory also contains SQLite's rollback journal when a transaction is active. The source archive is moved within the same storage area, preserving its bytes and file attributes.

## First open for an account

1. Read the legacy JSON with the previous decoder, then open the database and apply the schema. The last occurrence of a repeated photo ID wins, and the English language code is applied as before.
2. If the entire archive is readable and belongs to this account, insert all photos and a receipt for the archive's SHA-256 in one transaction. After the transaction commits, rename the original to `GRDB.v1/<owner UUID>.migrated-<timestamp>.json`.
3. If some or all records are unreadable or belong to another account, first move the unchanged archive to `GRDB.v1/<owner UUID>.unreadable-<timestamp>.json`. Then commit only the valid, owned photos and the receipt in one transaction. An unreadable archive containing zero usable photos is still retained. If the move fails, the active file is left in place and the queue refuses writes.
4. The normal upload flow resumes once the queue is available. Each successful upload removes its own database row. Account deletion removes that owner's rows, receipt, active JSON and retained archives. Other accounts' files and rows are scoped separately.

## Failure and retry

A database-open failure leaves the original where it was. A failed transaction rolls back every insert and the receipt. A complete archive stays at its active path. A partial archive is already retained at its new path, and the next open retries from that archive. Backups from before S4 can contain previously processed photos, so the app only retries partial archives from the dedicated `GRDB.v1` directory.

A crash or rename failure after a complete archive commits leaves both the database receipt and the active file. On the next open the app compares the original with the receipt and retries only the rename. If the bytes differ or both an active file and a staged partial archive exist, the queue blocks writes and retains the files for review. Database or file access errors leave writes paused until the queue can open again. A failed local account cleanup is logged while sign-out follows the existing account deletion flow.

## Recovery and rollback

1. Close the app and make a protected copy of `MatchMomentUploads.v1/`, including any SQLite journal. Keep this copy outside version control and public folders.
2. For temporary access problems, restore access and reopen the app with the files in place. For a failed partial import, leave the retained file in `GRDB.v1/` so the app can retry it. For competing or changed archives, compare copies before restoring the intended source. Preserve the untouched originals.
3. A retained JSON file is a snapshot of the old queue at migration time. To return to an older build after uploads have resumed, recover the current pending rows from a readable copy of the database. Filter `pendingPhoto` by the owner's UUID and recreate the legacy JSON array with each decoded `metadata` value under `row` and each `imageData` value base64-encoded under `data`. Check the owner and photo count before atomically placing the result at the legacy active path. A previously uploaded or deleted photo can still be present in the old snapshot.
4. If the database cannot be read, keep both the database and the original archive. Use the retained JSON to identify recoverable old photos and confirm which still need uploading before creating a replacement queue. Photos added after migration may exist only in the database.

[GRDB 7.12.0 release](https://github.com/groue/GRDB.swift/releases/tag/v7.12.0)
