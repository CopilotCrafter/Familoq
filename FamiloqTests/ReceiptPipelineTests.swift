import XCTest
import SwiftData
import UIKit
import Vision
import FamiloqCore
import FamiloqBudget
@testable import Familoq

/// The whole "Scan" path on the simulator: rendered receipt image -> Vision OCR
/// (same settings as on the iPhone) -> line assembly -> parser -> review draft.
@MainActor
final class ReceiptPipelineTests: XCTestCase {
    private func render(_ lines: [String], size: CGSize = CGSize(width: 900, height: 1400)) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 36, weight: .medium),
                .foregroundColor: UIColor.black
            ]
            for (index, line) in lines.enumerated() {
                (line as NSString).draw(at: CGPoint(x: 40, y: 40 + CGFloat(index) * 60), withAttributes: attributes)
            }
        }
    }

    private func makeDraft(from image: UIImage) async throws -> (lines: [String], draft: ReceiptDraft) {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let context = container.mainContext
        let family = try FamilyBootstrapper.createFamily(named: "Test", ownerName: "Me", in: context)
        let repo = FamilyRepository(context: context, familyID: family.id)
        let fragments = try await ReceiptOCRService.recognize(pages: [image])
        let lines = ReceiptLineAssembler.lines(from: fragments)
        print("OCR lines:", lines)
        let parsed = ReceiptParser.parse(lines: lines)
        let draft = ReceiptDrafting.draft(from: parsed, family: family,
                                          lookup: CategoryLookup(categories: try repo.categories(), subcategories: try repo.subcategories()),
                                          rules: try repo.merchantRules(), imageData: ReceiptOCRService.storageJPEG(from: image))
        return (lines, draft)
    }

    func testOCRLanguageSettingsAreAccepted() throws {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        let supported = try request.supportedRecognitionLanguages()
        print("Vision supports:", supported)
        let chosen = ReceiptOCRService.preferredLanguages(supported: supported)
        print("Familoq uses:", chosen)
        XCTAssertFalse(chosen.isEmpty)
        XCTAssertTrue(chosen.allSatisfy { supported.contains($0) })
    }

    func testGermanReceiptEndToEnd() async throws {
        let image = render([
            "REWE Markt GmbH",
            "Hauptstr. 5",
            "93413 Cham",
            "EUR",
            "BANANEN            1,99 B",
            "VOLLMILCH          1,19 B",
            "BROT               2,49 B",
            "SUMME EUR          5,67",
            "27.09.2026 10:15"
        ])
        let result = try await makeDraft(from: image)
        XCTAssertFalse(result.lines.isEmpty)
        XCTAssertEqual(result.draft.currencyCode, "EUR")
    }

    func testForeignReceiptEndToEnd() async throws {
        let image = render([
            "CORNER STORE",
            "09/25/2026 3:45 PM",
            "Apples            $3.20",
            "Chicken breast    $7.99",
            "TOTAL            $11.19"
        ])
        let result = try await makeDraft(from: image)
        XCTAssertFalse(result.lines.isEmpty)
    }

    /// Camera-sized photo (12 MP) as the document scanner delivers it.
    func testLargePhotoEndToEnd() async throws {
        let image = render(["LIDL", "Bananen 2,20 A", "zu zahlen 2,20"], size: CGSize(width: 3024, height: 4032))
        let result = try await makeDraft(from: image)
        XCTAssertNotNil(result.draft.imageData)
    }
}
