import XCTest
import BucketeerCore

final class EncryptionKeyReassignmentTests: XCTestCase {
    func testReassignmentPreservesKeyAndRefusesOccupiedBucket() async throws {
        let store = InMemoryEncryptionKeyStore()
        let source = await store.create(label: "Archive", accountID: UUID(), bucket: "photos")
        let targetID = UUID()
        let occupied = await store.create(label: "Existing", accountID: targetID, bucket: source.bucket)
        let originalBytes = try await store.keyMaterial(id: source.id)

        do {
            _ = try await store.reassign(source, to: targetID)
            XCTFail("An existing bucket key must never be overwritten")
        } catch EncryptionKeyReassignmentError.conflict {}
        let unchanged = await store.all()
        XCTAssertEqual(Set(unchanged), Set([source, occupied]))

        try await store.delete(id: occupied.id)
        await store.failNextLookups(1)
        do {
            _ = try await store.reassign(source, to: targetID)
            XCTFail("A failed verification read must roll back the replacement")
        } catch let error as CocoaError {
            XCTAssertEqual(error.code, .fileReadNoPermission)
        }
        let rolledBack = await store.all()
        XCTAssertEqual(rolledBack, [source])
        let preservedBytes = try await store.keyMaterial(id: source.id)
        XCTAssertEqual(preservedBytes, originalBytes)

        await store.failNextLookups(1)
        await store.failNextDeletes(1)
        do {
            _ = try await store.reassign(source, to: targetID)
            XCTFail("A failed rollback must report the leftover destination entry")
        } catch EncryptionKeyReassignmentError.rollbackFailed {}
        let afterFailedRollback = await store.all()
        let staleCopy = try XCTUnwrap(afterFailedRollback.first { $0.accountID == targetID })
        let sourceBytes = try await store.keyMaterial(id: source.id)
        XCTAssertEqual(sourceBytes, originalBytes)
        do {
            _ = try await store.keyMaterial(id: staleCopy.id)
            XCTFail("A stale destination entry must not supply key bytes")
        } catch EncryptionError.noKeyForBucket {}
        try await store.delete(id: staleCopy.id)

        await store.failNextDeletes(1)
        do {
            _ = try await store.reassign(source, to: targetID)
            XCTFail("A failed source cleanup must preserve the verified destination")
        } catch EncryptionKeyReassignmentError.sourceCleanupFailed {}
        let verifiedCopy = try await store.key(accountID: targetID, bucket: source.bucket)
        let moved = try XCTUnwrap(verifiedCopy)
        let verifiedBytes = try await store.keyMaterial(id: moved.id)
        XCTAssertEqual(verifiedBytes, originalBytes)
        try await store.delete(id: source.id)
        let remaining = await store.all()
        let movedBytes = try await store.keyMaterial(id: moved.id)
        XCTAssertEqual(remaining, [moved])
        XCTAssertNotEqual(moved.id, source.id)
        XCTAssertEqual(moved.accountID, targetID)
        XCTAssertEqual(moved.bucket, source.bucket)
        XCTAssertEqual(moved.label, source.label)
        XCTAssertEqual(moved.createdAt, source.createdAt)
        XCTAssertEqual(movedBytes, originalBytes)
        let oldLookup = try await store.key(accountID: source.accountID, bucket: source.bucket)
        XCTAssertNil(oldLookup)
        do {
            _ = try await store.keyMaterial(id: source.id)
            XCTFail("The old key entry must be removed after verification")
        } catch EncryptionError.noKeyForBucket {}

        let returned = try await store.reassign(moved, to: source.accountID)
        let returnedBytes = try await store.keyMaterial(id: returned.id)
        let finalKeys = await store.all()
        XCTAssertEqual(returnedBytes, originalBytes)
        XCTAssertEqual(finalKeys, [returned])
    }
}
