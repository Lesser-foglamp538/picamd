import Foundation

/// Tracks every PicaMD document that's currently open in a window.
/// Writes the list to a JSON file at
/// `~/Library/Application Support/PicaMD/active-documents.json`
/// every time it changes, so the MCP sidecar (which runs in a
/// separate process spawned by Claude Code) knows what the user is
/// working on without having to enumerate the filesystem.
///
/// The file is the *whole* contract between the main app and the
/// sidecar — no XPC, no sockets, just a single source of truth
/// updated atomically. Sidecar polls (cheap; <100 µs read) or, in a
/// future revision, can subscribe via `DispatchSourceFileSystemObject`.
///
/// Lifecycle:
///   - `register(url:)` when a window opens / saves-as a doc
///   - `unregister(url:)` when a window closes
///   - The JSON is rewritten atomically each time
@MainActor
final class ActiveDocumentsRegistry {
    static let shared = ActiveDocumentsRegistry()

    struct Entry: Codable, Equatable {
        var path: String       // absolute file path
        var openedAt: Date
    }

    private var entries: [String: Entry] = [:]   // keyed by absolute path
    private let queue = DispatchQueue(label: "PicaMD.ActiveDocumentsRegistry.io",
                                       qos: .utility)

    /// Where the registry file lives. The folder is created on first
    /// write. Public so the MCP sidecar can read the same path.
    static var registryFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                              in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("PicaMD/active-documents.json",
                                            isDirectory: false)
    }

    private init() {
        // Load any leftover registry from a previous launch — the
        // OS clears it eventually if PicaMD crashed without
        // unregistering, but on a clean restart the SwiftUI
        // DocumentGroup will re-register every restored document, so
        // stale entries get overwritten on first window-open anyway.
    }

    // MARK: - API

    func register(url: URL) {
        let key = url.standardizedFileURL.path
        if entries[key] == nil {
            entries[key] = Entry(path: key, openedAt: Date())
            persist()
        }
    }

    func unregister(url: URL) {
        let key = url.standardizedFileURL.path
        if entries.removeValue(forKey: key) != nil {
            persist()
        }
    }

    /// All currently-registered documents, sorted by openedAt
    /// descending so the most-recently opened comes first.
    func snapshot() -> [Entry] {
        entries.values.sorted { $0.openedAt > $1.openedAt }
    }

    // MARK: - Persistence

    private func persist() {
        let snapshot = self.snapshot()
        // Capture the URL on the main actor, BEFORE hopping queues —
        // `Self.registryFileURL` is implicitly `@MainActor`-isolated
        // (Swift 6 strict concurrency) so reading it from inside the
        // `queue.async { … }` Sendable closure is a compile error.
        let url = Self.registryFileURL
        // Hop off main: file IO can take ms, especially on iCloud Drive.
        queue.async {
            let dir = url.deletingLastPathComponent()
            try? FileManager.default.createDirectory(
                at: dir, withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            do {
                let data = try encoder.encode(snapshot)
                // Atomic write so a sidecar reading concurrently
                // never sees a half-written file.
                try data.write(to: url, options: .atomic)
            } catch {
                NSLog("PicaMD: failed to persist active-documents.json: \(error)")
            }
        }
    }
}
