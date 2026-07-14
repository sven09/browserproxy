import AppKit

/// Enumerates the web browsers installed on the system (everything that can
/// open an https URL), excluding BrowserProxy itself.
final class BrowserRegistry {
    private(set) var browsers: [Browser] = []
    private var byBundleID: [String: Browser] = [:]

    init() {
        refresh()
    }

    /// Re-scans installed browsers. Cheap enough to call on demand.
    func refresh() {
        let probe = URL(string: "https://example.com")!
        let appURLs = NSWorkspace.shared.urlsForApplications(toOpen: probe)

        let selfURL = Bundle.main.bundleURL.standardizedFileURL
        let selfBundleID = Bundle.main.bundleIdentifier

        var seen = Set<String>()
        var result: [Browser] = []

        for url in appURLs {
            // Exclude self by path and by bundle id (once we become the default,
            // LaunchServices returns us too — filtering avoids an open loop).
            if url.standardizedFileURL == selfURL { continue }
            guard let bundle = Bundle(url: url),
                  let bundleID = bundle.bundleIdentifier else { continue }
            if bundleID == selfBundleID { continue }
            if seen.contains(bundleID) { continue }
            seen.insert(bundleID)

            let name = displayName(for: url, bundle: bundle)
            result.append(Browser(id: bundleID, name: name, url: url))
        }

        browsers = result
        byBundleID = Dictionary(uniqueKeysWithValues: result.map { ($0.id, $0) })
    }

    func browser(withBundleID id: String) -> Browser? {
        byBundleID[id]
    }

    private func displayName(for url: URL, bundle: Bundle) -> String {
        if let display = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String {
            return display
        }
        if let name = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String {
            return name
        }
        return FileManager.default.displayName(atPath: url.path)
    }
}
