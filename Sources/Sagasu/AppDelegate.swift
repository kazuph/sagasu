import AppKit
import Darwin

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let coordinator = AppCoordinator()
    private var didStart = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        start()
    }

    func start() {
        guard didStart == false else { return }
        didStart = true
        terminateOtherSagasuInstances()
        coordinator.start(configuration: .current)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard coordinator.isQuitRequested else {
            coordinator.hideLauncher()
            return .terminateCancel
        }

        return .terminateNow
    }

    func applicationDidResignActive(_ notification: Notification) {
        guard coordinator.shouldHideLauncherOnApplicationResignActive else { return }
        coordinator.hideLauncher()
    }

    private func terminateOtherSagasuInstances() {
        let currentProcessID = ProcessInfo.processInfo.processIdentifier
        let executablePath = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.path
        let output: String

        do {
            output = try ShellCommandRunner().run(
                executableURL: URL(fileURLWithPath: "/bin/ps"),
                arguments: ["-axo", "pid=,command="]
            )
        } catch {
            return
        }

        for line in output.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.isEmpty == false else { continue }

            let components = trimmed.split(maxSplits: 1, whereSeparator: \.isWhitespace)
            guard components.count == 2,
                  let pid = Int32(components[0]),
                  pid != currentProcessID else {
                continue
            }

            let command = String(components[1])
            let commandExecutablePath = command.split(maxSplits: 1, whereSeparator: \.isWhitespace).first.map(String.init) ?? command
            guard commandExecutablePath.hasSuffix("/Sagasu.app/Contents/MacOS/Sagasu"),
                  commandExecutablePath != executablePath else {
                continue
            }
            kill(pid, SIGTERM)
        }
    }
}
