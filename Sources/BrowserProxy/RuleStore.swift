import Foundation

/// On-disk container for rules, matching the `rules.json` schema.
private struct RulesFile: Codable {
    var version: Int = 2
    var rules: [Rule] = []
}

/// Loads, matches, and persists the routing rules.
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

    /// Returns the bundle identifier of the browser the URL should open in when
    /// opened from `source`, or nil if no rule matches (→ caller shows the picker).
    ///
    /// The caller is responsible for verifying the browser is still installed;
    /// see `matchInstalled(for:source:registry:)` for the resolved variant.
    func matchBundleID(for url: URL, source: SourceApp?) -> String? {
        let host = (url.host ?? "").lowercased()
        for rule in sortedRules where rule.matches(url: url, host: host, source: source) {
            return rule.browserBundleID
        }
        return nil
    }

    /// Like `matchBundleID`, but skips rules whose target browser is no longer
    /// installed so a stale rule falls through to the picker instead of failing.
    func matchInstalled(for url: URL, source: SourceApp?, registry: BrowserRegistry) -> Browser? {
        let host = (url.host ?? "").lowercased()
        for rule in sortedRules where rule.matches(url: url, host: host, source: source) {
            if let browser = registry.browser(withBundleID: rule.browserBundleID) {
                return browser
            }
            // Target not installed → keep looking / fall through to picker.
        }
        return nil
    }

    /// Rules ordered by priority (desc), then specificity, then recency.
    private var sortedRules: [Rule] { Self.sorted(rules) }

    /// Orders rules so the first match wins: `priority` (desc), then specificity,
    /// then age (older first). Pure and static so it can be tested without disk.
    static func sorted(_ rules: [Rule]) -> [Rule] {
        rules.sorted { a, b in
            if a.priority != b.priority { return a.priority > b.priority }
            let sa = specificity(a), sb = specificity(b)
            if sa != sb { return sa > sb }
            return a.createdAt < b.createdAt
        }
    }

    /// Specificity so the most precise rule wins ties. App rules outrank URL rules
    /// (a rule tied to the source application is considered the stronger signal):
    /// a rule with an app condition always sorts above one without. Within that,
    /// a combined app+URL rule beats an app-only rule, and among URL conditions
    /// exact/regex > glob > domain > domainSuffix, with longer patterns preferred.
    static func specificity(_ rule: Rule) -> Int {
        // Larger than any realistic urlSpecificity, so the app tier dominates.
        let appTier = 1_000_000
        var score = rule.hasAppCondition ? appTier : 0
        if rule.hasURLCondition {
            let base: Int
            switch rule.matchType {
            case .exact: base = 400
            case .regex: base = 300
            case .glob: base = 200
            case .domain: base = 150
            case .domainSuffix: base = 100
            case nil: base = 0
            }
            score += base + (rule.pattern?.count ?? 0)
        }
        return score
    }

    // MARK: - Mutation

    /// Adds a rule and persists. Used by the picker's "pin"/learn action.
    func add(_ rule: Rule) {
        rules.append(rule)
        save()
    }

    /// Learn flow for the **URL pin**: bind a host (or its registrable domain) to a
    /// browser. When `exactHost` is true the full host is pinned, otherwise the
    /// registrable domain is used as a domain suffix.
    ///
    /// Re-pinning a pattern **edits** its URL-only rule rather than adding a second
    /// one, so bypassing the rules (shift) and pinning a different browser is a
    /// complete way to change a rule's target without touching rules.json.
    func learnURL(url: URL, browser: Browser, exactHost: Bool) {
        guard let host = url.host?.lowercased(), !host.isEmpty else { return }
        let (pattern, type) = Self.rulePattern(forHost: host, exactHost: exactHost)

        // Only match a URL-only rule; never rewrite a combined app+URL rule.
        if let i = rules.firstIndex(where: {
            $0.pattern == pattern && $0.matchType == type && $0.sourceAppBundleID == nil
        }) {
            // Same target and already active → nothing to write.
            if rules[i].browserBundleID == browser.id && rules[i].enabled { return }
            rules[i].browserBundleID = browser.id
            rules[i].enabled = true
            save()
            return
        }
        add(Rule(pattern: pattern, matchType: type, browserBundleID: browser.id))
    }

    /// Learn flow for the **App pin**: bind everything opened from `source` to a
    /// browser. Re-pinning the same app edits its app-only rule in place.
    func learnApp(source: SourceApp, browser: Browser) {
        // Only match an app-only rule; never rewrite a combined app+URL rule.
        if let i = rules.firstIndex(where: {
            $0.sourceAppBundleID == source.bundleID && !$0.hasURLCondition
        }) {
            if rules[i].browserBundleID == browser.id && rules[i].enabled { return }
            rules[i].browserBundleID = browser.id
            rules[i].enabled = true
            save()
            return
        }
        add(Rule(sourceAppBundleID: source.bundleID, browserBundleID: browser.id))
    }

    // MARK: - Pin state (picker toggle buttons)

    /// Indices of URL-only rules a URL pin for `url` would write: the domain and the
    /// exact-host variant. Rules written by hand in other shapes are not touched.
    private func urlPinIndices(for url: URL) -> [Int] {
        guard let host = url.host?.lowercased(), !host.isEmpty else { return [] }
        let candidates = [
            Self.rulePattern(forHost: host, exactHost: false),
            Self.rulePattern(forHost: host, exactHost: true),
        ]
        return rules.indices.filter { i in
            let r = rules[i]
            return r.sourceAppBundleID == nil
                && candidates.contains { $0.0 == r.pattern && $0.1 == r.matchType }
        }
    }

    /// The enabled URL pin for `url`, preferring the exact-host rule (it wins in
    /// matching). `exactHost` tells the picker whether to label it Host or Domain.
    func activeURLPin(for url: URL) -> (browserID: String, exactHost: Bool)? {
        let active = urlPinIndices(for: url)
            .map { rules[$0] }
            .filter(\.enabled)
            .max { Self.specificity($0) < Self.specificity($1) }
        guard let active else { return nil }
        let exact = active.matchType == .domain && active.pattern == url.host?.lowercased()
        return (active.browserBundleID, exact)
    }

    /// Switches every URL pin for `url` off (`enabled: false`), keeping the rules
    /// in rules.json so they can be switched on again.
    func disableURLPins(for url: URL) {
        var changed = false
        for i in urlPinIndices(for: url) where rules[i].enabled {
            rules[i].enabled = false
            changed = true
        }
        if changed { save() }
    }

    /// Browser bundle ID of the enabled app-only rule for `source`, if any.
    func activeAppPin(for source: SourceApp) -> String? {
        rules.first {
            $0.sourceAppBundleID == source.bundleID && !$0.hasURLCondition && $0.enabled
        }?.browserBundleID
    }

    /// Switches the app-only rule for `source` off (`enabled: false`).
    func disableAppPin(for source: SourceApp) {
        var changed = false
        for i in rules.indices
        where rules[i].sourceAppBundleID == source.bundleID && !rules[i].hasURLCondition && rules[i].enabled {
            rules[i].enabled = false
            changed = true
        }
        if changed { save() }
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
        let file = RulesFile(version: 2, rules: rules)
        if let data = try? AppSupport.encoder.encode(file) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
