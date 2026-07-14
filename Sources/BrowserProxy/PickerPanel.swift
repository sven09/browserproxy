import AppKit

/// A borderless floating panel that can become key even as an accessory app,
/// and forwards key events to its controller.
final class PickerPanel: NSPanel {
    weak var keyHandler: PickerController?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        if keyHandler?.handleKeyDown(event) == true { return }
        super.keyDown(with: event)
    }

    /// Handles Esc/⌘. which arrive via performKeyEquivalent rather than keyDown.
    override func cancelOperation(_ sender: Any?) {
        keyHandler?.cancel()
    }
}
