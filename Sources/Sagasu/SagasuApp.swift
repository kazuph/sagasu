import AppKit

@main
enum SagasuApp {
    @MainActor
    private static let appDelegate = AppDelegate()

    @MainActor
    static func main() {
        let application = NSApplication.shared
        application.delegate = appDelegate
        appDelegate.start()
        application.finishLaunching()
        application.run()
    }
}
