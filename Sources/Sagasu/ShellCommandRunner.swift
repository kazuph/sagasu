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

extension ShellCommandRunner {
    struct LineStreamResult: Equatable {
        /// ハンドラが止めた、または時間切れで途中終了した。
        var stoppedEarly: Bool
        var timedOut: Bool
    }

    /// 標準出力を1行ずつ読み、行ごとに handler を呼ぶ。handler が false を返す、時間の上限を超える、
    /// Task が取り消される、のいずれかでプロセスを terminate して返す（取り消しは CancellationError）。
    /// 途中で止めたときは終了コードを見ない。最後まで読んだ場合だけ、終了コードが0以外でエラーにする。
    func streamLines(
        executableURL: URL,
        arguments: [String],
        timeLimit: TimeInterval = 2.5,
        handler: (String) -> Bool
    ) throws -> LineStreamResult {
        let process = Process()
        let outputPipe = Pipe()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw LauncherError.commandFailed(executable: executableURL.path, message: error.localizedDescription)
        }

        let readHandle = outputPipe.fileHandleForReading
        let fileDescriptor = readHandle.fileDescriptor
        let deadline = Date().addingTimeInterval(timeLimit)
        var pending = Data()
        var buffer = [UInt8](repeating: 0, count: 65_536)
        var stoppedEarly = false
        var timedOut = false
        var cancelled = false
        var sawLine = false

        func stopProcess() {
            if process.isRunning { process.terminate() }
            let killDeadline = Date().addingTimeInterval(1)
            while process.isRunning && Date() < killDeadline {
                usleep(5_000)
            }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            try? readHandle.close()
        }

        readLoop: while true {
            if Task.isCancelled {
                cancelled = true
                break
            }
            if Date() >= deadline {
                timedOut = true
                stoppedEarly = true
                break
            }

            var pollDescriptor = pollfd(fd: fileDescriptor, events: Int16(POLLIN), revents: 0)
            let ready = poll(&pollDescriptor, 1, 20)
            if ready < 0 {
                if errno == EINTR { continue }
                break
            }
            if ready == 0 { continue }

            let count = read(fileDescriptor, &buffer, buffer.count)
            if count < 0 {
                if errno == EINTR || errno == EAGAIN { continue }
                break
            }
            if count == 0 {
                // EOF: 改行で終わらない最後の行も渡す。
                if pending.isEmpty == false {
                    sawLine = true
                    if handler(String(decoding: pending, as: UTF8.self)) == false { stoppedEarly = true }
                    pending.removeAll()
                }
                break
            }

            pending.append(buffer, count: count)
            while let newlineIndex = pending.firstIndex(of: 0x0A) {
                let lineData = pending[pending.startIndex..<newlineIndex]
                let line = String(decoding: lineData, as: UTF8.self)
                pending.removeSubrange(pending.startIndex...newlineIndex)
                sawLine = true
                if handler(line) == false {
                    stoppedEarly = true
                    break readLoop
                }
            }
        }

        let reachedEOF = cancelled == false && stoppedEarly == false
        stopProcess()

        if cancelled { throw CancellationError() }
        if reachedEOF, process.terminationStatus != 0 {
            throw LauncherError.commandFailed(
                executable: executableURL.lastPathComponent,
                message: sawLine ? "exit status \(process.terminationStatus)" : ""
            )
        }
        return LineStreamResult(stoppedEarly: stoppedEarly, timedOut: timedOut)
    }
}
