import AppKit
import Speech

@main
enum Newtv1Entry {
    @MainActor static func main() {
        let arguments = CommandLine.arguments
        if arguments.count == 3, arguments[1] == "--check-apple-speech" {
            // Exercise the signed app's actual Apple recognizer and existing TCC
            // identity without creating AppModel, opening a microphone or commands.
            Task { exit(await checkAppleSpeech(URL(fileURLWithPath: arguments[2]))) }
            RunLoop.main.run()
        } else {
            Newtv1App.main()
        }
    }

    @MainActor private static func checkAppleSpeech(_ url: URL) async -> Int32 {
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            print("Speech check needs Newtv1's existing Speech Recognition grant. Open the app and use Settings → Voice → Voice check first.")
            return 1
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            print("Apple on-device English recognition is unavailable on this Mac.")
            return 1
        }
        do {
            let text = try await SpeechFileTranscriber().transcribe(url, recognizer: recognizer,
                allowNetwork: false, vocabulary: ["Newt", "Calculator"], dictation: false)
            guard text.lowercased().contains("calculator") else {
                print("Apple returned a final result but missed the fixture's target word: \(text)")
                return 1
            }
            print("Actual Apple on-device recognition passed: \(text)")
            return 0
        } catch {
            let detail = error as NSError
            print("Apple recognition failed: \(detail.localizedDescription) (\(detail.domain) \(detail.code))")
            return 1
        }
    }
}
