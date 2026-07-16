import AppKit

/// The application a URL open request originated from — captured as the app that
/// was frontmost the instant the link arrived.
///
/// This is best-effort: macOS does not tell a URL handler which app asked it to
/// open a link, so we infer it from the frontmost application. BrowserProxy is an
/// accessory app (`.accessory` policy) and does not activate itself until it
/// actually shows the picker, so at intake time the clicking app is still in
/// front. Sources with no meaningful frontmost app — `open …` from a background
/// script, some notifications — yield `nil`, and app rules simply don't apply.
struct SourceApp: Equatable {
    /// Bundle identifier, e.g. `com.microsoft.VSCode`, `com.todesktop.230313mzl4w4u92`
    /// (Cursor) or `com.apple.mail`. This is what an app rule stores.
    let bundleID: String
    /// Human-readable name, used only for the picker's "Pin all links from …"
    /// affordance and tooltip.
    let name: String

    /// The frontmost application at call time, or `nil` when it is unknown or is
    /// BrowserProxy itself (which would make the "source" meaningless).
    static func current(excludingBundleID excluded: String?) -> SourceApp? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleID = app.bundleIdentifier,
              bundleID != excluded else { return nil }
        return SourceApp(bundleID: bundleID, name: app.localizedName ?? bundleID)
    }
}
