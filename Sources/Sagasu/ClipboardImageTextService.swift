import AppKit
import Foundation
import Vision

struct ClipboardImageTextService {
    struct ExtractionResult {
        let savedImageURL: URL
        let recognizedText: String
    }

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
    func searchResult(query: String) -> SearchResult? {
        guard hasClipboardImage else { return nil }

        let title = "Image: Save Clipboard Image and Extract Text"
        let metadata = "image ocr text extract save png downloads clipboard"
        let normalizedQuery = SearchMatcher.normalize(query)
        if normalizedQuery.isEmpty == false,
           SearchMatcher.score(
            query: normalizedQuery,
            primaryText: SearchMatcher.normalize(title),
            secondaryText: metadata
           ) == nil {
            return nil
        }

        return SearchResult(
            title: title,
            subtitle: "Save PNG to Downloads and add recognized text to clipboard history",
            detail: "~/Downloads",
            visual: .symbol("text.viewfinder"),
            action: .saveClipboardImageAndExtractText
        )
    }

    @MainActor
    func saveImageAndExtractText() async throws -> ExtractionResult {
        guard let image = pasteboard.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage,
              let pngData = image.pngData(),
              let bitmap = NSBitmapImageRep(data: pngData),
              let cgImage = bitmap.cgImage else {
            throw LauncherError.clipboardImageMissing
        }

        let savedURL = try savePNG(pngData)
        let text = try await Self.recognizedText(from: cgImage)
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedText.isEmpty == false else {
            throw LauncherError.clipboardImageTextNotFound
        }

        return ExtractionResult(savedImageURL: savedURL, recognizedText: trimmedText)
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
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US", "ja-JP"]

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
