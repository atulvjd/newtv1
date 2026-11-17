import Foundation
import Speech

/// A bounded second pass over this request's local WAV. Never returns a partial
/// result, and never changes whether Apple network recognition was authorized.
@MainActor
final class SpeechFileTranscriber {
    private var task: SFSpeechRecognitionTask?
    private var timeout: Task<Void, Never>?
    private var continuation: CheckedContinuation<String, Error>?

    func transcribe(_ url: URL, recognizer: SFSpeechRecognizer, allowNetwork: Bool,
                    vocabulary: [String], dictation: Bool) async throws -> String {
        try Task.checkCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                let request = SFSpeechURLRecognitionRequest(url: url)
                request.requiresOnDeviceRecognition = !allowNetwork
                request.shouldReportPartialResults = false
                request.addsPunctuation = dictation
                request.taskHint = .dictation
                request.contextualStrings = Array(vocabulary.prefix(100))
                task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        if let result, result.isFinal {
                            let text = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
                            self.finish(text.isEmpty ? .failure(SpeechTranscriptionError.noWords) : .success(text))
                        } else if let error { self.finish(.failure(error)) }
                    }
                }
                timeout = Task { [weak self] in
                    do { try await Task.sleep(nanoseconds: 20_000_000_000) } catch { return }
                    self?.finish(.failure(SpeechTranscriptionError.timeout))
                }
                if Task.isCancelled { finish(.failure(CancellationError())) }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finish(.failure(CancellationError())) }
        }
    }

    private func finish(_ result: Result<String, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        timeout?.cancel(); timeout = nil
        task?.cancel(); task = nil
        continuation.resume(with: result)
    }
}

enum SpeechTranscriptionError: LocalizedError {
    case noWords, timeout
    var errorDescription: String? {
        switch self {
        case .noWords: return "No words were recognized. Check the microphone input and recognition language in Settings → Voice."
        case .timeout: return "Apple speech recognition did not finish. Check the recognition language and its downloaded speech assets."
        }
    }
}
