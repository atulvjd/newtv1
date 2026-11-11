import Foundation
import Darwin
import Newtv1Core

@main
struct Setup {
    static func main() async {
        let provider: AIProvider = CommandLine.arguments.contains("--gemini") ? .gemini : .openAI
        let args = CommandLine.arguments.filter { $0 != "--gemini" }
        if args.count == 2, args[1] == "--check-existing" {
            do {
                guard let key = try KeychainStore.load(provider: provider) else { throw CommandError.invalid("No Newtv1 API key in Keychain.") }
                _ = try await OpenAIBrain(provider: provider).answer("Reply with OK.", model: provider.defaultModel, key: key, search: false, allowWeb: false)
                print("\(provider.title) key and model access verified.")
                return
            } catch { fputs(error.localizedDescription + "\n", stderr); exit(1) }
        }
        guard (2...3).contains(args.count) else { fputs("Usage: Newtv1Setup /absolute/path/to/Newtv1.app [--verify] [--gemini], or --check-existing [--gemini]\n", stderr); exit(1) }
        var original = termios()
        let terminal = tcgetattr(STDIN_FILENO, &original) == 0
        if terminal { var hidden = original; hidden.c_lflag &= ~tcflag_t(ECHO); tcsetattr(STDIN_FILENO, TCSANOW, &hidden) }
        defer { if terminal { tcsetattr(STDIN_FILENO, TCSANOW, &original) } }
        print("Enter API key (input hidden):")
        guard let key = readLine() else { exit(1) }
        do {
            try KeychainStore.save(key, trustedApp: args[1], provider: provider)
            let defaults = UserDefaults(suiteName: "dev.newtv1.mac")!
            defaults.set(true, forKey: provider.keyFlag)
            defaults.set(provider.rawValue, forKey: "aiProvider")
            defaults.set(true, forKey: "useOpenAI")
            defaults.set(true, forKey: "allowWebSearch")
            defaults.synchronize()
            print("API key saved in macOS Keychain for Newtv1. No key was written to project files.")
            if CommandLine.arguments.contains("--verify") {
                let brain = OpenAIBrain(provider: provider)
                let decision = try await brain.decide("Put Safari on the left half of my screen", model: provider.defaultModel, key: key, target: "Finder", workflows: [])
                let plan = try decision.actionPlan(transcript: "test", workflows: [])
                guard plan.requiresReview else { throw CommandError.invalid("Action review check failed.") }
                print("Live action planning verified: \(plan.actions.count) validated steps, review required. No actions executed.")
                let answer = try await brain.answer("Find Apple's official guide to using Voice Control on Mac. Give a single sentence and cite the source.", model: provider.defaultModel, key: key, search: true, allowWeb: true)
                guard answer.contains("](https://") else { throw CommandError.invalid("Search returned without a clickable source; inspect the response handling.") }
                print("Live \(provider.title) web search and clickable citation verified.")
            }
        } catch { fputs(error.localizedDescription + "\n", stderr); exit(1) }
    }
}
