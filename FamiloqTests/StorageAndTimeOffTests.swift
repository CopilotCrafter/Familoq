import XCTest
import SwiftData
import UIKit
import FamiloqCore
import FamiloqPlanner
@testable import Familoq

@MainActor
final class StorageAndTimeOffTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var family: Family!

    override func setUp() async throws {
        container = try PersistenceController.makeContainer(inMemory: true)
        context = container.mainContext
        family = try FamilyBootstrapper.createFamily(named: "Test", ownerName: "Martin", in: context)
    }

    override func tearDown() async throws {
        family = nil; context = nil; container = nil
    }

    private func receipt(daysAgo: Int, photo: Bool = true, keep: Bool = false) -> ReceiptRecord {
        let r = ReceiptRecord(familyID: family.id, merchant: "REWE", date: Date().addingTimeInterval(-Double(daysAgo) * 86_400), total: 10, currencyCode: "EUR")
        if photo { r.syncImage = Data(repeating: 7, count: 150_000) }
        r.keepPhoto = keep
        context.insert(r)
        return r
    }

    func testPayloadWithoutPhotoFlagsIsUnchanged() {
        let r = receipt(daysAgo: 1)
        XCTAssertNil(r.syncPayload().values["keepPhoto"], "old records keep their fingerprint")
        XCTAssertNil(r.syncPayload().values["photoRevision"])
        r.keepPhoto = true
        r.photoRevision = 2
        let copy = ReceiptRecord(familyID: family.id, merchant: "", date: Date(), total: 0, currencyCode: "EUR")
        copy.applySyncPayload(r.syncPayload())
        XCTAssertTrue(copy.keepPhoto)
        XCTAssertEqual(copy.photoRevision, 2)
    }

    func testRetentionRemovesOnlyOldUnpinnedPhotos() throws {
        let old = receipt(daysAgo: 400)
        let pinned = receipt(daysAgo: 500, keep: true)
        let recent = receipt(daysAgo: 30)
        try context.save()
        let photos = PhotoStorage.photos(familyID: family.id, context: context)
        XCTAssertEqual(photos.count, 3)
        XCTAssertEqual(PhotoStorage.candidates(photos, retention: .forever).count, 0)
        XCTAssertEqual(PhotoStorage.candidates(photos, retention: .oneYear).map(\.id), [old.id])

        PhotoStorage.setRetention(.oneYear, familyID: family.id)
        let freed = PhotoStorage.applyRetention(familyID: family.id, context: context)
        XCTAssertEqual(freed, 150_000)
        XCTAssertNil(old.imageData)
        XCTAssertEqual(old.photoRevision, 1, "change is sent to iCloud")
        XCTAssertNotNil(pinned.imageData)
        XCTAssertNotNil(recent.imageData)
        PhotoStorage.setRetention(.forever, familyID: family.id)
    }

    func testGrayscaleStoragePhotoIsSmall() throws {
        let size = CGSize(width: 1200, height: 3000)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(origin: .zero, size: size))
            for i in 0..<60 {
                ("ARTIKEL \(i)   1,99 A" as NSString).draw(at: CGPoint(x: 60, y: 40 + i * 48),
                                                          withAttributes: [.font: UIFont.monospacedSystemFont(ofSize: 34, weight: .regular)])
            }
        }
        let data = try XCTUnwrap(ReceiptOCRService.storageJPEG(from: image))
        XCTAssertLessThan(data.count, 400_000)
        let stored = try XCTUnwrap(UIImage(data: data))
        XCTAssertLessThanOrEqual(max(stored.size.width, stored.size.height), 1600)
    }

    func testArchiveFilesAreCreated() throws {
        let r = receipt(daysAgo: 1, photo: false)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 400)).image { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 400))
        }
        r.syncImage = image.jpegData(compressionQuality: 0.5)
        try context.save()
        let photos = PhotoStorage.photos(familyID: family.id, context: context)
        let year = Calendar.current.component(.year, from: r.date)
        let pdf = try PhotoStorage.archive(photos, year: year, familyName: "Test", format: .pdf, context: context)
        let zip = try PhotoStorage.archive(photos, year: year, familyName: "Test", format: .zip, context: context)
        XCTAssertGreaterThan((try? Data(contentsOf: pdf))?.count ?? 0, 1_000)
        XCTAssertGreaterThan((try? Data(contentsOf: zip))?.count ?? 0, 100)
    }

    func testLeaveSyncRoundTripAndAllowanceID() {
        let member = UUID()
        let leave = LeaveEntry(familyID: family.id, memberID: member, type: .bridgeDay,
                               firstDay: Date(timeIntervalSince1970: 1_790_000_000), lastDay: Date(timeIntervalSince1970: 1_790_000_000))
        leave.note = "Brückentag"
        let copy = LeaveEntry(id: leave.id, familyID: family.id, memberID: UUID(), type: .vacation, firstDay: Date(), lastDay: Date())
        copy.applySyncPayload(leave.syncPayload())
        XCTAssertEqual(copy.syncPayload(), leave.syncPayload())
        XCTAssertEqual(copy.type, .bridgeDay)
        XCTAssertEqual(LeaveAllowance.allowanceID(familyID: family.id, memberID: member, year: 2026),
                       LeaveAllowance.allowanceID(familyID: family.id, memberID: member, year: 2026))
        let allowance = LeaveAllowance(id: UUID(), familyID: family.id, memberID: member, year: 2026, days: 30.5)
        XCTAssertEqual(allowance.days, 30.5)
    }
}
