import AppKit
import Darwin

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
            guard command.hasPrefix(executablePath) else { continue }
            kill(pid, SIGTERM)
        }
    }
}
