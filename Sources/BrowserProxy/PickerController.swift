import AppKit

/// Presents the browser picker panel and reports the user's choice.
///
/// A single controller instance is reused across presentations; only one panel
/// is on screen at a time (the AppDelegate serializes URLs).
final class PickerController {

    /// What, if anything, to remember alongside opening the browser.
    enum PinKind {
        /// Just open; write no rule.
        case none
        /// Pin the URL. `exactHost` pins the full host instead of the domain.
        case url(exactHost: Bool)
        /// Pin the source application — every link from it opens here.
        case app
    }

    /// Outcome of a presentation.
    enum Result {
        case open(Browser, pin: PinKind)
        case cancel
    }

    private var panel: PickerPanel?
    private var resignObserver: NSObjectProtocol?
    private var finished = false

    private var url: URL!
    private var source: SourceApp?
    private var browsers: [Browser] = []
    private var rules: RuleStore?
    private var onResolve: ((Result) -> Void)?

    private var selectedIndex = 0
    private var rowViews: [BrowserRowView] = []
    private var urlLabel: NSTextField?
    private var urlExpanded = false

    // MARK: - Presentation

    func present(
        url: URL,
        source: SourceApp?,
        browsers: [Browser],
        rules: RuleStore,
        showFullURLByDefault: Bool,
        onResolve: @escaping (Result) -> Void
    ) {
        // If a panel is somehow still up, tear it down first.
        teardown()

        self.url = url
        self.source = source
        self.browsers = browsers
        self.rules = rules
        self.onResolve = onResolve
        self.selectedIndex = 0
        self.urlExpanded = showFullURLByDefault
        self.finished = false

        let content = buildContentView()
        let panel = PickerPanel(
            contentRect: NSRect(origin: .zero, size: content.fittingSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.keyHandler = self
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.contentView = content
        panel.setContentSize(content.fittingSize)

        self.panel = panel
        positionAtCursor(panel)
        highlight(index: 0)

        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel, queue: .main
        ) { [weak self] _ in
            // Delivered on the main queue, so main-actor access is safe.
            MainActor.assumeIsolated { self?.cancel() }
        }

        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    // MARK: - View construction

    private func buildContentView() -> NSView {
        let container = NSVisualEffectView()
        container.material = .popover
        container.blendingMode = .behindWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 12
        container.layer?.masksToBounds = true
        container.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 10, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false

        // URL header (click to expand/collapse).
        let urlField = NSTextField(labelWithString: displayURL())
        urlField.font = .systemFont(ofSize: 11, weight: .medium)
        urlField.textColor = .secondaryLabelColor
        urlField.lineBreakMode = urlExpanded ? .byCharWrapping : .byTruncatingMiddle
        urlField.maximumNumberOfLines = urlExpanded ? 0 : 1
        urlField.preferredMaxLayoutWidth = 336
        urlField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        self.urlLabel = urlField

        let urlButton = ClickView(frame: .zero)
        urlButton.onClick = { [weak self] in self?.toggleURLExpansion() }
        urlButton.translatesAutoresizingMaskIntoConstraints = false
        urlButton.addSubview(urlField)
        urlField.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            urlField.leadingAnchor.constraint(equalTo: urlButton.leadingAnchor),
            urlField.trailingAnchor.constraint(equalTo: urlButton.trailingAnchor),
            urlField.topAnchor.constraint(equalTo: urlButton.topAnchor),
            urlField.bottomAnchor.constraint(equalTo: urlButton.bottomAnchor),
            urlButton.widthAnchor.constraint(equalToConstant: 336),
        ])
        stack.addArrangedSubview(urlButton)

        // "from <app>" — makes the App pin discoverable and shows what it targets.
        if let source {
            let from = NSTextField(labelWithString: "from \(source.name)")
            from.font = .systemFont(ofSize: 10, weight: .regular)
            from.textColor = .tertiaryLabelColor
            from.lineBreakMode = .byTruncatingTail
            stack.addArrangedSubview(from)
        }

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(separator)
        separator.widthAnchor.constraint(equalToConstant: 336).isActive = true

        // Browser rows.
        rowViews.removeAll()
        for (i, browser) in browsers.enumerated() {
            let row = BrowserRowView(index: i, browser: browser, sourceAppName: source?.name)
            row.onOpen = { [weak self] in self?.choose(index: i) }
            row.onToggleURL = { [weak self] exact in self?.toggleURLPin(index: i, exactHost: exact) }
            row.onToggleApp = { [weak self] in self?.toggleAppPin(index: i) }
            row.onHover = { [weak self] in self?.highlight(index: i) }
            rowViews.append(row)
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalToConstant: 336).isActive = true
        }
        refreshPins()

        // Footer hints: navigation, how to pin, how to change or remove a pin.
        for line in footerHints() {
            let hint = NSTextField(wrappingLabelWithString: line)
            hint.font = .systemFont(ofSize: 10)
            hint.textColor = .tertiaryLabelColor
            hint.isSelectable = false
            hint.preferredMaxLayoutWidth = 336
            stack.addArrangedSubview(hint)
        }

        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    private func footerHints() -> [String] {
        let navigation = ["1–9 open", "↑↓ move", "⏎ open", "⌘C copy", "esc cancel"]
        let buttons = source == nil
            ? "Domain button: click to switch the binding on/off (⌥-click: exact host)"
            : "Domain / App buttons: click to switch a binding on/off (⌥-click: exact host)"
        var keys = ["⌘P bind domain + open"]
        if source != nil { keys.append("⌘⇧P bind app + open") }
        keys.append("⌘R rules")
        return [
            navigation.joined(separator: " · "),
            buttons,
            keys.joined(separator: " · "),
            "Bound links skip this picker; hold ⇧ while clicking to see it again.",
        ]
    }

    /// Opens rules.json in its default editor so a rule can be deleted, or reveals
    /// the folder in Finder when no rule has been written yet. The picker loses
    /// focus and cancels; the link is not opened.
    private func openRulesFile() {
        let file = AppSupport.url(for: "rules.json")
        if FileManager.default.fileExists(atPath: file.path) {
            NSWorkspace.shared.open(file)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([AppSupport.directory])
        }
        cancel()
    }

    private func displayURL() -> String {
        url.absoluteString
    }

    private func toggleURLExpansion() {
        urlExpanded.toggle()
        guard let field = urlLabel else { return }
        field.lineBreakMode = urlExpanded ? .byCharWrapping : .byTruncatingMiddle
        field.maximumNumberOfLines = urlExpanded ? 0 : 1
        if let panel { panel.setContentSize(panel.contentView!.fittingSize) }
    }

    // MARK: - Positioning

    private func positionAtCursor(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) }
            ?? NSScreen.main
        guard let visible = screen?.visibleFrame else {
            panel.center(); return
        }
        let size = panel.frame.size
        // Place top-left corner near the cursor (Cocoa origin is bottom-left).
        var originX = mouse.x
        var originY = mouse.y - size.height
        originX = min(max(originX, visible.minX), visible.maxX - size.width)
        originY = min(max(originY, visible.minY), visible.maxY - size.height)
        panel.setFrameOrigin(NSPoint(x: originX, y: originY))
    }

    // MARK: - Selection & keyboard

    private func highlight(index: Int) {
        guard !rowViews.isEmpty else { return }
        let clamped = min(max(index, 0), rowViews.count - 1)
        selectedIndex = clamped
        for (i, row) in rowViews.enumerated() {
            row.setHighlighted(i == clamped)
        }
    }

    /// Called by the panel on keyDown. Returns true when handled.
    func handleKeyDown(_ event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Command combinations.
        if mods.contains(.command) {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "c":
                copyURL(); return true
            case "r":
                openRulesFile(); return true
            case "p":
                if mods.contains(.shift) {
                    // ⌘⇧P → pin the source app.
                    choosePinnedApp(index: selectedIndex)
                } else {
                    // ⌘P → pin the URL; ⌥ pins the exact host.
                    choosePinnedURL(index: selectedIndex, exactHost: mods.contains(.option))
                }
                return true
            default:
                return false
            }
        }

        switch event.keyCode {
        case 53: // esc
            cancel(); return true
        case 125: // down
            highlight(index: selectedIndex + 1); return true
        case 126: // up
            highlight(index: selectedIndex - 1); return true
        case 36, 76: // return / enter
            choose(index: selectedIndex); return true
        default:
            break
        }

        // Number keys 1–9 select directly.
        if let chars = event.charactersIgnoringModifiers, let n = Int(chars),
           n >= 1, n <= browsers.count {
            choose(index: n - 1)
            return true
        }
        return false
    }

    private func copyURL() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(url.absoluteString, forType: .string)
    }

    // MARK: - Pin toggles

    /// Domain button: switches the URL binding on for this browser, or off when
    /// it is already bound here. Only one browser holds the binding at a time.
    private func toggleURLPin(index: Int, exactHost: Bool) {
        guard let rules, browsers.indices.contains(index) else { return }
        let browser = browsers[index]
        let active = rules.activeURLPin(for: url)
        rules.disableURLPins(for: url)
        if active?.browserID != browser.id {
            rules.learnURL(url: url, browser: browser, exactHost: exactHost)
        }
        refreshPins()
    }

    /// App button: switches "every link from this app" on for this browser, or
    /// off when it is already bound here.
    private func toggleAppPin(index: Int) {
        guard let rules, let source, browsers.indices.contains(index) else { return }
        let browser = browsers[index]
        if rules.activeAppPin(for: source) == browser.id {
            rules.disableAppPin(for: source)
        } else {
            rules.learnApp(source: source, browser: browser)
        }
        refreshPins()
    }

    /// Updates every row's buttons from the current rules.
    private func refreshPins() {
        let urlPin = rules?.activeURLPin(for: url)
        let appPin = source.flatMap { rules?.activeAppPin(for: $0) }
        for (i, row) in rowViews.enumerated() {
            let id = browsers[i].id
            row.setURLPin(active: urlPin?.browserID == id, exactHost: urlPin?.exactHost ?? false)
            row.setAppPin(active: appPin == id)
        }
    }

    private func choose(index: Int) {
        guard browsers.indices.contains(index) else { return }
        resolve(.open(browsers[index], pin: .none))
    }

    private func choosePinnedURL(index: Int, exactHost: Bool) {
        guard browsers.indices.contains(index) else { return }
        resolve(.open(browsers[index], pin: .url(exactHost: exactHost)))
    }

    private func choosePinnedApp(index: Int) {
        // No source app → nothing to pin to; ignore the request.
        guard source != nil, browsers.indices.contains(index) else { return }
        resolve(.open(browsers[index], pin: .app))
    }

    func cancel() {
        resolve(.cancel)
    }

    // MARK: - Teardown

    private func resolve(_ result: Result) {
        guard !finished else { return }
        finished = true
        let cb = onResolve
        teardown()
        cb?(result)
    }

    private func teardown() {
        if let obs = resignObserver {
            NotificationCenter.default.removeObserver(obs)
            resignObserver = nil
        }
        panel?.orderOut(nil)
        panel = nil
        rowViews.removeAll()
        urlLabel = nil
        rules = nil
        onResolve = nil
    }
}
