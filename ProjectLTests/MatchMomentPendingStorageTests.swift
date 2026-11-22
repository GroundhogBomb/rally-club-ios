import Foundation
import GRDB
import Testing
@testable import ProjectL

@MainActor
struct MatchMomentPendingStorageTests {
    private let files = FileManager.default

    @Test func completeArchiveImportsPhotoAndKeepsExactBackup() throws {
        let fixture = try LegacyPendingPhotoFixture()
        defer { fixture.cleanup() }
        let ownerID = UUID(), photoID = UUID()
        let bytes = Data("[\(fixture.record(ownerID: ownerID, id: photoID, order: 3))]".utf8)
        try bytes.write(to: fixture.original(ownerID))

        let loaded = fixture.load(ownerID)
        let queue = try loaded.storage.get()
        let photo = try #require(loaded.pending[photoID])
        #expect(photo.data == Data([1, 2, 3]))
        #expect(photo.row.sort_order == 3)
        #expect(photo.row.language_code == "en")
        #expect(!files.fileExists(atPath: fixture.original(ownerID).path))
        #expect(try Data(contentsOf: fixture.backup(ownerID, complete: true)) == bytes)
        #expect(fixture.load(ownerID).pending[photoID]?.data == photo.data)
        let url = MatchMomentPendingStorage.databaseURL(directory: fixture.directory)
        #expect(try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
        #expect(try url.deletingLastPathComponent()
            .resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)

        try queue.remove(id: photoID)
        #expect(fixture.load(ownerID).pending.isEmpty)
    }

    @Test func committedImportIsNotRepeatedWhenBackupRenameMustRetry() throws {
        let fixture = try LegacyPendingPhotoFixture()
        defer { fixture.cleanup() }
        let ownerID = UUID(), photoID = UUID()
        let original = fixture.original(ownerID)
        let backup = fixture.backup(ownerID, complete: true)
        let bytes = Data("[\(fixture.record(ownerID: ownerID, id: photoID))]".utf8)
        let previousBackup = Data("Existing backup".utf8)
        try bytes.write(to: original)
        let database = try MatchMomentPendingStorage.openDatabase(directory: fixture.directory)
        try previousBackup.write(to: backup)

        #expect(throws: (any Error).self) { try fixture.load(ownerID).storage.get() }
        #expect(try Data(contentsOf: original) == bytes)
        #expect(try Data(contentsOf: backup) == previousBackup)
        #expect(try photoCount(in: database) == 1)

        try files.removeItem(at: backup)
        let retry = fixture.load(ownerID)
        _ = try retry.storage.get()
        #expect(Set(retry.pending.keys) == [photoID])
        #expect(try photoCount(in: database) == 1)
        #expect(try Data(contentsOf: backup) == bytes)
        #expect(!files.fileExists(atPath: original.path))
    }

    @Test func partialArchiveRecoversOnlyReadablePhotosForThatOwner() throws {
        let fixture = try LegacyPendingPhotoFixture()
        defer { fixture.cleanup() }
        let ownerID = UUID(), photoID = UUID(), otherOwner = UUID()
        let good = fixture.record(ownerID: ownerID, id: photoID)
        let foreign = fixture.record(ownerID: otherOwner, id: UUID())
        let bytes = Data("[null,\(good),\(foreign)]".utf8)
        try bytes.write(to: fixture.original(ownerID))

        let recovered = fixture.load(ownerID)
        _ = try recovered.storage.get()
        #expect(Set(recovered.pending.keys) == [photoID])
        #expect(recovered.pending[photoID]?.data == Data([1, 2, 3]))
        #expect(fixture.load(otherOwner).pending.isEmpty)
        #expect(try Data(contentsOf: fixture.backup(ownerID, complete: false)) == bytes)
        #expect(!files.fileExists(atPath: fixture.original(ownerID).path))
    }

    @Test func unreadableJSONIsRetainedBeforeTheEmptyQueueCanBeUsed() throws {
        let fixture = try LegacyPendingPhotoFixture()
        defer { fixture.cleanup() }
        let ownerID = UUID()
        let bytes = Data([0xFF, 0x00, 0xC0, 0xAF])
        try bytes.write(to: fixture.original(ownerID))

        let loaded = fixture.load(ownerID)
        let queue = try loaded.storage.get()
        #expect(loaded.pending.isEmpty)
        let photoID = UUID()
        let photo = try JSONDecoder().decode(
            PendingMatchMoment.self, from: Data(fixture.record(ownerID: ownerID, id: photoID).utf8))
        try queue.save(photo)
        #expect(Set(fixture.load(ownerID).pending.keys) == [photoID])
        #expect(try Data(contentsOf: fixture.backup(ownerID, complete: false)) == bytes)
    }

    @Test(arguments: [true, false])
    func transactionFailureKeepsLegacyBytesAndCanBeRetried(complete: Bool) throws {
        let fixture = try LegacyPendingPhotoFixture()
        defer { fixture.cleanup() }
        let ownerID = UUID(), firstID = UUID(), secondID = UUID()
        let first = fixture.record(ownerID: ownerID, id: firstID)
        let second = fixture.record(ownerID: ownerID, id: secondID, order: 1)
        let bytes = Data((complete ? "[\(first),\(second)]" : "[\(first),null,\(second)]").utf8)
        let original = fixture.original(ownerID)
        let backup = fixture.backup(ownerID, complete: complete)
        try bytes.write(to: original)
        let database = try MatchMomentPendingStorage.openDatabase(directory: fixture.directory)

        // Fail the final write after the photo inserts so the test exercises an actual rollback.
        try database.write { db in
            try db.execute(sql: """
                CREATE TRIGGER failReceipt BEFORE INSERT ON legacyArchive
                BEGIN SELECT RAISE(ABORT, 'test transaction failure'); END
                """)
        }
        #expect(throws: (any Error).self) { try fixture.load(ownerID).storage.get() }
        #expect(try photoCount(in: database) == 0)
        #expect(try Data(contentsOf: complete ? original : backup) == bytes)
        #expect(!files.fileExists(atPath: (complete ? backup : original).path))

        try database.write { db in
            try db.execute(sql: "DROP TRIGGER failReceipt")
        }
        let retried = fixture.load(ownerID)
        _ = try retried.storage.get()
        #expect(Set(retried.pending.keys) == [firstID, secondID])
        #expect(try photoCount(in: database) == 2)
        #expect(try Data(contentsOf: backup) == bytes)
    }

    @Test func unavailableDatabaseKeepsOriginalInPlace() throws {
        let fixture = try LegacyPendingPhotoFixture()
        defer { fixture.cleanup() }
        let ownerID = UUID(), photoID = UUID()
        let original = fixture.original(ownerID)
        let bytes = Data("[null,\(fixture.record(ownerID: ownerID, id: photoID))]".utf8)
        try bytes.write(to: original)
        try files.createDirectory(at: MatchMomentPendingStorage.databaseURL(directory: fixture.directory),
            withIntermediateDirectories: true)

        let blocked = fixture.load(ownerID)
        #expect(throws: (any Error).self) { try blocked.storage.get() }
        #expect(try Data(contentsOf: original) == bytes)
        #expect(!files.fileExists(atPath: fixture.backup(ownerID, complete: false).path))
    }

    @Test func existingUnreadableBackupPreventsOverwriteAndNewWrites() throws {
        let fixture = try LegacyPendingPhotoFixture()
        defer { fixture.cleanup() }
        let ownerID = UUID(), photoID = UUID()
        let original = fixture.original(ownerID)
        let backup = fixture.backup(ownerID, complete: false)
        let bytes = Data("[null,\(fixture.record(ownerID: ownerID, id: photoID))]".utf8)
        let previousBackup = Data("Retained bytes".utf8)
        let database = try MatchMomentPendingStorage.openDatabase(directory: fixture.directory)
        try previousBackup.write(to: backup)
        try bytes.write(to: original)

        let blocked = fixture.load(ownerID)
        #expect(throws: (any Error).self) { try blocked.storage.get() }
        #expect(blocked.pending[photoID]?.data == Data([1, 2, 3]))
        #expect(try photoCount(in: database) == 0)
        #expect(try Data(contentsOf: original) == bytes)
        #expect(try Data(contentsOf: backup) == previousBackup)
    }

    @Test func clearRemovesOnlyTheDeletedAccountsRowsAndArchives() throws {
        let fixture = try LegacyPendingPhotoFixture()
        defer { fixture.cleanup() }
        let ownerID = UUID(), otherOwner = UUID(), photoID = UUID()
        let first = Data("[\(fixture.record(ownerID: ownerID, id: photoID))]".utf8)
        let second = Data("[\(fixture.record(ownerID: otherOwner, id: photoID))]".utf8)
        try first.write(to: fixture.original(ownerID))
        try second.write(to: fixture.original(otherOwner))
        let queue = try fixture.load(ownerID).storage.get()
        _ = try fixture.load(otherOwner).storage.get()

        let historicalBackup = fixture.directory.appendingPathComponent("\(ownerID.uuidString).unreadable-1.json")
        try first.write(to: historicalBackup)
        try first.write(to: fixture.original(ownerID))

        MatchMomentPendingStorage.clear(ownerID: ownerID, directory: fixture.directory)
        try queue.remove(id: photoID) // Completion of an upload started before account deletion.
        #expect(fixture.load(ownerID).pending.isEmpty)
        #expect(!files.fileExists(atPath: historicalBackup.path))
        #expect(!files.fileExists(atPath: fixture.original(ownerID).path))
        #expect(!files.fileExists(atPath: fixture.backup(ownerID, complete: true).path))
        #expect(Set(fixture.load(otherOwner).pending.keys) == [photoID])
        #expect(try Data(contentsOf: fixture.backup(otherOwner, complete: true)) == second)
        let database = try MatchMomentPendingStorage.openDatabase(directory: fixture.directory)
        let receiptCount = try database.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM legacyArchive WHERE ownerID = ?",
                arguments: [ownerID.uuidString])
        }
        #expect(receiptCount == 0)
    }

    private func photoCount(in database: DatabaseQueue) throws -> Int {
        try database.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM pendingPhoto") ?? 0 }
    }
}
