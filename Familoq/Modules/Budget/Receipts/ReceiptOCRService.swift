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

    static func recognize(_ original: UIImage, page: Int) async throws -> [OCRFragment] {
        // 48 MP photos from the library are far larger than a receipt needs;
        // text recognition on them uses a lot of memory.
        let image = downscaled(original, maxDimension: 3000)
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

    /// At most four languages: the iPhone's first two, then German and
    /// English. Every extra language loads another recognition model, and too
    /// many at once can exhaust the memory of the scanner on a real iPhone.
    /// Vision's automatic language detection covers the rest (Czech, Japanese …).
    static func preferredLanguages(supported: [String], preferred: [String] = Locale.preferredLanguages) -> [String] {
        let wanted = Array(preferred.prefix(2)) + ["de-DE", "en-US"]
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
        downscaled(image, maxDimension: maxDimension).jpegData(compressionQuality: 0.6)
    }

    /// Resized copy in real pixels (scale 1 - the default renderer would use
    /// the screen scale and create an image 3x larger than asked for).
    static func downscaled(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        let longest = max(pixelWidth, pixelHeight)
        guard longest > maxDimension else { return image }
        let factor = maxDimension / longest
        let target = CGSize(width: (pixelWidth * factor).rounded(), height: (pixelHeight * factor).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return autoreleasepool {
            UIGraphicsImageRenderer(size: target, format: format).image { _ in
                image.draw(in: CGRect(origin: .zero, size: target))
            }
        }
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
