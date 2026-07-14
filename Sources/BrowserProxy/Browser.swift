import AppKit

/// A web browser installed on the system that BrowserProxy can hand a URL to.
struct Browser: Identifiable, Equatable {
    /// Bundle identifier, e.g. "com.google.Chrome". Stable across app moves,
    /// so this is what we store in rules.
    let id: String
    let name: String
    let url: URL

    /// The app icon, loaded lazily from LaunchServices.
    var icon: NSImage {
        let image = NSWorkspace.shared.icon(forFile: url.path)
        image.size = NSSize(width: 32, height: 32)
        return image
    }

    static func == (lhs: Browser, rhs: Browser) -> Bool {
        lhs.id == rhs.id
    }
}
