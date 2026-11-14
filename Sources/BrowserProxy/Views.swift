import AppKit

/// A transparent view that reports clicks. Used for the expandable URL header.
final class ClickView: NSView {
    var onClick: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}

/// One row in the picker: shortcut number, icon, browser name, and up to two
/// toggle buttons — "App" binds every link from the source app to this browser,
/// "Domain" binds the link's domain. Each shows whether the binding is on.
final class BrowserRowView: NSView {
    var onOpen: (() -> Void)?
    /// Domain button. `exactHost` == true when the user held Option while clicking.
    var onToggleURL: ((_ exactHost: Bool) -> Void)?
    /// App button. Only shown when the source app is known.
    var onToggleApp: (() -> Void)?
    var onHover: (() -> Void)?

    private let highlightLayer = CALayer()
    private var trackingArea: NSTrackingArea?
    private let urlPin: NSButton
    private let appPin: NSButton?

    /// - Parameter sourceAppName: name of the app the link came from, or nil when
    ///   unknown — in which case the App button is omitted.
    init(index: Int, browser: Browser, sourceAppName: String?) {
        urlPin = Self.makeToggleButton(title: "Domain")
        urlPin.toolTip = """
            Click to switch on/off: always open this domain in \(browser.name).
            ⌥-click: only this exact host. ⌘R in the picker opens rules.json.
            """
        if let sourceAppName {
            let button = Self.makeToggleButton(title: "App")
            button.toolTip = """
                Click to switch on/off: always open links from \(sourceAppName) in \(browser.name).
                ⌘R in the picker opens rules.json.
                """
            appPin = button
        } else {
            appPin = nil
        }
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        highlightLayer.cornerRadius = 6
        highlightLayer.backgroundColor = NSColor.clear.cgColor
        layer?.addSublayer(highlightLayer)

        let number = NSTextField(labelWithString: index < 9 ? "\(index + 1)" : " ")
        number.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        number.textColor = .tertiaryLabelColor
        number.alignment = .center

        let iconView = NSImageView(image: browser.icon)
        iconView.imageScaling = .scaleProportionallyUpOrDown

        let name = NSTextField(labelWithString: browser.name)
        name.font = .systemFont(ofSize: 13, weight: .regular)
        name.textColor = .labelColor
        name.lineBreakMode = .byTruncatingTail
        name.setContentHuggingPriority(.defaultLow, for: .horizontal)
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        var views: [NSView] = [number, iconView, name]
        if let appPin {
            appPin.target = self
            appPin.action = #selector(appPinClicked)
            views.append(appPin)
        }
        urlPin.target = self
        urlPin.action = #selector(urlPinClicked)
        views.append(urlPin)

        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 40),
            number.widthAnchor.constraint(equalToConstant: 14),
            iconView.widthAnchor.constraint(equalToConstant: 26),
            iconView.heightAnchor.constraint(equalToConstant: 26),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    private static func makeToggleButton(title: String) -> NSButton {
        let button = NSButton(title: title, target: nil, action: nil)
        button.bezelStyle = .push
        button.controlSize = .small
        button.font = .systemFont(ofSize: 11, weight: .medium)
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        return button
    }

    /// Shows whether this browser holds the URL binding. `exactHost` labels an
    /// exact-host binding "Host" instead of "Domain".
    func setURLPin(active: Bool, exactHost: Bool) {
        Self.style(urlPin, title: active && exactHost ? "Host" : "Domain", active: active)
    }

    /// Shows whether this browser holds the source-app binding.
    func setAppPin(active: Bool) {
        guard let appPin else { return }
        Self.style(appPin, title: "App", active: active)
    }

    private static func style(_ button: NSButton, title: String, active: Bool) {
        button.title = active ? "✓ \(title)" : title
        button.bezelColor = active ? .systemGreen : nil
        button.setAccessibilityValue(active ? "on" : "off")
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func layout() {
        super.layout()
        highlightLayer.frame = bounds
    }

    func setHighlighted(_ on: Bool) {
        highlightLayer.backgroundColor =
            on ? NSColor.selectedContentBackgroundColor.withAlphaComponent(0.85).cgColor
               : NSColor.clear.cgColor
    }

    @objc private func urlPinClicked() {
        let exact = NSEvent.modifierFlags.contains(.option)
        onToggleURL?(exact)
    }

    @objc private func appPinClicked() {
        onToggleApp?()
    }

    override func mouseDown(with event: NSEvent) {
        onOpen?()
    }

    // MARK: Hover tracking

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        let ta = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil
        )
        addTrackingArea(ta)
        trackingArea = ta
    }

    override func mouseEntered(with event: NSEvent) {
        onHover?()
    }
}
