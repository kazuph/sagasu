import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let coordinator = AppCoordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        terminateOtherSagasuInstances()
        coordinator.start(configuration: .current)
    }

    func applicationDidResignActive(_ notification: Notification) {
        coordinator.hideLauncher()
    }

    private func terminateOtherSagasuInstances() {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }

        let currentProcessID = ProcessInfo.processInfo.processIdentifier
        let otherInstances = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .filter { $0.processIdentifier != currentProcessID }

        for application in otherInstances {
            application.forceTerminate()
        }
    }
}
