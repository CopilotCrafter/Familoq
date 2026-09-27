import UIKit
import Vision
import VisionKit
import SwiftUI
import FamiloqBudget

/// On-device text recognition (Apple Vision). No image or text leaves the iPhone.
enum ReceiptOCRService {
    enum OCRError: LocalizedError {
        case unreadableImage
        case noText

        var errorDescription: String? {
            switch self {
            case .unreadableImage: return "The image could not be read."
            case .noText: return "No text was found. Try again with better light and the whole receipt in view."
            }
        }
    }

    /// Recognises all pages (a long receipt can be scanned in several parts).
    static func recognize(pages: [UIImage]) async throws -> [OCRFragment] {
        var all: [OCRFragment] = []
        for (index, image) in pages.enumerated() {
            all += try await recognize(image, page: index)
        }
        guard !all.isEmpty else { throw OCRError.noText }
        return all
    }

    static func recognize(_ image: UIImage, page: Int) async throws -> [OCRFragment] {
        guard let cgImage = image.cgImage else { throw OCRError.unreadableImage }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        return try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            // Prices and article abbreviations must not be "corrected".
            request.usesLanguageCorrection = false
            // Receipts can come from any country: let Vision detect the
            // script, preferring the iPhone's languages, then common ones.
            request.automaticallyDetectsLanguage = true
            request.recognitionLanguages = ReceiptOCRService.preferredLanguages(supported: (try? request.supportedRecognitionLanguages()) ?? [])
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
            try handler.perform([request])
            let observations = request.results ?? []
            return observations.compactMap { observation -> OCRFragment? in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                let box = observation.boundingBox // normalised, origin bottom-left
                return OCRFragment(
                    text: candidate.string,
                    x: Double(box.minX),
                    y: Double(1 - box.maxY),
                    width: Double(box.width),
                    height: Double(box.height),
                    confidence: Double(candidate.confidence),
                    page: page
                )
            }
        }.value
    }

    /// iPhone languages first, then German/English and other supported
    /// Latin-script languages. Vision's automatic detection handles
    /// Chinese, Japanese, Korean, Thai, Arabic, Cyrillic … on its own.
    static func preferredLanguages(supported: [String]) -> [String] {
        let wanted = Locale.preferredLanguages + ["de-DE", "en-US", "fr-FR", "it-IT", "es-ES", "pt-BR", "nl-NL", "pl-PL", "cs-CZ", "sv-SE", "da-DK", "nb-NO", "tr-TR"]
        var result: [String] = []
        for language in wanted {
            let prefix = String(language.prefix(2))
            if let match = supported.first(where: { $0 == language }) ?? supported.first(where: { $0.hasPrefix(prefix) }),
               !result.contains(match) {
                result.append(match)
            }
        }
        return result.isEmpty ? ["de-DE", "en-US"] : result
    }

    /// Smaller JPEG for storage (receipts are kept with the expense).
    static func storageJPEG(from image: UIImage, maxDimension: CGFloat = 1800) -> Data? {
        let size = image.size
        let scale = min(1, maxDimension / max(size.width, size.height))
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
        return resized.jpegData(compressionQuality: 0.6)
    }
}

extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}

/// VisionKit document camera (edge detection, perspective correction).
struct DocumentScannerView: UIViewControllerRepresentable {
    let onFinish: ([UIImage]) -> Void
    let onCancel: () -> Void

    static var isAvailable: Bool { VNDocumentCameraViewController.isSupported }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: DocumentScannerView
        init(parent: DocumentScannerView) { self.parent = parent }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            let pages = (0..<scan.pageCount).map { scan.imageOfPage(at: $0) }
            parent.onFinish(pages)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.onCancel()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            parent.onCancel()
        }
    }
}
