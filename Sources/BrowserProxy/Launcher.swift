import AppKit

/// Opens URLs in a specific browser.
enum Launcher {
    static func open(_ url: URL, in browser: Browser, completion: (() -> Void)? = nil) {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        let name = browser.name
        // The error handler captures only Sendable values (url, name); it just
        // logs. We don't need to wait for the browser to finish launching before
        // advancing the queue, so run the completion synchronously on the main
        // actor right after issuing the open.
        NSWorkspace.shared.open(
            [url], withApplicationAt: browser.url, configuration: config
        ) { _, error in
            if let error {
                NSLog("BrowserProxy: failed to open \(url) in \(name): \(error)")
            }
        }
        completion?()
    }
}
