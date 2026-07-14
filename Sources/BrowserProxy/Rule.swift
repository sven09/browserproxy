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

/// A single URL-pattern → browser mapping.
struct Rule: Codable, Identifiable {
    let id: UUID
    var pattern: String
    var matchType: MatchType
    /// Bundle identifier of the target browser.
    var browserBundleID: String
    var enabled: Bool
    var priority: Int
    var createdAt: Date

    init(
        id: UUID = UUID(),
        pattern: String,
        matchType: MatchType,
        browserBundleID: String,
        enabled: Bool = true,
        priority: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.pattern = pattern
        self.matchType = matchType
        self.browserBundleID = browserBundleID
        self.enabled = enabled
        self.priority = priority
        self.createdAt = createdAt
    }

    /// Returns true if this rule matches the given URL. Disabled rules never match.
    func matches(url: URL, host: String) -> Bool {
        guard enabled else { return false }
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
