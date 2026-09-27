import XCTest
import SwiftUI
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

    /// The Czech receipt from the crash report (CZK total, paid in EUR),
    /// through OCR, parser, draft AND the check screen.
    func testCzechReceiptWithTwoCurrenciesAndCheckScreen() async throws {
        let image = render([
            "ASIA CENTER",
            "Horní Folmava 103",
            "34532 Česká Kubice",
            "IČ: 09497901 DIČ: CZ09497901",
            "Účtenka: P1/26/060769 27.09.2026 15:55:17",
            "Krevety vannamei 100/200 1kg 1x B 329.00",
            "Celkem:",
            "Total:              329.00 CZK",
            "Placeno:            13.80 EUR",
            "Vráceno:            20.00",
            "                    6.20",
            "Účtoval: Majitel",
            "Způsob platby: Hotovost",
            "[Rozpis DPH]",
            "Sazba Celkem DPH Základ",
            "B 12% 329.00 35.25 293.75",
            "Zboží lze vyměnit do 14 dnů s účtenkou."
        ], size: CGSize(width: 1100, height: 1300))
        let container = try PersistenceController.makeContainer(inMemory: true)
        let context = container.mainContext
        let family = try FamilyBootstrapper.createFamily(named: "Test", ownerName: "Me", in: context)
        let repo = FamilyRepository(context: context, familyID: family.id)
        let fragments = try await ReceiptOCRService.recognize(pages: [image])
        let lines = ReceiptLineAssembler.lines(from: fragments)
        print("OCR lines:", lines)
        let parsed = ReceiptParser.parse(lines: lines)
        var draft = ReceiptDrafting.draft(from: parsed, family: family,
                                          lookup: CategoryLookup(categories: try repo.categories(), subcategories: try repo.subcategories()),
                                          rules: try repo.merchantRules(), imageData: ReceiptOCRService.storageJPEG(from: image))
        print("Currency:", draft.currencyCode, draft.currencyConfirmed, draft.currencyCandidates, "total:", draft.totalText, "items:", draft.items.map(\.name))

        // Render the check screen like the app does.
        let session = AppSession()
        session.start(context: context)
        let binding = Binding(get: { draft }, set: { draft = $0 })
        let view = NavigationStack {
            ReceiptReviewView(family: family, draft: binding, onDone: {})
        }
        .environmentObject(session)
        .environmentObject(ExchangeRateService())
        .modelContainer(container)
        let host = UIHostingController(rootView: view)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(500))
        host.view.layoutIfNeeded()

        // Choose a currency as the user would.
        let lookup = CategoryLookup(categories: try repo.categories(), subcategories: try repo.subcategories())
        ReceiptDrafting.applyCurrency("CZK", to: &draft, lookup: lookup)
        XCTAssertTrue(draft.currencyConfirmed)
        host.view.layoutIfNeeded()
        let saved = try ReceiptSaver.save(draft, family: family, member: session.currentMember, lookup: lookup, context: context)
        XCTAssertFalse(saved.isEmpty)
    }

    /// Camera-sized photo (12 MP) as the document scanner delivers it.
    func testLargePhotoEndToEnd() async throws {
        let image = render(["LIDL", "Bananen 2,20 A", "zu zahlen 2,20"], size: CGSize(width: 3024, height: 4032))
        let result = try await makeDraft(from: image)
        XCTAssertNotNil(result.draft.imageData)
    }
}

/// Which language lists Vision accepts together (an iPhone's language
/// settings decide what Familoq asks for).
final class VisionLanguageComboTests: XCTestCase {
    private func run(_ languages: [String], on image: CGImage) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.automaticallyDetectsLanguage = true
        request.recognitionLanguages = languages
        do {
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
            return "ok (\(request.results?.count ?? 0) texts)"
        } catch {
            return "ERROR \(error.localizedDescription)"
        }
    }

    func testLanguageCombinations() throws {
        let size = CGSize(width: 600, height: 200)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(origin: .zero, size: size))
            ("Bananen 2,20 A" as NSString).draw(at: CGPoint(x: 20, y: 60), withAttributes: [.font: UIFont.systemFont(ofSize: 40)])
        }.cgImage!
        let supported = try VNRecognizeTextRequest().supportedRecognitionLanguages()
        var report: [String] = []
        for language in supported {
            report.append("\(language): \(run(["de-DE", "en-US", language], on: image)) / first: \(run([language, "de-DE", "en-US"], on: image))")
        }
        report.append("ALL: \(run(supported, on: image))")
        let familoq = ReceiptOCRService.preferredLanguages(supported: supported)
        report.append("Familoq list \(familoq): \(run(familoq, on: image))")
        let failures = report.filter { $0.contains("ERROR") }
        // Visible as a CI annotation.
        XCTAssertTrue(failures.isEmpty, "Vision rejected: " + failures.joined(separator: " | "))
        print(report.joined(separator: "\n"))
    }
}
