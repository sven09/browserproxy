import AppKit

/// User preferences, matching the `preferences.json` schema.
struct Preferences: Codable {
    var version: Int = 1
    /// Bundle id used when a URL has no host / cannot be matched and the user
    /// wants a silent fallback instead of the picker. nil → always show picker.
    var fallbackBrowserBundleID: String?
    /// Expand the full destination URL by default in the picker.
    var showFullURLByDefault: Bool = false
    /// Terminate after handling a URL instead of staying resident.
    var quitAfterOpen: Bool = false
    /// Modifier that, held while a link is opened, skips the rules and forces the
    /// picker: "shift", "option", "control", "command". null (or anything else)
    /// disables the bypass.
    var bypassModifier: String? = "shift"

    init() {}

    /// Decoded key by key so a preferences.json written by an older build — which
    /// has no `bypassModifier` — still loads, and keeps its other settings.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        fallbackBrowserBundleID = try c.decodeIfPresent(
            String.self, forKey: .fallbackBrowserBundleID)
        showFullURLByDefault = try c.decodeIfPresent(
            Bool.self, forKey: .showFullURLByDefault) ?? false
        quitAfterOpen = try c.decodeIfPresent(Bool.self, forKey: .quitAfterOpen) ?? false
        // Key absent → an older file, so take the default. Key present but null →
        // the user turned the bypass off deliberately; leave it off.
        bypassModifier = c.contains(.bypassModifier)
            ? try c.decodeIfPresent(String.self, forKey: .bypassModifier)
            : "shift"
    }

    /// The configured bypass modifier, or nil when the bypass is off.
    var bypassModifierFlag: NSEvent.ModifierFlags? {
        switch bypassModifier?.lowercased() {
        case "shift": return .shift
        case "option", "alt": return .option
        case "control", "ctrl": return .control
        case "command", "cmd": return .command
        default: return nil
        }
    }
}

/// Loads and persists `Preferences`.
final class PreferencesStore {
    private let fileURL = AppSupport.url(for: "preferences.json")
    private(set) var preferences: Preferences

    init() {
        if let data = try? Data(contentsOf: fileURL),
           let prefs = try? AppSupport.decoder.decode(Preferences.self, from: data) {
            preferences = prefs
        } else {
            preferences = Preferences()
            save()
        }
    }

    func update(_ mutate: (inout Preferences) -> Void) {
        mutate(&preferences)
        save()
    }

    func save() {
        if let data = try? AppSupport.encoder.encode(preferences) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
