import AppKit

/// A transparent view that reports clicks. Used for the expandable URL header.
final class ClickView: NSView {
    var onClick: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}

/// One row in the picker: shortcut number, icon, browser name, and a pin button.
final class BrowserRowView: NSView {
    var onOpen: (() -> Void)?
    /// exactHost == true when the user held Option while pinning.
    var onPin: ((_ exactHost: Bool) -> Void)?
    var onHover: (() -> Void)?

    private let highlightLayer = CALayer()
    private var trackingArea: NSTrackingArea?

    init(index: Int, browser: Browser) {
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

        let pin = NSButton()
        pin.bezelStyle = .inline
        pin.isBordered = false
        pin.image = NSImage(
            systemSymbolName: "pin", accessibilityDescription: "Pin domain to this browser"
        )
        pin.imagePosition = .imageOnly
        pin.target = self
        pin.action = #selector(pinClicked)
        pin.toolTip = "Pin this domain to this browser (⌥ for the exact host)"

        let stack = NSStackView(views: [number, iconView, name, pin])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 40),
            number.widthAnchor.constraint(equalToConstant: 14),
            iconView.widthAnchor.constraint(equalToConstant: 26),
            iconView.heightAnchor.constraint(equalToConstant: 26),
            pin.widthAnchor.constraint(equalToConstant: 22),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
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

    @objc private func pinClicked() {
        let exact = NSEvent.modifierFlags.contains(.option)
        onPin?(exact)
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
