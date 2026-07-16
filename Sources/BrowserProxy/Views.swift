import AppKit

/// A transparent view that reports clicks. Used for the expandable URL header.
final class ClickView: NSView {
    var onClick: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}

/// One row in the picker: shortcut number, icon, browser name, and up to two pin
/// buttons — one to pin the source app, one to pin the URL.
final class BrowserRowView: NSView {
    var onOpen: (() -> Void)?
    /// URL pin. `exactHost` == true when the user held Option while pinning.
    var onPinURL: ((_ exactHost: Bool) -> Void)?
    /// App pin. Only wired up when the source app is known.
    var onPinApp: (() -> Void)?
    var onHover: (() -> Void)?

    private let highlightLayer = CALayer()
    private var trackingArea: NSTrackingArea?

    /// - Parameter sourceAppName: name of the app the link came from, or nil when
    ///   unknown — in which case the App pin button is omitted.
    init(index: Int, browser: Browser, sourceAppName: String?) {
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

        var views: [NSView] = [number, iconView, name]

        // App pin (left of the URL pin) — only when we know the source app.
        var appPin: NSButton?
        if let sourceAppName {
            let button = NSButton()
            button.bezelStyle = .inline
            button.isBordered = false
            button.image = NSImage(
                systemSymbolName: "macwindow",
                accessibilityDescription: "Pin this app to this browser"
            )
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(pinAppClicked)
            button.toolTip = "Pin all links from \(sourceAppName) to this browser"
            views.append(button)
            appPin = button
        }

        let urlPin = NSButton()
        urlPin.bezelStyle = .inline
        urlPin.isBordered = false
        urlPin.image = NSImage(
            systemSymbolName: "pin", accessibilityDescription: "Pin domain to this browser"
        )
        urlPin.imagePosition = .imageOnly
        urlPin.target = self
        urlPin.action = #selector(pinURLClicked)
        urlPin.toolTip = "Pin this domain to this browser (⌥ for the exact host)"
        views.append(urlPin)

        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        var constraints: [NSLayoutConstraint] = [
            heightAnchor.constraint(equalToConstant: 40),
            number.widthAnchor.constraint(equalToConstant: 14),
            iconView.widthAnchor.constraint(equalToConstant: 26),
            iconView.heightAnchor.constraint(equalToConstant: 26),
            urlPin.widthAnchor.constraint(equalToConstant: 22),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ]
        if let appPin {
            constraints.append(appPin.widthAnchor.constraint(equalToConstant: 22))
        }
        NSLayoutConstraint.activate(constraints)
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

    @objc private func pinURLClicked() {
        let exact = NSEvent.modifierFlags.contains(.option)
        onPinURL?(exact)
    }

    @objc private func pinAppClicked() {
        onPinApp?()
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
