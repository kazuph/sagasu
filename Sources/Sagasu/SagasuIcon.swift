import AppKit

enum SagasuIcon {
    static func appIcon() -> NSImage {
        if let url = Bundle.main.url(forResource: "SagasuIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: url) {
            return image
        }

        return NSImage(size: NSSize(width: 512, height: 512))
    }
}
