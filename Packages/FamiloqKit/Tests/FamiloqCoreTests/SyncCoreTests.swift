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

    // MARK: Payload

    func testPayloadRoundTripKeepsValuesAndFingerprint() {
        let date = Date(timeIntervalSince1970: 1_791_000_000.123_456)
        let id = UUID()
        var p = SyncPayload()
        p.set("name", "Martin & Carol")
        p.set("amount", Int64(123_4500))
        p.set("base", Int64?.none)
        p.set("order", 3)
        p.set("active", true)
        p.set("category", id)
        p.set("sub", UUID?.none)
        p.set("date", date)

        let back = SyncPayload(json: p.jsonString)
        XCTAssertEqual(back, p)
        XCTAssertEqual(back?.fingerprint, p.fingerprint)
        XCTAssertEqual(back?.string("name"), "Martin & Carol")
        XCTAssertEqual(back?.int64("amount"), 1_234_500)
        XCTAssertNil(back?.optionalInt64("base"))
        XCTAssertEqual(back?.int("order"), 3)
        XCTAssertEqual(back?.bool("active"), true)
        XCTAssertEqual(back?.uuid("category"), id)
        XCTAssertNil(back?.uuid("sub"))
        XCTAssertEqual(back?.date("date"), SyncPayload.roundTripped(date))
    }

    func testDateSurvivesRepeatedRoundTrips() {
        let date = Date(timeIntervalSince1970: 1_791_000_000.987_654_3)
        var a = SyncPayload()
        a.set("d", date)
        var b = SyncPayload()
        b.set("d", a.date("d")!)
        XCTAssertEqual(a.fingerprint, b.fingerprint, "re-encoding a received date must not look like a change")
    }

    func testPayloadIsOrderIndependent() {
        var a = SyncPayload()
        a.set("x", "1")
        a.set("y", "2")
        var b = SyncPayload()
        b.set("y", "2")
        b.set("x", "1")
        XCTAssertEqual(a.jsonString, b.jsonString)
    }

    func testDefaultsForMissingKeys() {
        let p = SyncPayload()
        XCTAssertEqual(p.string("missing", default: "EUR"), "EUR")
        XCTAssertEqual(p.int("missing", default: 6), 6)
        XCTAssertTrue(p.bool("missing", default: true))
        XCTAssertNil(SyncPayload(json: "not json"))
    }
}
