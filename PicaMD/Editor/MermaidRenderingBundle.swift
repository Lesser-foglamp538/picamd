import Foundation

/// Mermaid is too large (~3 MB) to ship in the app bundle without
/// blowing past the lean-bundle goal. We download it once on first
/// use and cache it under `~/Library/Caches/PicaMD/Mermaid/`.
///
/// When the file is already present, render is offline-capable. When
/// it isn't (and we have no network), the WebView's `onerror` fallback
/// shows the source text in a code-block style.
enum MermaidRenderingBundle {
    private static let mermaidVersion = "11.14.0"
    private static let mermaidURL = "https://cdn.jsdelivr.net/npm/mermaid@\(mermaidVersion)/dist/mermaid.min.js"

    static let cacheDir: URL = {
        let base = (FileManager.default.urls(for: .cachesDirectory,
                                              in: .userDomainMask).first
                    ?? URL(fileURLWithPath: NSTemporaryDirectory()))
        return base.appendingPathComponent("PicaMD/Mermaid", isDirectory: true)
    }()

    static var localScriptURL: URL {
        cacheDir.appendingPathComponent("mermaid.min.js")
    }

    static var isAvailable: Bool {
        FileManager.default.fileExists(atPath: localScriptURL.path)
    }

    /// Synchronously make sure the cache dir exists. Schedule a
    /// best-effort download in the background. The first Mermaid
    /// block to render will fall back to the source until the
    /// download completes; subsequent renders pick up the cached file.
    static func ensureInstalled(then completion: @escaping @Sendable (Bool) -> Void) {
        try? FileManager.default.createDirectory(at: cacheDir,
                                                  withIntermediateDirectories: true)
        if isAvailable {
            completion(true)
            return
        }
        guard let remote = URL(string: mermaidURL) else {
            completion(false)
            return
        }
        let dst = localScriptURL
        URLSession.shared.dataTask(with: remote) { data, _, error in
            guard let data = data, error == nil else {
                completion(false)
                return
            }
            do {
                try data.write(to: dst, options: .atomic)
                completion(true)
            } catch {
                completion(false)
            }
        }.resume()
    }
}
