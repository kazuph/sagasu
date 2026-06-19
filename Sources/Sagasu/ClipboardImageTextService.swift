import AppKit
import Foundation
import Vision

struct ClipboardImageTextService {
    static let textRecognitionRevision = VNRecognizeTextRequestRevision3
    static let textRecognitionLanguages = ["ja-JP", "en-US"]

    private let pasteboard: NSPasteboard
    private let fileManager: FileManager

    init(
        pasteboard: NSPasteboard = .general,
        fileManager: FileManager = .default
    ) {
        self.pasteboard = pasteboard
        self.fileManager = fileManager
    }

    @MainActor
    func searchResults(query: String) -> [SearchResult] {
        guard hasClipboardImage else { return [] }

        let normalizedQuery = SearchMatcher.normalize(query)
        return [
            SearchResult(
                title: "Image: Save Clipboard Image",
                subtitle: "Save PNG to Downloads",
                detail: "~/Downloads",
                visual: .symbol("square.and.arrow.down"),
                action: .saveClipboardImage
            ),
            SearchResult(
                title: "Image: Extract Text from Clipboard Image",
                subtitle: "Copy recognized text and add it to clipboard history",
                detail: "OCR clipboard image",
                visual: .symbol("text.viewfinder"),
                action: .extractTextFromClipboardImage
            )
        ].filter { result in
            normalizedQuery.isEmpty || SearchMatcher.score(
                query: normalizedQuery,
                primaryText: SearchMatcher.normalize(result.title),
                secondaryText: SearchMatcher.normalize([result.subtitle, result.detail, "image ocr text extract save png downloads clipboard"].joined(separator: " "))
            ) != nil
        }
    }

    @MainActor
    func saveClipboardImage() throws -> URL {
        let image = try readClipboardImage()
        return try savePNG(image.pngData)
    }

    @MainActor
    func extractTextFromClipboardImage() async throws -> String {
        let image = try readClipboardImage()
        let text = try await Self.recognizedText(from: image.cgImage)
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedText.isEmpty == false else {
            throw LauncherError.clipboardImageTextNotFound
        }
        return trimmedText
    }

    @MainActor
    private func readClipboardImage() throws -> (pngData: Data, cgImage: CGImage) {
        guard let image = pasteboard.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage,
              let pngData = image.pngData(),
              let bitmap = NSBitmapImageRep(data: pngData),
              let cgImage = bitmap.cgImage else {
            throw LauncherError.clipboardImageMissing
        }

        return (pngData, cgImage)
    }

    @MainActor
    private var hasClipboardImage: Bool {
        pasteboard.canReadObject(forClasses: [NSImage.self], options: nil)
    }

    private func savePNG(_ data: Data) throws -> URL {
        let downloadsURL = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appending(path: "Downloads", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: downloadsURL, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let filename = "Sagasu-Clipboard-Image-\(formatter.string(from: Date())).png"
        let fileURL = downloadsURL.appending(path: filename)
        try data.write(to: fileURL, options: [.atomic])
        return fileURL
    }

    private static func recognizedText(from image: CGImage) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.revision = textRecognitionRevision
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = textRecognitionLanguages

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            try handler.perform([request])

            let lines = request.results?
                .compactMap { $0.topCandidates(1).first?.string }
                .filter { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false } ?? []
            return lines.joined(separator: "\n")
        }.value
    }
}

private extension NSImage {
    func pngData() -> Data? {
        guard let tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffRepresentation) else {
            return nil
        }

        return bitmap.representation(using: .png, properties: [:])
    }
}
