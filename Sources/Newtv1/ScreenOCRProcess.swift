import Foundation

/// Keeps native recognition faults outside the UI process. Bytes travel only through
/// private pipes, with bounded output, cancellation, and a 30-second deadline.
final class ScreenOCRProcess: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    private var timedOut = false

    func read(_ image: Data) async throws -> String {
        guard !image.isEmpty, image.count <= 5_000_000 else { throw Newtv1Failure("Screen image is too large for local text recognition.") }
        let executable = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/Newtv1ScreenReader")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { throw Newtv1Failure("The local screen reader is missing. Rebuild Newtv1 and try again.") }
        return try await withTaskCancellationHandler(operation: {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                let task = Process(), input = Pipe(), output = Pipe()
                task.executableURL = executable
                task.standardInput = input; task.standardOutput = output; task.standardError = FileHandle.nullDevice
                do { try launch(task) }
                catch { continuation.resume(throwing: error); return }
                try? input.fileHandleForReading.close()
                try? output.fileHandleForWriting.close()
                DispatchQueue.global(qos: .userInitiated).async {
                    try? input.fileHandleForWriting.write(contentsOf: image)
                    try? input.fileHandleForWriting.close()
                }
                DispatchQueue.global(qos: .userInitiated).async { [self] in
                    let result: Result<String, Error>
                    do {
                        var response = Data()
                        while let chunk = try output.fileHandleForReading.read(upToCount: 8192), !chunk.isEmpty {
                            response.append(chunk)
                            guard response.count <= 100_000 else { throw Newtv1Failure("Local text recognition returned too much data.") }
                        }
                        task.waitUntilExit()
                        guard !wasCancelled else { throw CancellationError() }
                        guard !didTimeOut else { throw Newtv1Failure("Local text recognition timed out. Your screen preview is still available.") }
                        guard task.terminationStatus == 0 else { throw Newtv1Failure("Local text recognition stopped. Your preview is still available; try again or choose another display.") }
                        struct Response: Decodable { let text: String }
                        let text = try JSONDecoder().decode(Response.self, from: response).text
                        guard text.count <= 20100 else { throw Newtv1Failure("Local screen text is too long.") }
                        result = .success(text)
                    } catch { stop(); result = .failure(error) }
                    try? output.fileHandleForReading.close()
                    continuation.resume(with: result)
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + 30) { [weak self] in
                    if task.isRunning { self?.stop(timeout: true) }
                }
            }
        }, onCancel: { self.stop() })
    }
    private var wasCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    private var didTimeOut: Bool { lock.lock(); defer { lock.unlock() }; return timedOut }
    private func launch(_ task: Process) throws {
        lock.lock(); defer { lock.unlock() }
        guard !cancelled else { throw CancellationError() }
        process = task; try task.run()
    }
    private func stop(timeout: Bool = false) {
        lock.lock()
        if timeout { if !cancelled { timedOut = true } } else { cancelled = true }
        let task = process; lock.unlock()
        guard let task, task.isRunning else { return }
        task.terminate()
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) { if task.isRunning { kill(task.processIdentifier, SIGKILL) } }
    }
}
