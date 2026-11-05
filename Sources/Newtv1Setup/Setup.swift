import Foundation
import Darwin
import Newtv1Core

@main
struct Setup {
    static func main() {
        guard CommandLine.arguments.count == 2 else { fputs("Usage: Newtv1Setup /absolute/path/to/Newtv1.app\n", stderr); exit(1) }
        var original = termios()
        let terminal = tcgetattr(STDIN_FILENO, &original) == 0
        if terminal { var hidden = original; hidden.c_lflag &= ~tcflag_t(ECHO); tcsetattr(STDIN_FILENO, TCSANOW, &hidden) }
        defer { if terminal { tcsetattr(STDIN_FILENO, TCSANOW, &original) } }
        print("Enter API key (input hidden):")
        guard let key = readLine() else { exit(1) }
        do {
            try KeychainStore.save(key, trustedApp: CommandLine.arguments[1])
            let defaults = UserDefaults(suiteName: "dev.newtv1.mac")!
            defaults.set(true, forKey: "openAIKeyConfigured")
            defaults.set(true, forKey: "useOpenAI")
            defaults.set(true, forKey: "allowWebSearch")
            defaults.synchronize()
            print("API key saved in macOS Keychain for Newtv1. No key was written to project files.")
        } catch { fputs(error.localizedDescription + "\n", stderr); exit(1) }
    }
}
