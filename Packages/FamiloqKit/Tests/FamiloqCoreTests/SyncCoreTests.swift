import XCTest
@testable import FamiloqCore

final class SyncCoreTests: XCTestCase {
    func testRecordNamesRoundTrip() {
        let id = UUID()
        for kind in SyncKind.allCases {
            let name = kind.recordName(for: id)
            let parsed = SyncKind.parse(recordName: name)
            XCTAssertEqual(parsed?.0, kind)
            XCTAssertEqual(parsed?.1, id)
        }
        XCTAssertNil(SyncKind.parse(recordName: "cloudkit.zoneshare"))
        XCTAssertNil(SyncKind.parse(recordName: "expense-not-a-uuid"))
    }

    func testZoneNames() {
        let id = UUID()
        XCTAssertEqual(SyncZone.familyID(fromZoneName: SyncZone.zoneName(for: id)), id)
        XCTAssertNil(SyncZone.familyID(fromZoneName: "_defaultZone"))
    }

    func testFingerprintIsStableAndSensitive() {
        let a = Data(#"{"amount":1}"#.utf8)
        let b = Data(#"{"amount":2}"#.utf8)
        XCTAssertEqual(SyncFingerprint.of(a), SyncFingerprint.of(a))
        XCTAssertNotEqual(SyncFingerprint.of(a), SyncFingerprint.of(b))
    }

    func testDiffFindsNewChangedAndDeleted() {
        let current = ["expense-1": "aa", "expense-2": "bb2", "expense-4": "dd"]
        let ledger = ["expense-1": "aa", "expense-2": "bb", "expense-3": "cc"]
        let diff = SyncDiff.compute(current: current, ledger: ledger)
        XCTAssertEqual(diff.changed, ["expense-2", "expense-4"])
        XCTAssertEqual(diff.deleted, ["expense-3"])
    }

    func testNothingChanged() {
        let same = ["a": "1", "b": "2"]
        XCTAssertEqual(SyncDiff.compute(current: same, ledger: same), SyncDiffResult(changed: [], deleted: []))
    }

    func testLastWriterWins() {
        let t = Date(timeIntervalSince1970: 1_000)
        XCTAssertTrue(SyncConflictResolver.serverWins(serverModifiedAt: t.addingTimeInterval(1), localChangedAt: t))
        XCTAssertFalse(SyncConflictResolver.serverWins(serverModifiedAt: t, localChangedAt: t.addingTimeInterval(1)))
        XCTAssertTrue(SyncConflictResolver.serverWins(serverModifiedAt: t, localChangedAt: nil))
        XCTAssertFalse(SyncConflictResolver.serverWins(serverModifiedAt: nil, localChangedAt: t))
    }
}
