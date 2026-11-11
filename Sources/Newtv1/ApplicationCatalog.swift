import AppKit
import Newtv1Core

@MainActor
final class ApplicationCatalog {
    private var applications: [InstalledApplication] = []
    private var refreshedAt = Date.distantPast

    func resolve(_ name: String) throws -> InstalledApplication {
        refreshIfNeeded()
        do { return try ApplicationMatch.resolve(name, in: applications) }
        catch CommandError.unknown {
            // An application may have been installed since the previous lookup.
            refreshIfNeeded(force: true)
            return try ApplicationMatch.resolve(name, in: applications)
        }
    }

    private func refreshIfNeeded(force: Bool = false) {
        guard force || Date().timeIntervalSince(refreshedAt) > 30 else { return }
        let manager = FileManager.default
        var urls = NSWorkspace.shared.runningApplications.compactMap(\.bundleURL)
        let roots = ["/Applications", "/System/Applications", "/System/Library/CoreServices",
                     manager.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path]
        for root in roots {
            let rootURL = URL(fileURLWithPath: root)
            guard let enumerator = manager.enumerator(at: rootURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { continue }
            var inspected = 0
            while let url = enumerator.nextObject() as? URL, inspected < 3000 {
                inspected += 1
                if url.pathExtension.lowercased() == "app" {
                    urls.append(url)
                    enumerator.skipDescendants()
                } else if url.pathComponents.count - rootURL.pathComponents.count >= 3 {
                    enumerator.skipDescendants()
                }
            }
        }
        var seen = Set<String>()
        applications = urls.compactMap { url in
            let canonical = url.resolvingSymlinksInPath().standardizedFileURL
            guard seen.insert(canonical.path).inserted, let bundle = Bundle(url: canonical),
                  let identifier = bundle.bundleIdentifier else { return nil }
            let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                ?? canonical.deletingPathExtension().lastPathComponent
            return InstalledApplication(name: name, bundleID: identifier, path: canonical.path)
        }.sorted { $0.path < $1.path }
        refreshedAt = Date()
    }
}
