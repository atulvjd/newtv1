import Foundation
import ImageIO
import Vision

public enum ScreenTextRecognition {
    /// Local OCR for bounded preview images. This function performs no capture or networking.
    public static func read(_ data: Data) throws -> String {
        guard !data.isEmpty, data.count <= 5_000_000,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              width.doubleValue > 0, height.doubleValue > 0, width.doubleValue * height.doubleValue <= 16_000_000,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw CommandError.invalid("Use a valid screen image under 5 MB and 16 megapixels.") }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        // CPU processing avoids accelerator-runtime failures on some macOS/device combinations.
        // Keep this compatible with the app's macOS 13 minimum.
        request.usesCPUOnly = true
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        return String(text.prefix(20000)) + (text.count > 20000 ? "\n[Text truncated at 20,000 characters.]" : "")
    }
}
