import Foundation

/// On-disk container for rules, matching the `rules.json` schema.
private struct RulesFile: Codable {
    var version: Int = 1
    var rules: [Rule] = []
}

/// Loads, matches, and persists the URL → browser routing rules.
final class RuleStore {
    private let fileURL = AppSupport.url(for: "rules.json")
    private(set) var rules: [Rule]

    init() {
        rules = []
        reload()
    }

    /// Re-reads rules from disk. Called before matching each URL so manual edits
    /// (and rules written by another launch) take effect without a restart.
    func reload() {
        if let data = try? Data(contentsOf: fileURL),
           let file = try? AppSupport.decoder.decode(RulesFile.self, from: data) {
            rules = file.rules
        } else {
            rules = []
        }
    }

    /// Returns the bundle identifier of the browser the URL should open in,
    /// or nil if no rule matches (→ caller shows the picker).
    ///
    /// The caller is responsible for verifying the browser is still installed;
    /// see `matchInstalled(url:registry:)` for the resolved variant.
    func matchBundleID(for url: URL) -> String? {
        let host = (url.host ?? "").lowercased()
        for rule in sortedRules where rule.matches(url: url, host: host) {
            return rule.browserBundleID
        }
        return nil
    }

    /// Like `matchBundleID`, but skips rules whose target browser is no longer
    /// installed so a stale rule falls through to the picker instead of failing.
    func matchInstalled(for url: URL, registry: BrowserRegistry) -> Browser? {
        let host = (url.host ?? "").lowercased()
        for rule in sortedRules where rule.matches(url: url, host: host) {
            if let browser = registry.browser(withBundleID: rule.browserBundleID) {
                return browser
            }
            // Target not installed → keep looking / fall through to picker.
        }
        return nil
    }

    /// Rules ordered by priority (desc), then specificity, then recency.
    private var sortedRules: [Rule] {
        rules.sorted { a, b in
            if a.priority != b.priority { return a.priority > b.priority }
            let sa = specificity(a), sb = specificity(b)
            if sa != sb { return sa > sb }
            return a.createdAt < b.createdAt
        }
    }

    /// Rough specificity so more precise rules win ties: exact/regex > glob >
    /// domain > domainSuffix, with longer patterns preferred.
    private func specificity(_ rule: Rule) -> Int {
        let base: Int
        switch rule.matchType {
        case .exact: base = 400
        case .regex: base = 300
        case .glob: base = 200
        case .domain: base = 150
        case .domainSuffix: base = 100
        }
        return base + rule.pattern.count
    }

    // MARK: - Mutation

    /// Adds a rule and persists. Used by the picker's "pin"/learn action.
    func add(_ rule: Rule) {
        rules.append(rule)
        save()
    }

    /// Convenience for the learn flow: pin a host (or its registrable domain)
    /// to a browser. When `exactHost` is true the full host is pinned, otherwise
    /// the registrable domain is used as a domain suffix.
    ///
    /// Re-pinning a pattern **edits** its rule rather than adding a second one, so
    /// bypassing the rules (shift) and pinning a different browser is a complete
    /// way to change a rule's target without touching rules.json.
    func learn(url: URL, browser: Browser, exactHost: Bool) {
        guard let host = url.host?.lowercased(), !host.isEmpty else { return }
        let (pattern, type) = Self.rulePattern(forHost: host, exactHost: exactHost)

        if let i = rules.firstIndex(where: { $0.pattern == pattern && $0.matchType == type }) {
            // Same target and already active → nothing to write.
            if rules[i].browserBundleID == browser.id && rules[i].enabled { return }
            rules[i].browserBundleID = browser.id
            rules[i].enabled = true
            save()
            return
        }
        add(Rule(pattern: pattern, matchType: type, browserBundleID: browser.id))
    }

    /// Derives a rule pattern from a host. `shop.kunde-x.de` → `kunde-x.de`
    /// (domainSuffix); `localhost` and IP literals stay exact.
    static func rulePattern(forHost host: String, exactHost: Bool) -> (String, MatchType) {
        if exactHost || host == "localhost" || isIPLiteral(host) {
            return (host, .domain)
        }
        let labels = host.split(separator: ".")
        guard labels.count >= 2 else { return (host, .domain) }

        // Normally the registrable domain is the last two labels. Under a
        // multi-label public suffix it is three, otherwise pinning
        // shop.example.co.uk would produce "co.uk" and capture all of .co.uk.
        var take = 2
        if labels.count >= 3, multiLabelPublicSuffixes.contains(labels.suffix(2).joined(separator: ".")) {
            take = 3
        }
        return (labels.suffix(take).joined(separator: "."), .domainSuffix)
    }

    /// Two-label public suffixes common enough to be worth special-casing. Not the
    /// full Public Suffix List — that would need a bundled, regularly updated table;
    /// a host under a suffix missing here just pins one label too few, and ⌥-pin
    /// (exact host) is always available as a workaround.
    private static let multiLabelPublicSuffixes: Set<String> = [
        "co.uk", "org.uk", "ac.uk", "gov.uk", "me.uk", "net.uk", "sch.uk",
        "co.jp", "or.jp", "ne.jp", "ac.jp", "go.jp",
        "com.au", "net.au", "org.au", "edu.au", "gov.au",
        "co.nz", "net.nz", "org.nz", "govt.nz", "ac.nz",
        "com.br", "net.br", "org.br", "gov.br",
        "co.za", "org.za", "net.za", "gov.za",
        "co.in", "net.in", "org.in", "gov.in", "ac.in",
        "com.cn", "net.cn", "org.cn", "gov.cn", "edu.cn",
        "com.mx", "com.ar", "com.tr", "com.tw", "com.hk", "com.sg", "com.pl",
        "co.kr", "or.kr",
        "co.il", "org.il",
    ]

    private static func isIPLiteral(_ host: String) -> Bool {
        // IPv6 comes bracketed from URL.host on some systems; treat both forms.
        if host.contains(":") { return true }
        let parts = host.split(separator: ".")
        return parts.count == 4 && parts.allSatisfy { Int($0) != nil }
    }

    func save() {
        let file = RulesFile(version: 1, rules: rules)
        if let data = try? AppSupport.encoder.encode(file) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
