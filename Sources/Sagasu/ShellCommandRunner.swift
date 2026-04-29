import Foundation

struct ShellCommandRunner {
    private final class DataCollector: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()

        func append(_ chunk: Data) {
            lock.lock()
            data.append(chunk)
            lock.unlock()
        }

        func snapshot() -> Data {
            lock.lock()
            defer { lock.unlock() }
            return data
        }
    }

    func run(executableURL: URL, arguments: [String]) throws -> String {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let outputData = DataCollector()
        let errorData = DataCollector()
        let outputGroup = DispatchGroup()
        let errorGroup = DispatchGroup()

        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        outputGroup.enter()
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                outputGroup.leave()
                return
            }
            outputData.append(chunk)
        }

        errorGroup.enter()
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                errorGroup.leave()
                return
            }
            errorData.append(chunk)
        }

        do {
            try process.run()
        } catch {
            throw LauncherError.commandFailed(executable: executableURL.path, message: error.localizedDescription)
        }

        process.waitUntilExit()
        outputGroup.wait()
        errorGroup.wait()

        let output = String(data: outputData.snapshot(), encoding: .utf8) ?? ""
        let errorOutput = String(data: errorData.snapshot(), encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            throw LauncherError.commandFailed(
                executable: executableURL.lastPathComponent,
                message: errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        return output
    }
}
