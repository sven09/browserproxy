import Foundation

/// How a rule's `pattern` is compared against an incoming URL.
enum MatchType: String, Codable {
    /// Exact host equality (e.g. "localhost", "kunde-x.de").
    case domain
    /// Host equals the pattern or ends with "." + pattern
    /// (e.g. "kunde-x.de" also matches "shop.kunde-x.de"). Default for learned rules.
    case domainSuffix
    /// Shell-style wildcard against the host or full URL (e.g. "*.internal.corp").
    case glob
    /// Regular expression against the full URL.
    case regex
    /// Full-URL equality.
    case exact
}

/// A single routing rule. A rule can constrain on a **URL pattern**, on the
/// **source application** a link was opened from, or on both:
///
/// - URL-only  (`pattern` set, `sourceAppBundleID` nil) — the classic behaviour:
///   `kunde-x.de → Edge`.
/// - App-only  (`pattern` nil, `sourceAppBundleID` set) — "everything opened from
///   this app goes here": `Cursor → Chrome`.
/// - Combined  (both set) — the URL pattern, but only when opened from that app.
///
/// A rule with neither condition never matches (it would otherwise catch every
/// link). See `RuleStore` for how the winner is chosen when several match.
struct Rule: Codable, Identifiable {
    let id: UUID
    /// URL pattern to match, or nil for an app-only rule.
    var pattern: String?
    /// How `pattern` is compared. Meaningful only when `pattern` is set.
    var matchType: MatchType?
    /// Bundle id of the source application to match, or nil for a URL-only rule.
    var sourceAppBundleID: String?
    /// Bundle identifier of the target browser.
    var browserBundleID: String
    var enabled: Bool
    var priority: Int
    var createdAt: Date

    init(
        id: UUID = UUID(),
        pattern: String? = nil,
        matchType: MatchType? = nil,
        sourceAppBundleID: String? = nil,
        browserBundleID: String,
        enabled: Bool = true,
        priority: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.pattern = pattern
        self.matchType = matchType
        self.sourceAppBundleID = sourceAppBundleID
        self.browserBundleID = browserBundleID
        self.enabled = enabled
        self.priority = priority
        self.createdAt = createdAt
    }

    /// True when the rule declares a URL condition.
    var hasURLCondition: Bool { pattern != nil && matchType != nil }
    /// True when the rule declares a source-app condition.
    var hasAppCondition: Bool { sourceAppBundleID != nil }

    /// Returns true if this rule matches the given URL opened from `source`.
    /// Disabled rules, and rules with no condition at all, never match. Every
    /// condition the rule declares must be satisfied (logical AND).
    func matches(url: URL, host: String, source: SourceApp?) -> Bool {
        guard enabled, hasURLCondition || hasAppCondition else { return false }

        // App condition: an app rule can only match when the source is known.
        if hasAppCondition, source?.bundleID != sourceAppBundleID {
            return false
        }
        // URL condition.
        if hasURLCondition, !matchesURL(url: url, host: host) {
            return false
        }
        return true
    }

    private func matchesURL(url: URL, host: String) -> Bool {
        guard let pattern, let matchType else { return false }
        let full = url.absoluteString

        switch matchType {
        case .domain:
            return host == pattern.lowercased()
        case .domainSuffix:
            let p = pattern.lowercased()
            return host == p || host.hasSuffix("." + p)
        case .glob:
            // Match the glob against the host first, then the full URL.
            return Rule.glob(pattern, matches: host) || Rule.glob(pattern, matches: full)
        case .regex:
            guard let re = try? NSRegularExpression(pattern: pattern) else { return false }
            let range = NSRange(full.startIndex..., in: full)
            return re.firstMatch(in: full, range: range) != nil
        case .exact:
            return full == pattern
        }
    }

    /// Minimal shell-style glob: `*` matches any run of characters, `?` matches one.
    static func glob(_ pattern: String, matches candidate: String) -> Bool {
        // Translate the glob into an anchored regex.
        var regex = "^"
        for ch in pattern {
            switch ch {
            case "*": regex += ".*"
            case "?": regex += "."
            default: regex += NSRegularExpression.escapedPattern(for: String(ch))
            }
        }
        regex += "$"
        guard let re = try? NSRegularExpression(pattern: regex, options: [.caseInsensitive]) else {
            return false
        }
        let range = NSRange(candidate.startIndex..., in: candidate)
        return re.firstMatch(in: candidate, range: range) != nil
    }
}
