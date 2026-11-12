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

        await store.delete(id: occupied.id)
        let moved = try await store.reassign(source, to: targetID)
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
    }
}
