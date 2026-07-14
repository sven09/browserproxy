import Foundation

/// Resolves and creates BrowserProxy's Application Support directory and provides
/// shared JSON coders used for on-disk persistence.
enum AppSupport {
    static let directoryName = "BrowserProxy"

    /// ~/Library/Application Support/BrowserProxy, created on first access.
    static var directory: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let dir = base.appendingPathComponent(directoryName, isDirectory: true)
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true
        )
        return dir
    }

    static func url(for file: String) -> URL {
        directory.appendingPathComponent(file)
    }

    static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
