import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    // Lazily initialized so the very first URL — which can arrive before
    // applicationDidFinishLaunching — is handled correctly.
    private lazy var registry = BrowserRegistry()
    private lazy var rules = RuleStore()
    private lazy var prefs = PreferencesStore()
    private lazy var picker = PickerController()

    /// A URL awaiting the picker, together with the app it was opened from —
    /// captured at intake because the source app is only knowable at that instant,
    /// not later when the (possibly queued) picker is finally shown.
    private struct Pending {
        let url: URL
        let source: SourceApp?
    }

    private var queue: [Pending] = []
    private var presenting = false

    // MARK: - Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        // `BrowserProxy --set-default` asks macOS to make us the default browser.
        // The request must come from this app itself; macOS then shows its own
        // confirmation dialog, which the user has to accept.
        if CommandLine.arguments.contains("--set-default") {
            requestDefaultBrowser()
        }
    }

    private func requestDefaultBrowser() {
        NSWorkspace.shared.setDefaultApplication(
            at: Bundle.main.bundleURL, toOpenURLsWithScheme: "http"
        ) { error in
            if let error {
                NSLog("BrowserProxy: set-default(http) failed: \(error)")
            }
            // https follows http on macOS, but set it explicitly to be safe.
            NSWorkspace.shared.setDefaultApplication(
                at: Bundle.main.bundleURL, toOpenURLsWithScheme: "https"
            ) { error in
                if let error {
                    NSLog("BrowserProxy: set-default(https) failed: \(error)")
                }
            }
        }
    }

    // MARK: - Early Apple Event registration (belt-and-suspenders)

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    @objc private func handleGetURLEvent(
        _ event: NSAppleEventDescriptor, withReplyEvent: NSAppleEventDescriptor
    ) {
        guard let string = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: string) else { return }
        enqueue([url])
    }

    // MARK: - Modern URL delivery

    func application(_ application: NSApplication, open urls: [URL]) {
        enqueue(urls)
    }

    // MARK: - Routing

    private func enqueue(_ urls: [URL]) {
        // Pick up rule changes made on disk (manual edits, other launches).
        rules.reload()
        // Capture the source app now, while the clicking app is still frontmost —
        // by the time the picker appears we may have activated ourselves. All URLs
        // in one delivery came from the same click, so one lookup covers them.
        let source = SourceApp.current(excludingBundleID: Bundle.main.bundleIdentifier)
        // Holding the bypass modifier (shift by default) while opening a link
        // skips routing entirely — that is how a domain already owned by a rule
        // gets back to the picker, and how the rule can be re-pinned elsewhere.
        let bypass = bypassRequested()
        for url in urls {
            if bypass {
                queue.append(Pending(url: url, source: source))
            } else if let browser = rules.matchInstalled(for: url, source: source, registry: registry) {
                // A rule match opens immediately without the picker.
                Launcher.open(url, in: browser) { [weak self] in
                    self?.finishIfIdle()
                }
            } else if let fallbackID = prefs.preferences.fallbackBrowserBundleID,
                      url.host == nil,
                      let browser = registry.browser(withBundleID: fallbackID) {
                // Host-less URLs (rare) can use a configured fallback.
                Launcher.open(url, in: browser) { [weak self] in
                    self?.finishIfIdle()
                }
            } else {
                queue.append(Pending(url: url, source: source))
            }
        }
        presentNextIfNeeded()
    }

    /// True when the bypass modifier is down as the URL arrives. Read live rather
    /// than from an event: the click happened in another app, so there is no event
    /// of ours to inspect.
    private func bypassRequested() -> Bool {
        guard let flag = prefs.preferences.bypassModifierFlag else { return false }
        return NSEvent.modifierFlags.contains(flag)
    }

    private func presentNextIfNeeded() {
        guard !presenting, let pending = queue.first else {
            finishIfIdle()
            return
        }
        // Rescan browsers each time so freshly-installed browsers appear.
        registry.refresh()
        guard !registry.browsers.isEmpty else {
            // No browser to route to; drop the URL to avoid a dead panel.
            NSLog("BrowserProxy: no browsers found to open \(pending.url)")
            queue.removeFirst()
            presentNextIfNeeded()
            return
        }

        presenting = true
        picker.present(
            url: pending.url,
            source: pending.source,
            browsers: registry.browsers,
            showFullURLByDefault: prefs.preferences.showFullURLByDefault
        ) { [weak self] result in
            self?.handle(result: result, for: pending)
        }
    }

    private func handle(result: PickerController.Result, for pending: Pending) {
        presenting = false
        if !queue.isEmpty { queue.removeFirst() }

        switch result {
        case .open(let browser, let pin):
            switch pin {
            case .none:
                break
            case .url(let exactHost):
                rules.learnURL(url: pending.url, browser: browser, exactHost: exactHost)
            case .app:
                // Only reachable when a source app was detected; guard anyway.
                if let source = pending.source {
                    rules.learnApp(source: source, browser: browser)
                }
            }
            Launcher.open(pending.url, in: browser) { [weak self] in
                self?.continueAfterResolve()
            }
        case .cancel:
            continueAfterResolve()
        }
    }

    private func continueAfterResolve() {
        if queue.isEmpty {
            finishIfIdle()
        } else {
            presentNextIfNeeded()
        }
    }

    /// When nothing is pending, either quit (if configured) or return to the
    /// background so the process stays warm for the next click.
    private func finishIfIdle() {
        guard !presenting, queue.isEmpty else { return }
        if prefs.preferences.quitAfterOpen {
            NSApp.terminate(nil)
        } else {
            NSApp.hide(nil)
        }
    }
}
